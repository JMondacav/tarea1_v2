#!/usr/bin/env bash
# OSM: osmium recorta el PBF de Chile a la caja y ogr2ogr carga las tres capas en UNA pasada
# (el driver OSM de GDAL lee las capas intercaladas cuando se piden juntas).
# Se usa el osmconf.ini que trae GDAL; las etiquetas que no son columna (amenity en nodos,
# public_transport, bus, ...) se leen de other_tags como hstore en el SQL.
source "$(dirname "$0")/comun.sh"

PBF="${PBF:-$(ls -1 "$DATOS"/*.osm.pbf 2>/dev/null | head -n1 || true)}"
[ -n "$PBF" ] && [ -f "$PBF" ] || morir "falta datos/chile-latest.osm.pbf"
mkdir -p "$TMPD"
RECORTE="$TMPD/santiago_centro.osm.pbf"

FECHA=$(osmium fileinfo -g header.option.osmosis_replication_timestamp "$PBF" 2>/dev/null || true)
paso "OSM $(basename "$PBF"), datos al ${FECHA:-?}"
fuente osm "$PBF" "$FECHA" "Geofabrik; recorte $CAJA (osmium, estrategia smart)"

# Se recorta con 0,01° (~1 km) de margen: los paraderos justo fuera de la caja también
# cuentan como "cercanos" para edificios del borde (P2, P3). Lo demás se filtra a la caja en SQL.
AMPLIADA=$(echo "$CAJA" | awk -F, '{printf "%.4f,%.4f,%.4f,%.4f", $1-0.01, $2-0.01, $3+0.01, $4+0.01}')
osmium extract --overwrite --strategy smart --bbox "$AMPLIADA" -o "$RECORTE" "$PBF"
anotar osm "PBF recortado a la caja (bytes)" "$(stat -c %s "$RECORTE")"

sql -c "DROP SCHEMA IF EXISTS fuente_osm CASCADE; CREATE SCHEMA fuente_osm;"
ogr2ogr -f PostgreSQL "$(dsn_ogr)" "$RECORTE" points lines multipolygons \
  -lco SCHEMA=fuente_osm -lco GEOMETRY_NAME=geom -lco SPATIAL_INDEX=NONE -lco FID=fid \
  --config PG_USE_COPY YES -gt 250000

for t in points lines multipolygons; do
  anotar osm "fuente_osm.$t (ogr2ogr)" "$(sql -tA -c "SELECT count(*) FROM fuente_osm.$t")"
done
