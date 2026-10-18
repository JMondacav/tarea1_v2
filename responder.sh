#!/usr/bin/env bash
# Parte C: corre las preguntas, guarda resultados/, exporta salidas/ y dibuja los mapas.
# Ruta de la P5 (opcional): RUTA=<route_short_name> ./responder.sh
set -euo pipefail
cd "$(dirname "$0")"
docker compose run --rm -e RUTA="${RUTA:-}" herramientas bash pipeline/responder.sh
