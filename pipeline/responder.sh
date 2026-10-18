#!/usr/bin/env bash
# Parte C: P1..P8 -> resultados/, capas -> salidas/santiago_t1.gpkg, mapas -> salidas/mapas/
source "$(dirname "$0")/comun.sh"
OUT="$RAIZ/resultados"; mkdir -p "$OUT" "$RAIZ/salidas/mapas"

sql -c "DROP SCHEMA IF EXISTS preguntas CASCADE; CREATE SCHEMA preguntas;"
sql -c "CREATE TABLE preguntas.indices_antes AS SELECT indexrelid, idx_scan FROM pg_stat_user_indexes;"
sleep 1   # las estadísticas de uso se publican con un pequeño retraso

for f in "$RAIZ"/preguntas/p[1-7]_*.sql; do
  n=$(basename "$f" .sql); paso "$n"
  sql -v ruta="${RUTA:-}" -f "$f" > "$OUT/$n.txt"
done
sleep 1
sql -f "$RAIZ/preguntas/p8_indices.sql" > "$OUT/p8_indices.txt"

GPKG="$RAIZ/salidas/santiago_t1.gpkg"
paso "Capas -> salidas/$(basename "$GPKG")"
rm -f "$GPKG"
capa() { ogr2ogr -f GPKG "$GPKG" "$(dsn_ogr)" -sql "$2" -nln "$1" -update -overwrite; }
capa comunas       "SELECT gid, cut, nombre, km2_total, km2_caja, geom_caja AS geom FROM stgo.comunas"
capa red_bus       "SELECT route_id, sentido, nombre_corto, salidas_dia, km_red, geom FROM stgo.red_ruta WHERE modo = 'bus'"
capa p1_comunas    "SELECT * FROM preguntas.p1"
capa p2_comunas    "SELECT * FROM preguntas.p2"
capa p3_sin_pareja "SELECT * FROM preguntas.p3"
capa p3_gtfs_bus   "SELECT stop_id, nombre, salidas_dia, geom FROM stgo.paraderos_gtfs WHERE en_caja AND sirve_bus"
capa p4_comunas    "SELECT * FROM preguntas.p4"
capa p5_lineas     "SELECT * FROM preguntas.p5"
capa p5_ruta       "SELECT r.nombre_corto, r.sentido, r.geom FROM stgo.red_ruta r JOIN preguntas.p5_ruta USING (route_id)"
capa p5_salud      "SELECT id, amenity, nombre, geom FROM stgo.amenidades WHERE amenity IN ('pharmacy','hospital','clinic','doctors')"
capa p6_hex        "SELECT * FROM preguntas.hex"
capa p6_top10      "SELECT * FROM preguntas.p6_top10"
capa p7_muestras   "SELECT id, nombre_corto, salidas_dia, coalesce(jerarquia, 'sin_calle') AS via, dist_m, geom FROM preguntas.p7_muestras"
capa fuentes       "SELECT clave, archivo, fecha_datos FROM stgo.fuente"

paso "Mapas"
python3 "$RAIZ/mapas/mapas.py" "$GPKG" "$RAIZ/salidas/mapas"
