\pset footer off
\echo '### Fuentes'
SELECT clave, archivo, pg_size_pretty(bytes) AS tamano, fecha_datos, left(sha256, 12) AS sha256, comentario FROM stgo.fuente ORDER BY clave;
\echo '### Tablas de stgo'
SELECT c.relname AS tabla, (xpath('//n/text()', query_to_xml(format('SELECT count(*) AS n FROM stgo.%I', c.relname), false, true, '')))[1]::text::bigint AS filas, pg_size_pretty(pg_total_relation_size(c.oid)) AS tamano,
       (SELECT string_agg(indexname, ', ' ORDER BY indexname) FROM pg_indexes i WHERE i.schemaname = 'stgo' AND i.tablename = c.relname) AS indices
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'stgo' AND c.relkind = 'r' ORDER BY 1;
\echo '### Registro de la carga'
SELECT etapa, descripcion, n FROM stgo.registro ORDER BY n_paso;
