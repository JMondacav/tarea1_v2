#!/usr/bin/env bash
# GTFS: cada .txt del ZIP va a fuente_gtfs.<archivo> con todas sus columnas como text,
# en streaming (unzip -p | COPY FROM STDIN): ni se descomprime a disco ni se inserta fila a fila.
source "$(dirname "$0")/comun.sh"

ZIP="${GTFS_ZIP:-$(ls -1 "$DATOS"/GTFS*.zip "$DATOS"/gtfs*.zip 2>/dev/null | sort | tail -n1 || true)}"
[ -n "$ZIP" ] && [ -f "$ZIP" ] || morir "falta datos/GTFS_AAAAMMDD.zip"
paso "GTFS $(basename "$ZIP")"
sql -c "DROP SCHEMA IF EXISTS fuente_gtfs CASCADE; CREATE SCHEMA fuente_gtfs;"

python3 - "$ZIP" > "$TMPD/gtfs_columnas.tsv" <<'PY'
# Lee la cabecera de cada .txt (sin importar si el ZIP trae carpeta) y quita BOM y comillas.
import csv, io, sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
for nombre in z.namelist():
    if not nombre.endswith(".txt"):
        continue
    with z.open(nombre) as f:
        primera = io.TextIOWrapper(f, encoding="utf-8-sig").readline()
    cols = next(csv.reader([primera]))
    print(nombre, ",".join(c.strip() for c in cols), sep="\t")
PY

while IFS=$'\t' read -r miembro cols; do
  tabla=$(basename "$miembro" .txt)
  defs=$(echo "$cols" | tr ',' '\n' | awk '{printf "%s\"%s\" text", (NR>1?", ":""), $0}')
  sql -c "CREATE UNLOGGED TABLE fuente_gtfs.\"$tabla\" ($defs)"
  unzip -p "$ZIP" "$miembro" | sed '1s/^\xEF\xBB\xBF//' \
    | sql -c "\\copy fuente_gtfs.\"$tabla\" FROM STDIN WITH (FORMAT csv, HEADER true)"
  anotar gtfs "fuente_gtfs.$tabla (COPY)" "$(sql -tA -c "SELECT count(*) FROM fuente_gtfs.\"$tabla\"")"
done < "$TMPD/gtfs_columnas.tsv"

for t in stops routes trips shapes stop_times; do
  [ "$(sql -tA -c "SELECT to_regclass('fuente_gtfs.$t') IS NOT NULL")" = t ] || morir "el GTFS no trae $t.txt"
done

FECHA=$(sql -tA -c "SELECT CASE WHEN to_regclass('fuente_gtfs.feed_info') IS NULL THEN NULL ELSE
  (SELECT string_agg(concat_ws(' ', j->>'feed_version', '(' || (j->>'feed_start_date') || '-' || (j->>'feed_end_date') || ')'), '; ')
   FROM (SELECT to_jsonb(f) j FROM fuente_gtfs.feed_info f) x) END")
fuente gtfs "$ZIP" "${FECHA:-$(basename "$ZIP" .zip)}" "DTPM, GTFS vigente al descargar"
