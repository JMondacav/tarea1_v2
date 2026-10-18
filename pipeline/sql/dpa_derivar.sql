-- DPA: fuente_dpa.comunas -> stgo.comunas (5361) y stgo.comunas_sub (ST_Subdivide)
-- El volcado del Lab 03 no se edita: nombre y código se buscan entre nombres habituales.
\set ON_ERROR_STOP on

DO $$
DECLARE
  cols text[];
  c_nom text; c_cod text; c_geo text; srid int;
BEGIN
  SELECT array_agg(lower(column_name::text)) INTO cols
  FROM information_schema.columns WHERE table_schema = 'fuente_dpa' AND table_name = 'comunas';
  SELECT x INTO c_nom FROM unnest(ARRAY['comuna','nom_comuna','nom_com','nombre','name']) x WHERE x = ANY (cols) LIMIT 1;
  SELECT x INTO c_cod FROM unnest(ARRAY['cut_com','cod_comuna','cut','codigo_comuna','cod_com']) x WHERE x = ANY (cols) LIMIT 1;
  SELECT f_geometry_column, nullif(gc.srid, 0) INTO c_geo, srid
  FROM geometry_columns gc WHERE f_table_schema = 'fuente_dpa' AND f_table_name = 'comunas';
  IF c_nom IS NULL OR c_geo IS NULL THEN
    RAISE EXCEPTION 'fuente_dpa.comunas sin columna de nombre o geometría reconocible: %', cols;
  END IF;
  IF srid IS NULL THEN
    EXECUTE format('SELECT nullif(ST_SRID(%I), 0) FROM fuente_dpa.comunas LIMIT 1', c_geo) INTO srid;
  END IF;
  IF srid IS NULL THEN
    RAISE EXCEPTION 'La geometría de la DPA no declara SRID';
  END IF;

  INSERT INTO stgo.registro (etapa, descripcion)
  VALUES ('dpa', format('columnas usadas: nombre=%s, código=%s, geom=%s, SRID origen=%s', c_nom, coalesce(c_cod, '-'), c_geo, srid));

  DROP TABLE IF EXISTS stgo.comunas CASCADE;
  EXECUTE format($q$
    CREATE TABLE stgo.comunas AS
    SELECT %s AS cut, %I::text AS nombre,
           ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_Transform(ST_Union(ST_SetSRID(%I, %s)), 5361)), 3))
             ::geometry(MultiPolygon, 5361) AS geom
    FROM fuente_dpa.comunas GROUP BY 1, 2 $q$,
    CASE WHEN c_cod IS NULL THEN 'NULL::text' ELSE quote_ident(c_cod) || '::text' END, c_nom, c_geo, srid);
END $$;

-- Comunas que tocan la caja. geom_caja = la parte dentro de la caja: es la superficie donde
-- existen los datos OSM/GTFS cargados, así que toda densidad se calcula sobre ella.
DELETE FROM stgo.comunas k USING stgo.caja c WHERE NOT ST_Intersects(k.geom, c.geom);
ALTER TABLE stgo.comunas ADD COLUMN gid serial PRIMARY KEY;
ALTER TABLE stgo.comunas ADD COLUMN geom_caja geometry(MultiPolygon, 5361);
UPDATE stgo.comunas k SET geom_caja = ST_Multi(ST_CollectionExtract(ST_Intersection(k.geom, c.geom), 3)) FROM stgo.caja c;
ALTER TABLE stgo.comunas ADD COLUMN km2_total double precision;
ALTER TABLE stgo.comunas ADD COLUMN km2_caja double precision;
UPDATE stgo.comunas SET km2_total = ST_Area(geom) / 1e6, km2_caja = ST_Area(geom_caja) / 1e6;

-- Piezas de a lo más 64 vértices. Se eligió 64 midiendo en la P4 (que prueba varios valores):
-- piezas chicas = cajas envolventes ajustadas = el GiST descarta más candidatos.
DROP TABLE IF EXISTS stgo.comunas_sub CASCADE;
CREATE TABLE stgo.comunas_sub AS
SELECT row_number() OVER () AS pid, gid, nombre, geom
FROM (SELECT gid, nombre, ST_Subdivide(geom_caja, 64)::geometry(Polygon, 5361) AS geom FROM stgo.comunas) piezas;
ALTER TABLE stgo.comunas_sub ADD PRIMARY KEY (pid);

INSERT INTO stgo.registro (etapa, descripcion, n)
SELECT 'dpa', 'comunas que tocan la caja', count(*) FROM stgo.comunas
UNION ALL SELECT 'dpa', 'comunas enteras dentro de la caja', count(*) FROM stgo.comunas WHERE km2_caja > 0.999 * km2_total
UNION ALL SELECT 'dpa', 'vértices de las comunas completas', sum(ST_NPoints(geom)) FROM stgo.comunas
UNION ALL SELECT 'dpa', 'vértices de la parte en la caja', sum(ST_NPoints(geom_caja)) FROM stgo.comunas
UNION ALL SELECT 'dpa', 'piezas de comunas_sub (64 vértices)', count(*) FROM stgo.comunas_sub;
