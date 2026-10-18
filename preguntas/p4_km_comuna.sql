-- P4 · Km de recorrido de bus por comuna: red de cada ruta y sentido (stgo.red_ruta, variantes
-- unidas) recortada en el límite comunal con ST_Intersection.
-- Además se mide cuánto cambia el tiempo según cuánto se subdividen los polígonos.
\set ON_ERROR_STOP on
\pset footer off

CREATE TABLE preguntas.p4 AS
SELECT k.gid, k.nombre,
       round(sum(ST_Length(ST_Intersection(r.geom, s.geom)))::numeric / 1000, 1) AS km_bus,
       count(DISTINCT r.route_id) AS rutas,
       k.geom_caja AS geom
FROM stgo.red_ruta r
JOIN stgo.comunas_sub s ON ST_Intersects(r.geom, s.geom)
JOIN stgo.comunas k ON k.gid = s.gid
WHERE r.modo = 'bus'
GROUP BY k.gid;
ALTER TABLE preguntas.p4 ADD COLUMN km_por_km2 numeric;
UPDATE preguntas.p4 p SET km_por_km2 = round(p.km_bus / k.km2_caja::numeric, 1) FROM stgo.comunas k WHERE k.gid = p.gid;

\echo '--- P4. Km de red de bus por comuna (dentro de la caja; ida y vuelta cuentan aparte)'
SELECT nombre, km_bus, rutas, km_por_km2 FROM preguntas.p4 ORDER BY km_bus DESC;

-- Experimento: mismo cálculo con polígonos sin subdividir y subdivididos a 256/128/64/32/16
-- vértices. Cada variante corre 3 veces y se guarda el mejor tiempo (la primera calienta caché).
CREATE TABLE preguntas.p4_tiempos (max_vertices int, piezas int, ms_mejor numeric, km_total numeric);
DO $$
DECLARE v int; rep int; t0 timestamptz; ms numeric; mejor numeric; km numeric; n int;
BEGIN
  FOREACH v IN ARRAY ARRAY[0, 256, 128, 64, 32, 16] LOOP
    DROP TABLE IF EXISTS tmp_piezas;
    IF v = 0 THEN
      CREATE TEMP TABLE tmp_piezas AS SELECT gid, geom_caja::geometry(Geometry, 5361) AS geom FROM stgo.comunas;
    ELSE
      EXECUTE format('CREATE TEMP TABLE tmp_piezas AS SELECT gid, ST_Subdivide(geom_caja, %s)::geometry(Geometry, 5361) AS geom FROM stgo.comunas', v);
    END IF;
    CREATE INDEX ON tmp_piezas USING gist (geom);
    ANALYZE tmp_piezas;
    SELECT count(*) INTO n FROM tmp_piezas;
    mejor := NULL;
    FOR rep IN 1..3 LOOP
      t0 := clock_timestamp();
      SELECT sum(ST_Length(ST_Intersection(r.geom, p.geom))) / 1000 INTO km
      FROM stgo.red_ruta r JOIN tmp_piezas p ON ST_Intersects(r.geom, p.geom) WHERE r.modo = 'bus';
      ms := extract(epoch FROM clock_timestamp() - t0) * 1000;
      mejor := least(coalesce(mejor, ms), ms);
    END LOOP;
    INSERT INTO preguntas.p4_tiempos VALUES (v, n, round(mejor, 1), round(km, 1));
  END LOOP;
END $$;

\echo '--- P4. Efecto de ST_Subdivide en el tiempo (0 = sin subdividir; km_total debe ser igual en todas)'
SELECT CASE max_vertices WHEN 0 THEN 'sin subdividir' ELSE max_vertices::text END AS max_vertices,
       piezas, ms_mejor, km_total FROM preguntas.p4_tiempos ORDER BY max_vertices = 0 DESC, max_vertices DESC;

\echo '--- P4. Plan sin subdividir'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT k.gid, sum(ST_Length(ST_Intersection(r.geom, k.geom_caja)))
FROM stgo.red_ruta r JOIN stgo.comunas k ON ST_Intersects(r.geom, k.geom_caja)
WHERE r.modo = 'bus' GROUP BY k.gid;

\echo '--- P4. Plan con comunas_sub (64 vértices)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT s.gid, sum(ST_Length(ST_Intersection(r.geom, s.geom)))
FROM stgo.red_ruta r JOIN stgo.comunas_sub s ON ST_Intersects(r.geom, s.geom)
WHERE r.modo = 'bus' GROUP BY s.gid;
