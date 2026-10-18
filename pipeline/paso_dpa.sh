#!/usr/bin/env bash
# DPA 2023 (Lab 03): el volcado se ejecuta en una base temporal y lo que crea se mueve a
# fuente_dpa. Así no importa qué esquema, extensiones o nombres traiga el archivo, y la base
# del trabajo no se ensucia si el volcado tiene errores.
source "$(dirname "$0")/comun.sh"

ARCH="${DPA_SQL:-$DATOS/comunas_cl.sql}"
[ -f "$ARCH" ] || morir "falta datos/comunas_cl.sql"
paso "DPA $(basename "$ARCH")"
mkdir -p "$TMPD"

TMPDB="pmd_dpa_tmp"
sql -c "DROP DATABASE IF EXISTS $TMPDB" -c "CREATE DATABASE $TMPDB"
PGDATABASE=$TMPDB sql -c "CREATE EXTENSION IF NOT EXISTS postgis"
PGDATABASE=$TMPDB psql -X -q -v ON_ERROR_STOP=0 -f "$ARCH" > "$TMPD/dpa.log" 2>&1 || true
anotar dpa "errores no fatales al ejecutar el volcado" "$(grep -c 'ERROR' "$TMPD/dpa.log" || true)"

# La tabla con geometría y "comuna" en el nombre, en cualquier esquema
read -r SCH TAB < <(PGDATABASE=$TMPDB sql -tA -F' ' -c "
  SELECT f_table_schema, f_table_name FROM geometry_columns
  WHERE f_table_name ILIKE '%comuna%' ORDER BY f_table_name LIMIT 1") || true
[ -n "${TAB:-}" ] || morir "el volcado no creó una tabla de comunas con geometría (ver trabajo_tmp/dpa.log)"

sql -c "DROP SCHEMA IF EXISTS fuente_dpa CASCADE; CREATE SCHEMA fuente_dpa;"
ogr2ogr -f PostgreSQL "$(dsn_ogr)" "PG:dbname=$TMPDB host=${PGHOST:-localhost} port=${PGPORT:-5432} user=${PGUSER:-pmd} password=${PGPASSWORD:-pmd}" \
  "$SCH.$TAB" -nln fuente_dpa.comunas -lco GEOMETRY_NAME=geom -lco SPATIAL_INDEX=NONE -overwrite
sql -c "DROP DATABASE $TMPDB"
anotar dpa "fuente_dpa.comunas desde $SCH.$TAB" "$(sql -tA -c 'SELECT count(*) FROM fuente_dpa.comunas')"
fuente dpa "$ARCH" "DPA 2023" "Laboratorio 03"
