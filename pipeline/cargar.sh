#!/usr/bin/env bash
# Orquestador de la carga. Corre en el contenedor "herramientas" (lo llama ./cargar.sh),
# o en cualquier máquina con psql/ogr2ogr/osmium y las variables PG* definidas.
source "$(dirname "$0")/comun.sh"
INICIO=$(date +%s)
mkdir -p "$TMPD" "$RAIZ/resultados"

paso "Esquemas"
sql -c "DROP SCHEMA IF EXISTS preguntas CASCADE; DROP SCHEMA IF EXISTS stgo CASCADE;"
sql -f "$RAIZ/pipeline/sql/esquemas.sql"

bash "$RAIZ/pipeline/paso_osm.sh"
bash "$RAIZ/pipeline/paso_gtfs.sh"
bash "$RAIZ/pipeline/paso_dpa.sh"

for f in osm_derivar gtfs_derivar dpa_derivar indices; do
  paso "SQL $f"
  t0=$(date +%s)
  sql -v caja="$CAJA" -f "$RAIZ/pipeline/sql/$f.sql"
  anotar tiempo "$f.sql (s)" "$(( $(date +%s) - t0 ))"
done
anotar tiempo "carga completa (s)" "$(( $(date +%s) - INICIO ))"

paso "Resumen -> resultados/carga_resumen.txt"
sql -f "$RAIZ/pipeline/sql/resumen.sql" | tee "$RAIZ/resultados/carga_resumen.txt"
