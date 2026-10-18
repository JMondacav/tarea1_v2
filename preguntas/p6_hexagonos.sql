-- P6 · Grilla hexagonal de 500 m de lado (ST_HexagonGrid, ~0,65 km² por celda) en una vista
-- materializada: edificios (por punto interior), rutas de bus distintas que cruzan la celda
-- (cualquier shape, así una variante que entra a la celda también cuenta).
-- "Más edificios y menos recorridos": de las celdas del cuartil superior en edificios, las que
-- tienen menos rutas (desempate: más edificios). Así una celda casi vacía sin buses no gana.
\set ON_ERROR_STOP on
\pset footer off

CREATE MATERIALIZED VIEW preguntas.hex AS
WITH celdas AS (
  SELECT h.i, h.j, h.geom FROM stgo.caja c, ST_HexagonGrid(500, c.geom) h
  WHERE ST_Intersects(h.geom, c.geom)
),
edif AS (
  SELECT c.i, c.j, count(*) AS n FROM celdas c JOIN stgo.edificios e ON ST_Intersects(e.punto, c.geom) GROUP BY 1, 2
),
rutas AS (
  SELECT c.i, c.j, count(DISTINCT r.route_id) AS n
  FROM celdas c JOIN stgo.recorridos r ON r.modo = 'bus' AND ST_Intersects(r.geom, c.geom)
  GROUP BY 1, 2
)
SELECT row_number() OVER (ORDER BY c.i, c.j)::int AS celda, c.i, c.j,
       coalesce(e.n, 0) AS edificios, coalesce(r.n, 0) AS rutas_bus,
       c.geom::geometry(Polygon, 5361) AS geom
FROM celdas c LEFT JOIN edif e USING (i, j) LEFT JOIN rutas r USING (i, j);
CREATE UNIQUE INDEX hex_celda_ix ON preguntas.hex (celda);
CREATE INDEX hex_gix ON preguntas.hex USING gist (geom);
ANALYZE preguntas.hex;

\echo '--- P6. La grilla'
SELECT count(*) AS celdas, count(*) FILTER (WHERE edificios > 0) AS con_edificios,
       count(*) FILTER (WHERE edificios > 0 AND rutas_bus = 0) AS con_edificios_sin_bus,
       percentile_disc(0.75) WITHIN GROUP (ORDER BY edificios) FILTER (WHERE edificios > 0) AS p75_edificios,
       round(corr(edificios, rutas_bus)::numeric, 2) AS correlacion
FROM preguntas.hex;

CREATE TABLE preguntas.p6_top10 AS
WITH umbral AS (SELECT percentile_disc(0.75) WITHIN GROUP (ORDER BY edificios) AS p75 FROM preguntas.hex WHERE edificios > 0)
SELECT h.*, (SELECT string_agg(k.nombre, ' / ') FROM stgo.comunas k WHERE ST_Intersects(k.geom, ST_PointOnSurface(h.geom))) AS comuna,
       round(ST_X(ST_Transform(ST_Centroid(h.geom), 4326))::numeric, 4) AS lon,
       round(ST_Y(ST_Transform(ST_Centroid(h.geom), 4326))::numeric, 4) AS lat
FROM preguntas.hex h, umbral u
WHERE h.edificios >= u.p75
ORDER BY h.rutas_bus, h.edificios DESC
LIMIT 10;

\echo '--- P6. 10 celdas con más edificios y menos rutas de bus'
SELECT celda, comuna, edificios, rutas_bus, lon, lat FROM preguntas.p6_top10 ORDER BY rutas_bus, edificios DESC;

\echo '--- P6. Plan (conteo de rutas por celda)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT h.celda, count(DISTINCT r.route_id)
FROM preguntas.hex h JOIN stgo.recorridos r ON r.modo = 'bus' AND ST_Intersects(r.geom, h.geom)
GROUP BY h.celda;
