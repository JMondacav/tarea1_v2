-- Uso de índices por las preguntas: diferencia entre la foto de pg_stat_user_indexes tomada
-- justo antes de P1 (preguntas.indices_antes) y la de ahora. No se reinician las estadísticas
-- globales de la base. idx_scan = 0 => ninguna pregunta usó ese índice.
\pset footer off
\echo '--- Índices usados por P1-P7'
SELECT a.schemaname AS esquema, a.relname AS tabla, a.indexrelname AS indice,
       a.idx_scan - coalesce(b.idx_scan, 0) AS usos,
       pg_size_pretty(pg_relation_size(a.indexrelid)) AS tamano
FROM pg_stat_user_indexes a
LEFT JOIN preguntas.indices_antes b ON b.indexrelid = a.indexrelid
WHERE a.schemaname IN ('stgo', 'fuente_gtfs', 'preguntas')
ORDER BY usos, esquema, tabla, indice;
