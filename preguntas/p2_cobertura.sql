-- P2 · % de edificios de cada comuna a más de 500 m de cualquier paradero, con GTFS y con OSM.
-- Anti-join NOT EXISTS + ST_DWithin desde el punto interior del edificio.
-- Los paraderos incluyen el margen de 600 m fuera de la caja: un edificio del borde no queda
-- "lejos" solo porque su paradero más cercano cae afuera.
\set ON_ERROR_STOP on
\pset footer off

CREATE TABLE preguntas.p2_edificio AS
SELECT e.id, s.gid,
       NOT EXISTS (SELECT 1 FROM stgo.paraderos_gtfs p WHERE p.sirve_bus AND ST_DWithin(p.geom, e.punto, 500)) AS lejos_gtfs,
       NOT EXISTS (SELECT 1 FROM stgo.paraderos_osm o WHERE ST_DWithin(o.geom, e.punto, 500))                  AS lejos_osm
FROM stgo.edificios e
JOIN stgo.comunas_sub s ON ST_Intersects(e.punto, s.geom);

CREATE TABLE preguntas.p2 AS
SELECT k.gid, k.nombre, count(*) AS edificios,
       round(100.0 * avg(lejos_gtfs::int), 1) AS pct_lejos_gtfs,
       round(100.0 * avg(lejos_osm::int), 1)  AS pct_lejos_osm,
       round(100.0 * avg((lejos_gtfs AND NOT lejos_osm)::int), 1) AS pct_solo_gtfs_lejos,
       round(100.0 * avg((lejos_osm AND NOT lejos_gtfs)::int), 1) AS pct_solo_osm_lejos,
       k.geom_caja AS geom
FROM preguntas.p2_edificio x JOIN stgo.comunas k USING (gid)
GROUP BY k.gid;

\echo '--- P2. Edificios a más de 500 m de un paradero, por fuente'
SELECT nombre, edificios, pct_lejos_gtfs, pct_lejos_osm, pct_solo_gtfs_lejos, pct_solo_osm_lejos
FROM preguntas.p2 ORDER BY pct_lejos_gtfs DESC;

\echo '--- P2. Toda la caja y tabla de acuerdo entre fuentes (edificios)'
SELECT lejos_gtfs, lejos_osm, count(*) AS edificios, round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM preguntas.p2_edificio GROUP BY 1, 2 ORDER BY 1, 2;

\echo '--- P2. Plan (anti-join contra el índice parcial de paraderos de bus)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT count(*) FROM stgo.edificios e
WHERE NOT EXISTS (SELECT 1 FROM stgo.paraderos_gtfs p WHERE p.sirve_bus AND ST_DWithin(p.geom, e.punto, 500));
