# Variables y funciones comunes. Uso: source pipeline/comun.sh
set -euo pipefail

RAIZ="${RAIZ:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DATOS="${DATOS:-$RAIZ/datos}"
TMPD="${TMPD:-$RAIZ/trabajo_tmp}"
# Caja santiago-centro (lon_min,lat_min,lon_max,lat_max en 4326)
CAJA="${CAJA:-}"; CAJA="${CAJA:--70.75,-33.52,-70.52,-33.36}"
export PGOPTIONS="${PGOPTIONS:--c client_min_messages=warning}"

sql()  { psql -X -q -v ON_ERROR_STOP=1 "$@"; }
paso() { printf '\n== %s · %s\n' "$(date +%H:%M:%S)" "$*"; }
morir(){ printf '\nERROR: %s\n' "$*" >&2; exit 1; }

dsn_ogr() {
  printf 'PG:host=%s port=%s dbname=%s user=%s password=%s' \
    "${PGHOST:-localhost}" "${PGPORT:-5432}" "${PGDATABASE:-pmd_t1}" "${PGUSER:-pmd}" "${PGPASSWORD:-pmd}"
}

# anotar <etapa> <descripcion> [n]  -> fila en stgo.registro
anotar() {
  # (las variables :'x' de psql solo se expanden leyendo de stdin, no con -c)
  sql -v e="$1" -v d="$2" -v n="${3:-}" <<< \
    "INSERT INTO stgo.registro (etapa, descripcion, n) VALUES (:'e', :'d', NULLIF(:'n','')::bigint);"
}

# fuente <clave> <archivo> <fecha de los datos> [comentario] -> fila en stgo.fuente
fuente() {
  sql -v c="$1" -v a="$(basename "$2")" -v b="$(stat -c %s "$2")" \
      -v h="$(sha256sum "$2" | cut -c1-64)" -v f="$3" -v m="${4:-}" <<< "
    INSERT INTO stgo.fuente (clave, archivo, bytes, sha256, fecha_datos, comentario)
    VALUES (:'c', :'a', :'b', :'h', NULLIF(:'f',''), NULLIF(:'m',''))
    ON CONFLICT (clave) DO UPDATE SET archivo = EXCLUDED.archivo, bytes = EXCLUDED.bytes,
      sha256 = EXCLUDED.sha256, fecha_datos = EXCLUDED.fecha_datos, comentario = EXCLUDED.comentario;"
}
