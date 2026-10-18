-- P5 · Para cada paradero de una ruta, el establecimiento de salud OSM más cercano
-- (pharmacy, hospital, clinic, doctors). CROSS JOIN LATERAL + <-> + LIMIT 1.
-- Ruta: variable psql "ruta" (route_short_name). Si viene vacía se usa la ruta de bus con más
-- salidas en día hábil que tenga al menos 10 paraderos en la caja: la que más gente expone.
\set ON_ERROR_STOP on
\pset footer off
\if :{?ruta}
\else
  \set ruta ''
\endif

CREATE TABLE preguntas.p5_ruta AS
WITH candidatas AS (
  SELECT r.route_id, r.nombre_corto, sum(v.salidas_dia) AS salidas
  FROM stgo.rutas r JOIN stgo.viajes v USING (route_id)
  WHERE r.modo = 'bus'
  GROUP BY r.route_id, r.nombre_corto
)
SELECT route_id, nombre_corto, salidas FROM candidatas
WHERE nombre_corto = :'ruta'
   OR (:'ruta' = '' AND route_id IN (
        SELECT v.route_id FROM stgo.viajes v
        JOIN fuente_gtfs.stop_times st USING (trip_id)
        JOIN stgo.paraderos_gtfs p ON p.stop_id = st.stop_id AND p.en_caja
        GROUP BY v.route_id, v.trip_id HAVING count(*) >= 10))
ORDER BY coalesce(nombre_corto = :'ruta', false) DESC, salidas DESC
LIMIT 1;

\echo '--- P5. Ruta analizada'
SELECT nombre_corto AS ruta, salidas AS salidas_dia_habil FROM preguntas.p5_ruta;

-- Paraderos en orden: el viaje de la ruta con más paradas (sentido 0 primero)
CREATE TABLE preguntas.p5_paraderos AS
SELECT st.stop_sequence::int AS orden, p.stop_id, p.codigo, p.nombre, p.geom
FROM (SELECT v.trip_id FROM stgo.viajes v JOIN preguntas.p5_ruta USING (route_id)
      JOIN fuente_gtfs.stop_times st USING (trip_id)
      GROUP BY v.trip_id, v.sentido ORDER BY coalesce(v.sentido, 0), count(*) DESC LIMIT 1) t
JOIN fuente_gtfs.stop_times st USING (trip_id)
JOIN stgo.paraderos_gtfs p ON p.stop_id = st.stop_id AND p.en_caja;

CREATE TABLE preguntas.p5 AS
SELECT pa.orden, pa.codigo, pa.nombre AS paradero, cerca.amenity, cerca.nombre AS establecimiento,
       round(ST_Distance(pa.geom, cerca.geom)::numeric) AS metros,
       ST_MakeLine(pa.geom, cerca.geom)::geometry(LineString, 5361) AS geom
FROM preguntas.p5_paraderos pa
CROSS JOIN LATERAL (
  SELECT a.amenity, a.nombre, a.geom
  FROM stgo.amenidades a
  WHERE a.amenity IN ('pharmacy', 'hospital', 'clinic', 'doctors')
  ORDER BY a.geom <-> pa.geom
  LIMIT 1
) cerca;

\echo '--- P5. Establecimiento de salud más cercano por paradero'
SELECT orden, codigo, paradero, amenity, establecimiento, metros FROM preguntas.p5 ORDER BY orden;
SELECT count(*) AS paraderos, percentile_disc(0.5) WITHIN GROUP (ORDER BY metros) AS mediana_m,
       max(metros) AS max_m, round(100.0 * avg((metros <= 400)::int), 1) AS pct_a_400m
FROM preguntas.p5;

\echo '--- P5. Plan (KNN sobre el índice GiST parcial de salud)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT pa.stop_id, c.nombre
FROM preguntas.p5_paraderos pa
CROSS JOIN LATERAL (SELECT a.nombre FROM stgo.amenidades a
                    WHERE a.amenity IN ('pharmacy', 'hospital', 'clinic', 'doctors')
                    ORDER BY a.geom <-> pa.geom LIMIT 1) c;
