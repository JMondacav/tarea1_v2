#!/usr/bin/env bash
# Carga completa: fuentes -> esquemas fuente_* -> esquema stgo (5361), índices y ANALYZE.
# Antes: docker compose up -d   y los tres archivos en ./datos (ver README §2).
# Caja más chica (opcional): CAJA=lon_min,lat_min,lon_max,lat_max ./cargar.sh
set -euo pipefail
cd "$(dirname "$0")"
docker compose run --rm -e CAJA="${CAJA:-}" herramientas bash pipeline/cargar.sh
