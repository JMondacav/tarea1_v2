-- GTFS: fuente_gtfs (texto) -> stgo.{rutas, viajes, servicio_paradero, paraderos_gtfs, recorridos, red_ruta}
-- Columnas opcionales del GTFS se leen con to_jsonb(fila) ->> 'col' (no fallan si faltan).
\set ON_ERROR_STOP on

------------------------------------------------------------------ rutas
DROP TABLE IF EXISTS stgo.rutas CASCADE;
CREATE TABLE stgo.rutas AS
SELECT route_id, nullif(route_short_name, '') AS nombre_corto, nullif(route_long_name, '') AS nombre_largo,
       route_type::int AS tipo,
       CASE WHEN route_type::int = 3 OR route_type::int BETWEEN 700 AND 799 THEN 'bus'
            WHEN route_type::int IN (1, 401, 402) THEN 'metro'
            WHEN route_type::int IN (2, 100, 101, 102, 106, 109) THEN 'tren'
            ELSE 'otro' END AS modo
FROM fuente_gtfs.routes;
ALTER TABLE stgo.rutas ADD PRIMARY KEY (route_id);

------------------------------------------------------------------ día hábil tipo
-- Un miércoles: servicios con wednesday = 1 en calendar.txt (si no hay calendar.txt, todos).
-- No se aplican las excepciones de calendar_dates: se busca un día hábil típico, no una fecha.
DROP TABLE IF EXISTS tmp_servicio_habil;
CREATE TEMP TABLE tmp_servicio_habil (service_id text PRIMARY KEY);
DO $$
BEGIN
  IF to_regclass('fuente_gtfs.calendar') IS NOT NULL THEN
    INSERT INTO tmp_servicio_habil SELECT DISTINCT service_id FROM fuente_gtfs.calendar WHERE wednesday = '1';
  ELSE
    INSERT INTO tmp_servicio_habil SELECT DISTINCT service_id FROM fuente_gtfs.trips;
  END IF;
END $$;
INSERT INTO stgo.registro (etapa, descripcion, n)
SELECT 'gtfs', 'service_id de día hábil (miércoles): ' || string_agg(service_id, ', '), count(*) FROM tmp_servicio_habil;

------------------------------------------------------------------ salidas por viaje
-- Especificación GTFS: si un trip_id aparece en frequencies.txt, sus horarios en stop_times son
-- una plantilla y el viaje sale cada headway_secs entre start_time y end_time. Cada fila de
-- frequencies aporta ceil((end_time - start_time) / headway_secs) salidas. Un viaje sin
-- frequencies sale una sola vez. Así "salidas" son buses reales, no plantillas.
DROP TABLE IF EXISTS tmp_salidas;
CREATE TEMP TABLE tmp_salidas (trip_id text PRIMARY KEY, salidas int);
DO $$
BEGIN
  IF to_regclass('fuente_gtfs.frequencies') IS NOT NULL THEN
    INSERT INTO tmp_salidas
    SELECT trip_id, sum(ceil((stgo.seg(end_time) - stgo.seg(start_time))::numeric / nullif(headway_secs::int, 0)))::int
    FROM fuente_gtfs.frequencies GROUP BY trip_id;
  END IF;
END $$;

DROP TABLE IF EXISTS stgo.viajes CASCADE;
CREATE TABLE stgo.viajes AS
SELECT t.trip_id, t.route_id, t.service_id,
       nullif(to_jsonb(t) ->> 'direction_id', '')::int AS sentido,
       nullif(to_jsonb(t) ->> 'shape_id', '')          AS shape_id,
       h.service_id IS NOT NULL                        AS dia_habil,
       s.trip_id IS NOT NULL                           AS por_frecuencia,
       CASE WHEN h.service_id IS NULL THEN 0 ELSE coalesce(s.salidas, 1) END AS salidas_dia
FROM fuente_gtfs.trips t
LEFT JOIN tmp_servicio_habil h USING (service_id)
LEFT JOIN tmp_salidas s USING (trip_id);
ALTER TABLE stgo.viajes ADD PRIMARY KEY (trip_id);
CREATE INDEX ON stgo.viajes (shape_id);
CREATE INDEX ON stgo.viajes (route_id);
ANALYZE stgo.viajes;

INSERT INTO stgo.registro (etapa, descripcion, n)
SELECT 'gtfs', 'viajes definidos por frecuencia', count(*) FILTER (WHERE por_frecuencia) FROM stgo.viajes
UNION ALL SELECT 'gtfs', 'viajes con horario fijo', count(*) FILTER (WHERE NOT por_frecuencia) FROM stgo.viajes
UNION ALL SELECT 'gtfs', 'salidas en día hábil (todas las rutas)', sum(salidas_dia) FROM stgo.viajes;

------------------------------------------------------------------ servicio por paradero
-- stop_times (~1 M filas) se agrega una sola vez a una tabla; las demás consultas usan esta.
DROP TABLE IF EXISTS stgo.servicio_paradero CASCADE;
CREATE TABLE stgo.servicio_paradero AS
SELECT st.stop_id,
       sum(v.salidas_dia)                                  AS salidas_dia,
       count(DISTINCT v.route_id) FILTER (WHERE v.salidas_dia > 0) AS rutas_dia,
       array_agg(DISTINCT r.modo ORDER BY r.modo)          AS modos
FROM fuente_gtfs.stop_times st
JOIN stgo.viajes v USING (trip_id)
JOIN stgo.rutas r USING (route_id)
GROUP BY st.stop_id;
ALTER TABLE stgo.servicio_paradero ADD PRIMARY KEY (stop_id);
ANALYZE stgo.servicio_paradero;

------------------------------------------------------------------ paraderos GTFS
DROP TABLE IF EXISTS stgo.paraderos_gtfs CASCADE;
CREATE TABLE stgo.paraderos_gtfs AS
WITH s AS (
  SELECT stop_id, nullif(to_jsonb(x) ->> 'stop_code', '') AS codigo, stop_name,
         coalesce(nullif(to_jsonb(x) ->> 'location_type', ''), '0') AS location_type,
         ST_SetSRID(ST_MakePoint(stop_lon::float8, stop_lat::float8), 4326) AS g
  FROM fuente_gtfs.stops x
)
SELECT s.stop_id, s.codigo, s.stop_name AS nombre,
       coalesce('bus' = ANY (sp.modos), false)   AS sirve_bus,
       coalesce(sp.modos, '{}')                  AS modos,
       coalesce(sp.salidas_dia, 0)               AS salidas_dia,
       coalesce(sp.rutas_dia, 0)                 AS rutas_dia,
       ST_Intersects(ST_Transform(s.g, 5361), c.geom) AS en_caja,   -- false = margen de 600 m
       ST_Transform(s.g, 5361)::geometry(Point, 5361) AS geom
FROM s
JOIN stgo.caja c ON ST_Intersects(ST_Transform(s.g, 5361), c.geom_margen)
LEFT JOIN stgo.servicio_paradero sp USING (stop_id)
WHERE s.location_type = '0';                    -- solo puntos de abordaje
ALTER TABLE stgo.paraderos_gtfs ADD PRIMARY KEY (stop_id);

INSERT INTO stgo.registro (etapa, descripcion, n)
SELECT 'gtfs', 'stops.txt (todo el feed)', count(*) FROM fuente_gtfs.stops
UNION ALL SELECT 'gtfs', 'paraderos_gtfs en la caja', count(*) FROM stgo.paraderos_gtfs WHERE en_caja
UNION ALL SELECT 'gtfs', 'paraderos_gtfs en el margen de 600 m (solo para distancias)', count(*) FROM stgo.paraderos_gtfs WHERE NOT en_caja
UNION ALL SELECT 'gtfs', 'paraderos_gtfs en la caja con servicio de bus', count(*) FROM stgo.paraderos_gtfs WHERE en_caja AND sirve_bus
UNION ALL SELECT 'gtfs', 'paraderos_gtfs en la caja sin salidas en día hábil', count(*) FROM stgo.paraderos_gtfs WHERE en_caja AND salidas_dia = 0;

------------------------------------------------------------------ recorridos (1 por shape)
INSERT INTO stgo.registro (etapa, descripcion, n)
SELECT 'gtfs', 'shapes.txt: puntos', count(*) FROM fuente_gtfs.shapes
UNION ALL SELECT 'gtfs', 'shapes.txt: shape_id', count(DISTINCT shape_id) FROM fuente_gtfs.shapes
UNION ALL SELECT 'gtfs', 'shape_id con shape_pt_sequence repetido', count(*)
  FROM (SELECT 1 FROM fuente_gtfs.shapes GROUP BY shape_id, shape_pt_sequence HAVING count(*) > 1) d
UNION ALL SELECT 'gtfs', 'shape_id usados por más de una ruta', count(*)
  FROM (SELECT shape_id FROM stgo.viajes WHERE shape_id IS NOT NULL GROUP BY shape_id HAVING count(DISTINCT route_id) > 1) d;

-- Ruta de cada shape (la de más viajes si hubiera más de una) y sus salidas en día hábil
DROP TABLE IF EXISTS tmp_shape_ruta;
CREATE TEMP TABLE tmp_shape_ruta AS
SELECT DISTINCT ON (shape_id) shape_id, route_id, sentido,
       sum(salidas_dia) OVER (PARTITION BY shape_id) AS salidas_dia
FROM (SELECT shape_id, route_id, max(sentido) AS sentido, count(*) AS n, sum(salidas_dia) AS salidas_dia
      FROM stgo.viajes WHERE shape_id IS NOT NULL GROUP BY shape_id, route_id) x
ORDER BY shape_id, n DESC, route_id;

DROP TABLE IF EXISTS stgo.recorridos CASCADE;
CREATE TABLE stgo.recorridos AS
WITH lineas AS (
  SELECT shape_id, count(*) AS n_puntos,
         -- shape_pt_sequence es texto en la fuente: ::int para que 10 vaya después de 9
         ST_RemoveRepeatedPoints(ST_MakeLine(
           ST_SetSRID(ST_MakePoint(shape_pt_lon::float8, shape_pt_lat::float8), 4326)
           ORDER BY shape_pt_sequence::int)) AS g
  FROM fuente_gtfs.shapes GROUP BY shape_id
)
SELECT l.shape_id, sr.route_id, r.nombre_corto, r.modo, sr.sentido, sr.salidas_dia, l.n_puntos,
       round((ST_Length(ST_Transform(l.g, 5361)) / 1000)::numeric, 3) AS largo_km,
       ST_Transform(l.g, 5361)::geometry(LineString, 5361) AS geom
FROM lineas l
JOIN tmp_shape_ruta sr USING (shape_id)
JOIN stgo.rutas r USING (route_id)
JOIN stgo.caja c ON ST_Intersects(l.g, c.geom_4326)
WHERE ST_NPoints(l.g) >= 2;
ALTER TABLE stgo.recorridos ADD PRIMARY KEY (shape_id);

------------------------------------------------------------------ red por ruta y sentido
-- Varios shapes por ruta (variantes, servicios cortos): en vez de elegir uno, se unen todos
-- los de la misma ruta y sentido. Donde las variantes comparten calle, el tramo queda una
-- sola vez; donde se separan, se conservan los dos. Así los km no se inflan por variantes
-- (pasaría sumando todos los shapes) ni se pierden desvíos (pasaría eligiendo un shape).
-- Se ajusta a una grilla de 1 m antes de unir para que vértices casi iguales coincidan.
DROP TABLE IF EXISTS stgo.red_ruta CASCADE;
CREATE TABLE stgo.red_ruta AS
SELECT route_id, coalesce(sentido, 0) AS sentido, min(nombre_corto) AS nombre_corto, min(modo) AS modo,
       count(*) AS n_shapes, sum(salidas_dia) AS salidas_dia,
       round(sum(largo_km), 3) AS km_suma_shapes,
       ST_Multi(ST_LineMerge(ST_Union(ST_SnapToGrid(geom, 1))))::geometry(MultiLineString, 5361) AS geom
FROM stgo.recorridos
GROUP BY route_id, coalesce(sentido, 0);
ALTER TABLE stgo.red_ruta ADD PRIMARY KEY (route_id, sentido);
ALTER TABLE stgo.red_ruta ADD COLUMN km_red double precision;
UPDATE stgo.red_ruta SET km_red = round((ST_Length(geom) / 1000)::numeric, 3);

INSERT INTO stgo.registro (etapa, descripcion, n)
SELECT 'gtfs', 'recorridos (shapes) que tocan la caja', count(*) FROM stgo.recorridos
UNION ALL SELECT 'gtfs', 'shapes descartados por no tener viajes', count(DISTINCT s.shape_id)
  FROM fuente_gtfs.shapes s LEFT JOIN tmp_shape_ruta t USING (shape_id) WHERE t.shape_id IS NULL
UNION ALL SELECT 'gtfs', 'red_ruta (ruta x sentido)', count(*) FROM stgo.red_ruta
UNION ALL SELECT 'gtfs', 'km suma de shapes (bus)', round(sum(km_suma_shapes)) FROM stgo.red_ruta WHERE modo = 'bus'
UNION ALL SELECT 'gtfs', 'km de red unida (bus)', round(sum(km_red)) FROM stgo.red_ruta WHERE modo = 'bus'
UNION ALL SELECT 'gtfs', 'recorridos que se cruzan a sí mismos (circuitos)', count(*) FROM stgo.recorridos WHERE NOT ST_IsSimple(geom);
