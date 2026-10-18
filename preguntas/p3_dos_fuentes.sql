-- P3 · Paraderos que existen en una sola fuente: GTFS de bus sin bus_stop OSM a < 50 m y al revés.
-- Anti-join en ambos sentidos. Se cuentan solo los que están dentro de la caja, pero la pareja
-- se busca también en el margen.
\set ON_ERROR_STOP on
\pset footer off

CREATE TABLE preguntas.p3 AS
SELECT 'solo_gtfs'::text AS caso, p.stop_id AS id, p.nombre, p.salidas_dia, p.geom
FROM stgo.paraderos_gtfs p
WHERE p.en_caja AND p.sirve_bus
  AND NOT EXISTS (SELECT 1 FROM stgo.paraderos_osm o WHERE ST_DWithin(o.geom, p.geom, 50))
UNION ALL
SELECT 'solo_osm', o.osm_id, o.nombre, NULL::bigint, o.geom
FROM stgo.paraderos_osm o
WHERE o.en_caja
  AND NOT EXISTS (SELECT 1 FROM stgo.paraderos_gtfs p WHERE p.sirve_bus AND ST_DWithin(p.geom, o.geom, 50));

\echo '--- P3. Sin contraparte a menos de 50 m'
SELECT 'GTFS bus' AS fuente, count(*) AS en_caja,
       (SELECT count(*) FROM preguntas.p3 WHERE caso = 'solo_gtfs') AS sin_pareja
FROM stgo.paraderos_gtfs WHERE en_caja AND sirve_bus
UNION ALL
SELECT 'OSM bus_stop', count(*), (SELECT count(*) FROM preguntas.p3 WHERE caso = 'solo_osm')
FROM stgo.paraderos_osm WHERE en_caja;

\echo '--- P3. ¿A qué paraderos GTFS les falta pareja? Por cuartil de salidas en día hábil'
SELECT cuartil, count(*) AS paraderos, min(salidas_dia) AS desde, max(salidas_dia) AS hasta,
       round(100.0 * avg(sin_pareja::int), 1) AS pct_sin_pareja_osm
FROM (SELECT p.salidas_dia, ntile(4) OVER (ORDER BY p.salidas_dia) AS cuartil,
             EXISTS (SELECT 1 FROM preguntas.p3 x WHERE x.caso = 'solo_gtfs' AND x.id = p.stop_id) AS sin_pareja
      FROM stgo.paraderos_gtfs p WHERE p.en_caja AND p.sirve_bus) q
GROUP BY cuartil ORDER BY cuartil;

\echo '--- P3. Sensibilidad al umbral'
SELECT u AS metros,
       count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM stgo.paraderos_osm o WHERE ST_DWithin(o.geom, p.geom, u))) AS gtfs_sin_osm
FROM stgo.paraderos_gtfs p CROSS JOIN (VALUES (20), (50), (100)) v(u)
WHERE p.en_caja AND p.sirve_bus GROUP BY u ORDER BY u;

\echo '--- P3. Plan (sentido GTFS -> OSM)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT count(*) FROM stgo.paraderos_gtfs p
WHERE p.en_caja AND p.sirve_bus
  AND NOT EXISTS (SELECT 1 FROM stgo.paraderos_osm o WHERE ST_DWithin(o.geom, p.geom, 50));
