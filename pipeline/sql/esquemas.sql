-- Un esquema por fuente, tal como llega, y uno propio para lo derivado:
--   fuente_osm, fuente_gtfs, fuente_dpa : copia fiel de cada fuente (4326 / texto)
--   stgo                                 : tablas del trabajo, SRID 5361
--   preguntas                            : resultados de la Parte C (se rehace en cada corrida)
-- Así, rehacer una fuente es DROP SCHEMA de esa fuente y nada más.
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS hstore;      -- etiquetas OSM de other_tags

CREATE SCHEMA IF NOT EXISTS stgo;

CREATE TABLE IF NOT EXISTS stgo.registro (
  n_paso      serial PRIMARY KEY,
  cuando      timestamptz NOT NULL DEFAULT clock_timestamp(),
  etapa       text NOT NULL,
  descripcion text NOT NULL,
  n           bigint
);
CREATE TABLE IF NOT EXISTS stgo.fuente (
  clave       text PRIMARY KEY,
  archivo     text NOT NULL,
  bytes       bigint,
  sha256      text,
  fecha_datos text,
  comentario  text
);

-- other_tags de ogr2ogr viene como texto con sintaxis hstore. Si una fila viniera mal
-- formada, mejor perder sus etiquetas extra que abortar toda la carga.
CREATE OR REPLACE FUNCTION stgo.etiquetas(t text) RETURNS hstore
LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  RETURN coalesce(t, '')::hstore;
EXCEPTION WHEN others THEN
  RETURN ''::hstore;
END $$;

-- Segundos desde medianoche de una hora GTFS (puede pasar de 24:00:00)
CREATE OR REPLACE FUNCTION stgo.seg(h text) RETURNS int
LANGUAGE sql IMMUTABLE AS $$
  SELECT split_part(h, ':', 1)::int * 3600 + split_part(h, ':', 2)::int * 60 + split_part(h, ':', 3)::int
$$;
