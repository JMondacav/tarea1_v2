-- P7 (propia) · ¿Sobre qué jerarquía de vías de OSM circulan los buses del GTFS, y qué parte
-- de lo que el operador declara no coincide con ninguna calle mapeada?
--
-- La red de cada ruta y sentido (stgo.red_ruta) se muestrea cada 50 m dentro de la caja. Cada
-- muestra toma la calle OSM transitable más cercana a 20 m como máximo (KNN con LATERAL) y pesa
-- las salidas en día hábil de su ruta y sentido (frequencies.txt expandido). El resultado se lee
-- como "% de los bus-km diarios que pasan por cada tipo de vía".
-- Sin calle a 20 m = el trazado GTFS y la red OSM no coinciden: calle que falta en OSM, trazado
-- impreciso, o una vía exclusiva dibujada con otra etiqueta.
\set ON_ERROR_STOP on
\pset footer off

CREATE TABLE preguntas.p7_muestras AS
WITH partes AS (           -- red_ruta es MultiLineString: se muestrea cada parte por separado
  SELECT r.route_id, r.sentido, r.nombre_corto, r.salidas_dia, d.geom AS g
  FROM stgo.red_ruta r, ST_Dump(r.geom) d
  WHERE r.modo = 'bus' AND r.salidas_dia > 0
),
puntos AS (
  SELECT p.route_id, p.sentido, p.nombre_corto, p.salidas_dia,
         (ST_Dump(ST_LineInterpolatePoints(p.g, least(1.0, 50.0 / ST_Length(p.g)), true))).geom AS geom
  FROM partes p WHERE ST_Length(p.g) >= 25
)
SELECT row_number() OVER () AS id, pu.route_id, pu.sentido, pu.nombre_corto, pu.salidas_dia,
       v.jerarquia, round(v.d::numeric, 1) AS dist_m, pu.geom::geometry(Point, 5361) AS geom
FROM puntos pu
JOIN stgo.caja c ON ST_Intersects(pu.geom, c.geom)
LEFT JOIN LATERAL (
  SELECT k.jerarquia, ST_Distance(k.geom, pu.geom) AS d
  FROM stgo.calles k
  WHERE k.jerarquia <> 'no_vehicular' AND ST_DWithin(k.geom, pu.geom, 20)
  ORDER BY k.geom <-> pu.geom LIMIT 1
) v ON true;

\echo '--- P7. Bus-km diarios por jerarquía vial OSM'
SELECT coalesce(jerarquia, 'sin calle OSM a 20 m') AS via,
       round(count(*) * 0.05, 1) AS km_de_red,
       round(sum(salidas_dia) * 0.05) AS bus_km_dia,
       round(100.0 * sum(salidas_dia) / sum(sum(salidas_dia)) OVER (), 1) AS pct_bus_km
FROM preguntas.p7_muestras GROUP BY 1 ORDER BY pct_bus_km DESC;

\echo '--- P7. Rutas con más trazado sin calle OSM (con al menos 2 km en la caja)'
SELECT nombre_corto AS ruta, sentido, round(count(*) * 0.05, 1) AS km_en_caja,
       round(100.0 * avg((jerarquia IS NULL)::int), 1) AS pct_sin_calle
FROM preguntas.p7_muestras GROUP BY 1, 2 HAVING count(*) >= 40
ORDER BY pct_sin_calle DESC, km_en_caja DESC LIMIT 10;

\echo '--- P7. Plan (KNN con el índice parcial de calles transitables), 2000 muestras'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT m.id, v.jerarquia
FROM (SELECT id, geom FROM preguntas.p7_muestras LIMIT 2000) m
LEFT JOIN LATERAL (SELECT k.jerarquia FROM stgo.calles k
                   WHERE k.jerarquia <> 'no_vehicular' AND ST_DWithin(k.geom, m.geom, 20)
                   ORDER BY k.geom <-> m.geom LIMIT 1) v ON true;
