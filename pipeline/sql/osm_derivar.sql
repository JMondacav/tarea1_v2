-- OSM: fuente_osm (4326, sin reparar) -> stgo.{edificios, calles, paraderos_osm, amenidades}
-- Variable psql :caja = 'lon_min,lat_min,lon_max,lat_max'
\set ON_ERROR_STOP on

DROP TABLE IF EXISTS stgo.caja CASCADE;
CREATE TABLE stgo.caja AS
SELECT e AS geom_4326,
       -- se densifica antes de proyectar: en 5361 los bordes de la caja ya no son rectos
       ST_Transform(ST_Segmentize(e, 0.005), 5361) AS geom,
       -- margen de 600 m: paraderos de fuera que igual están a < 500 m de algo de dentro
       ST_Buffer(ST_Transform(ST_Segmentize(e, 0.005), 5361), 600, 'join=mitre') AS geom_margen
FROM (SELECT ST_MakeEnvelope(v[1], v[2], v[3], v[4], 4326) AS e
      FROM (SELECT string_to_array(:'caja', ',')::float8[] AS v) a) b;

-- Validez ANTES de reparar, por motivo
INSERT INTO stgo.registro (etapa, descripcion, n)
SELECT 'osm', 'multipolygons inválidos: ' || coalesce(split_part(ST_IsValidReason(geom), '[', 1), '?'), count(*)
FROM fuente_osm.multipolygons WHERE NOT ST_IsValid(geom) GROUP BY 2
UNION ALL
SELECT 'osm', 'multipolygons inválidos (total)', count(*) FROM fuente_osm.multipolygons WHERE NOT ST_IsValid(geom)
UNION ALL
SELECT 'osm', 'lines inválidas', count(*) FROM fuente_osm.lines WHERE NOT ST_IsValid(geom);

------------------------------------------------------------------ edificios
DROP TABLE IF EXISTS stgo.edificios CASCADE;
CREATE TABLE stgo.edificios (
  id        bigserial PRIMARY KEY,
  osm_id    text,
  es_relacion boolean,
  tipo      text,
  pisos     int,
  reparado  boolean,
  area_m2   double precision,
  geom      geometry(MultiPolygon, 5361),
  punto     geometry(Point, 5361)
);
INSERT INTO stgo.edificios (osm_id, es_relacion, tipo, pisos, reparado, area_m2, geom, punto)
SELECT coalesce(m.osm_id, m.osm_way_id), m.osm_id IS NOT NULL, m.building,
       CASE WHEN stgo.etiquetas(m.other_tags) -> 'building:levels' ~ '^\d{1,3}$'
            THEN (stgo.etiquetas(m.other_tags) -> 'building:levels')::int END,
       r.reparado, ST_Area(r.g), r.g, ST_PointOnSurface(r.g)
FROM fuente_osm.multipolygons m
CROSS JOIN LATERAL (
  SELECT NOT ST_IsValid(m.geom) AS reparado,
         ST_Transform(ST_Multi(ST_CollectionExtract(ST_MakeValid(m.geom), 3)), 5361) AS g
) r
WHERE m.building IS NOT NULL AND m.building <> 'no' AND NOT ST_IsEmpty(r.g);

-- osmium (smart) deja enteros los edificios que cruzan el borde: entra el que tiene su punto dentro
DELETE FROM stgo.edificios e USING stgo.caja c WHERE NOT ST_Intersects(e.punto, c.geom);

INSERT INTO stgo.registro (etapa, descripcion, n)
SELECT 'osm', 'edificios', count(*) FROM stgo.edificios
UNION ALL SELECT 'osm', 'edificios reparados con ST_MakeValid', count(*) FROM stgo.edificios WHERE reparado
UNION ALL SELECT 'osm', 'edificios descartados (vacíos tras reparar)', count(*)
  FROM fuente_osm.multipolygons
  WHERE building IS NOT NULL AND building <> 'no' AND ST_IsEmpty(ST_CollectionExtract(ST_MakeValid(geom), 3))
UNION ALL SELECT 'osm', 'edificios con building:levels', count(pisos) FROM stgo.edificios;

------------------------------------------------------------------ calles
DROP TABLE IF EXISTS stgo.calles CASCADE;
CREATE TABLE stgo.calles AS
SELECT l.fid AS id, l.osm_id, l.name AS nombre, l.highway AS clase,
       -- jerarquía resumida: los *_link se juntan con su vía
       CASE regexp_replace(l.highway, '_link$', '')
         WHEN 'motorway' THEN 'autopista' WHEN 'trunk' THEN 'autopista'
         WHEN 'primary' THEN 'primaria' WHEN 'secondary' THEN 'secundaria'
         WHEN 'tertiary' THEN 'terciaria' WHEN 'residential' THEN 'local'
         WHEN 'living_street' THEN 'local' WHEN 'unclassified' THEN 'local'
         WHEN 'service' THEN 'servicio' WHEN 'busway' THEN 'solo_bus'
         ELSE 'no_vehicular' END AS jerarquia,
       stgo.etiquetas(l.other_tags) -> 'oneway' AS sentido_unico,
       ST_Multi(ST_Transform(l.geom, 5361))::geometry(MultiLineString, 5361) AS geom
FROM fuente_osm.lines l
WHERE l.highway IS NOT NULL AND ST_IsValid(l.geom);
-- osmium también deja enteras las calles que cruzan el borde: se recortan a la caja
UPDATE stgo.calles k SET geom = ST_Multi(ST_CollectionExtract(ST_Intersection(k.geom, c.geom), 2))
FROM stgo.caja c WHERE NOT ST_Within(k.geom, c.geom);
DELETE FROM stgo.calles WHERE ST_IsEmpty(geom);
ALTER TABLE stgo.calles ADD COLUMN largo_m double precision;
UPDATE stgo.calles SET largo_m = ST_Length(geom);
ALTER TABLE stgo.calles ADD PRIMARY KEY (id);

INSERT INTO stgo.registro (etapa, descripcion, n)
SELECT 'osm', 'calles: ' || jerarquia, count(*) FROM stgo.calles GROUP BY jerarquia;

------------------------------------------------------------------ paraderos OSM
DROP TABLE IF EXISTS stgo.paraderos_osm CASCADE;
CREATE TABLE stgo.paraderos_osm AS
SELECT p.fid AS id, p.osm_id, p.name AS nombre, p.ref,
       stgo.etiquetas(p.other_tags) -> 'shelter' AS refugio,
       ST_Intersects(ST_Transform(p.geom, 5361), c.geom) AS en_caja,
       ST_Transform(p.geom, 5361)::geometry(Point, 5361) AS geom
FROM fuente_osm.points p JOIN stgo.caja c ON ST_Intersects(ST_Transform(p.geom, 5361), c.geom_margen)
WHERE p.highway = 'bus_stop';
ALTER TABLE stgo.paraderos_osm ADD PRIMARY KEY (id);

INSERT INTO stgo.registro (etapa, descripcion, n)
SELECT 'osm', 'paraderos_osm en la caja (nodos highway=bus_stop)', count(*) FROM stgo.paraderos_osm WHERE en_caja
UNION ALL
SELECT 'osm', 'paraderos_osm en el margen de 600 m (solo para distancias)', count(*) FROM stgo.paraderos_osm WHERE NOT en_caja
UNION ALL
SELECT 'osm', 'fuera por etiquetado: plataformas de bus sin highway=bus_stop', count(*)
FROM fuente_osm.points p JOIN stgo.caja c ON ST_Intersects(p.geom, c.geom_4326)
WHERE p.highway IS DISTINCT FROM 'bus_stop'
  AND stgo.etiquetas(p.other_tags) -> 'public_transport' = 'platform'
  AND stgo.etiquetas(p.other_tags) -> 'bus' = 'yes';

------------------------------------------------------------------ amenidades
DROP TABLE IF EXISTS stgo.amenidades CASCADE;
CREATE TABLE stgo.amenidades AS
WITH todas AS (
  SELECT 'nodo' AS origen, p.osm_id, p.name, stgo.etiquetas(p.other_tags) -> 'amenity' AS amenity, p.geom AS g
  FROM fuente_osm.points p
  UNION ALL
  SELECT 'area', coalesce(m.osm_id, m.osm_way_id), m.name, m.amenity,
         ST_PointOnSurface(ST_CollectionExtract(ST_MakeValid(m.geom), 3))
  FROM fuente_osm.multipolygons m WHERE m.amenity IS NOT NULL
)
SELECT row_number() OVER () AS id, t.origen, t.osm_id, t.name AS nombre, t.amenity,
       ST_Transform(t.g, 5361)::geometry(Point, 5361) AS geom
FROM todas t JOIN stgo.caja c ON ST_Intersects(t.g, c.geom_4326)
WHERE t.amenity IS NOT NULL;
ALTER TABLE stgo.amenidades ADD PRIMARY KEY (id);

INSERT INTO stgo.registro (etapa, descripcion, n)
SELECT 'osm', 'amenidades (' || origen || ')', count(*) FROM stgo.amenidades GROUP BY origen;
