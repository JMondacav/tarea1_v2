-- P1 · Paraderos GTFS de bus por comuna y densidad (paraderos / km² de la comuna dentro de la caja)
-- Punto en polígono contra comunas_sub (piezas de ≤ 64 vértices).
\set ON_ERROR_STOP on
\pset footer off

CREATE TABLE preguntas.p1 AS
SELECT k.gid, k.cut, k.nombre, round(k.km2_caja::numeric, 2) AS km2_caja,
       round((100 * k.km2_caja / k.km2_total)::numeric) AS pct_en_caja,
       coalesce(x.paraderos, 0) AS paraderos_bus,
       round((coalesce(x.paraderos, 0) / k.km2_caja)::numeric, 1) AS por_km2,
       coalesce(x.salidas, 0) AS salidas_dia,
       k.geom_caja AS geom
FROM stgo.comunas k
LEFT JOIN (
  SELECT s.gid, count(*) AS paraderos, sum(p.salidas_dia) AS salidas
  FROM stgo.comunas_sub s
  JOIN stgo.paraderos_gtfs p ON ST_Intersects(p.geom, s.geom)
  WHERE p.sirve_bus AND p.en_caja
  GROUP BY s.gid
) x USING (gid);

\echo '--- P1. Paraderos de bus GTFS por comuna (área dentro de la caja)'
SELECT nombre, km2_caja, pct_en_caja, paraderos_bus, por_km2, salidas_dia FROM preguntas.p1 ORDER BY por_km2 DESC;
SELECT sum(paraderos_bus) AS paraderos, round(sum(paraderos_bus) / sum(km2_caja), 1) AS por_km2_caja FROM preguntas.p1;

\echo '--- P1. Plan'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT s.gid, count(*)
FROM stgo.comunas_sub s
JOIN stgo.paraderos_gtfs p ON ST_Intersects(p.geom, s.geom)
WHERE p.sirve_bus AND p.en_caja
GROUP BY s.gid;
