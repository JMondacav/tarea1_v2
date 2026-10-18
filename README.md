# Tarea 1 · Santiago centro en PostGIS: OSM × GTFS

Procesamiento Masivo de Datos (ELE051-B / EIN102B) · USM 2026-2 · Paralelo 701
Integrantes: [COMPLETAR]

¿Cómo se relaciona la ciudad construida (OpenStreetMap) con la red de transporte público (GTFS de la DTPM)?

> Los valores `[COMPLETAR]` se copian de `resultados/carga_resumen.txt`, que se genera solo al correr `./cargar.sh`.

## 1. Reproducir

Se necesita Docker con `docker compose` v2 y unos 6 GB de disco libres.

```bash
# los tres archivos fuente en ./datos (ver §2)
docker compose up -d    # PostGIS (imagen oficial postgis/postgis:16-3.4)
./cargar.sh             # carga y transforma todo, crea índices y corre ANALYZE
./responder.sh          # preguntas P1-P7, uso de índices, GeoPackage y mapas
```

`cargar.sh` y `responder.sh` usan `docker compose run` sobre el servicio `herramientas` (Ubuntu 24.04 con GDAL, osmium, psql y Python). Ese servicio espera a que PostGIS responda y no queda corriendo. No hay rutas que editar.

| Comando | Deja |
|---|---|
| `./cargar.sh` | esquemas `fuente_osm`, `fuente_gtfs`, `fuente_dpa` y `stgo` en la base `pmd_t1`; `resultados/carga_resumen.txt` |
| `./responder.sh` | `resultados/p1…p8_*.txt` (resultado + plan), `salidas/santiago_t1.gpkg`, `salidas/mapas/*.png` |

Opcional, sin editar nada:
- `CAJA=-70.70,-33.48,-70.58,-33.40 ./cargar.sh` usa una caja más chica (si se usa, anótelo aquí).
- `RUTA=<route_short_name> ./responder.sh` fija la ruta de la P5. Si no se indica, se usa la ruta de bus con más salidas en día hábil.
- Desde el host: `localhost:55432`, base `pmd_t1`, usuario y clave `pmd`.

**Prueba sin descargar nada.** `python3 pruebas/generar_sinteticos.py` (necesita `osmium`) crea un PBF, un GTFS (con `frequencies.txt`) y un `comunas_cl.sql` sintéticos y pequeños. Si los copia a `datos/` en una copia aparte del repositorio y corre los tres comandos, el pipeline completo termina en segundos. Los números que salen así no significan nada.

## 2. Fuentes

No se versionan (`.gitignore`). Cada archivo queda registrado con su tamaño, `sha256` y la fecha que declara la propia fuente en `stgo.fuente`. Esa fecha también va al pie de cada mapa.

| Fuente | Archivo | Fecha de los datos | Descarga | Origen |
|---|---|---|---|---|
| OpenStreetMap, Chile | `chile-latest.osm.pbf` | [COMPLETAR: `osmosis_replication_timestamp`] | [COMPLETAR] | Geofabrik, `south-america/chile-latest.osm.pbf` |
| GTFS Santiago | [COMPLETAR `GTFS_AAAAMMDD.zip`] | [COMPLETAR: `feed_version` y vigencia] | [COMPLETAR] | DTPM, «GTFS vigente» |
| DPA 2023 | `comunas_cl.sql` | 2023 | del curso | Laboratorio 03 |

Caja: lon −70,75 … −70,52 · lat −33,52 … −33,36.

## 3. Organización

```
datos/*.osm.pbf ─ osmium (caja + 1 km) ─ ogr2ogr (1 pasada, 3 capas) ─▶ fuente_osm.points/lines/multipolygons
datos/GTFS*.zip ─ unzip -p | COPY FROM STDIN (cada .txt) ─────────────▶ fuente_gtfs.<archivo>   (texto)
datos/comunas_cl.sql ─ psql en base temporal ─ ogr2ogr ───────────────▶ fuente_dpa.comunas
                                   │  pipeline/sql/{osm,gtfs,dpa}_derivar.sql + indices.sql
                                   ▼
                         stgo.*  (SRID 5361, reparado, indexado)
                                   │  preguntas/p1..p8 ─▶ esquema preguntas ─▶ salidas/santiago_t1.gpkg ─▶ mapas/mapas.py
```

| Ruta | Para qué |
|---|---|
| `docker-compose.yml` | `postgis` (oficial, volumen `pmd_t1_datos_pg`) y `herramientas` (perfil aparte) |
| `herramientas/Dockerfile` | Ubuntu 24.04 + `gdal-bin`, `osmium-tool`, `postgresql-client`, Python (geopandas, matplotlib) |
| `pipeline/cargar.sh` | orquesta la carga; `paso_osm.sh`, `paso_gtfs.sh` y `paso_dpa.sh` traen cada fuente |
| `pipeline/sql/` | transformación a `stgo`, índices y resumen |
| `pipeline/responder.sh`, `preguntas/` | Parte C, exportación y mapas |
| `pruebas/generar_sinteticos.py` | datos de prueba |

## 4. Decisiones

**PostGIS sin modificar y las herramientas en otro contenedor.** La base corre la imagen oficial tal cual. GDAL, osmium y Python viven en una imagen Ubuntu 24.04 aparte, donde esos paquetes vienen del repositorio de la distribución. Así no hay que instalar nada sobre la imagen de PostGIS, y la versión de GDAL no depende de la distribución base de esa imagen.

**SRID 5361.** Todo `stgo` está en metros (UTM 19S, SIRGAS-Chile): `ST_DWithin(…, 500)` son 500 m y los GiST trabajan en el mismo sistema que las consultas. Las fuentes quedan en su sistema original (4326) en `fuente_*` y se transforman una sola vez. La caja se densifica antes de proyectarla, para que sus bordes sigan los meridianos y paralelos.

**OSM.** El recorte se hace con `osmium extract --strategy smart` (deja completos los polígonos que cruzan el borde) sobre la caja más 0,01°, y la carga con un solo `ogr2ogr` que lee las tres capas en una pasada. Se usa el `osmconf.ini` de GDAL sin cambios. Las etiquetas que no son columna (`amenity` de los nodos, `public_transport`, `bus`, `building:levels`, `shelter`) se leen de `other_tags` como `hstore` con una función que tolera filas mal formadas.

**Margen de 600 m para paraderos.** Edificios, calles y amenidades se quedan dentro de la caja. Los paraderos (OSM y GTFS) se cargan también hasta 600 m fuera, marcados `en_caja = false`. Los conteos usan solo los de la caja, pero las distancias consideran también los de afuera. Sin esto, un edificio del borde aparecería "lejos" de un paradero solo porque el más cercano cae al otro lado de la línea.

**Punto interior vs. polígono.** `edificios` guarda `geom` (MultiPolygon reparado) y `punto = ST_PointOnSurface(geom)`, que siempre cae dentro del polígono, a diferencia del centroide. Distancias y asignación a comuna o celda usan el punto: cada edificio cuenta una vez y se compara un punto contra un índice de puntos.

**Reparaciones.** Se cuentan las geometrías inválidas por motivo (`ST_IsValidReason`) antes de tocarlas. Se reparan con `ST_MakeValid` + `ST_CollectionExtract(…, 3)` y se descartan las que quedan vacías.

| | Filas |
|---|---|
| multipolygons inválidos (total) | [COMPLETAR] |
| motivo más frecuente | [COMPLETAR] |
| edificios reparados | [COMPLETAR] |
| edificios descartados tras reparar | [COMPLETAR] |

**GTFS: salidas reales con `frequencies.txt`.** Según la especificación GTFS, si un `trip_id` está en `frequencies.txt`, sus horarios en `stop_times` son una plantilla y el viaje sale cada `headway_secs` entre `start_time` y `end_time`. Cada fila de frecuencias aporta `ceil((end − start) / headway)` salidas, y un viaje sin frecuencias sale una vez. Se toma un **miércoles** como día hábil tipo (servicios con `wednesday = 1`; no se aplican las excepciones de `calendar_dates`, porque se busca un día típico y no una fecha). Con eso, `stgo.servicio_paradero` tiene las salidas diarias que pasan por cada paradero y `stgo.red_ruta` las salidas de cada ruta y sentido. `stop_times.txt`, con [COMPLETAR] filas, se carga en streaming con `COPY` y se agrega una sola vez.

**Paraderos GTFS.** Solo puntos de abordaje (`location_type` 0 o vacío). `sirve_bus` dice si pasa alguna ruta de bus, porque el feed también trae andenes de Metro. Todas las comparaciones con `bus_stop` de OSM usan `sirve_bus`.

**Recorridos y varios shapes por ruta.** `stgo.recorridos` tiene una LineString por `shape_id`: `ST_MakeLine(punto ORDER BY shape_pt_sequence::int)`, sin vértices repetidos, asociada a su ruta vía `trips.txt`. Para las preguntas de longitud **no se elige un shape**: `stgo.red_ruta` une todos los shapes de cada ruta y sentido (`ST_Union` tras ajustar a una grilla de 1 m). Donde las variantes comparten calle, el tramo cuenta una vez; donde se separan, se conservan los dos. Sumar todos los shapes inflaría los km, y quedarse con uno perdería los desvíos. La diferencia queda medida: km sumando shapes [COMPLETAR] contra km de red unida [COMPLETAR]. La P6 (rutas por celda) usa los shapes y cuenta `route_id` distintos.

**DPA.** El volcado del Lab 03 se ejecuta en una base temporal y su tabla de comunas se copia a `fuente_dpa` con `ogr2ogr`. Así no importa qué esquema, extensiones o comandos traiga el archivo, y la base del trabajo no se ensucia si el volcado tiene errores. Las columnas de nombre y código se reconocen entre nombres habituales. `comunas.geom_caja` es la parte de cada comuna dentro de la caja, y toda densidad se calcula sobre ella. `comunas_sub = ST_Subdivide(geom_caja, 64)`. El valor 64 se eligió con el experimento de la P4 (`resultados/p4_km_comuna.txt`).

**Índices.** GiST en cada geometría, más índices parciales donde una consulta siempre filtra lo mismo: `paraderos_gtfs WHERE sirve_bus` (P2, P3), `amenidades` de salud (P5) y `calles WHERE jerarquia <> 'no_vehicular'` (P7). Al final van `VACUUM ANALYZE` y `ANALYZE`. El uso se mide como diferencia de `pg_stat_user_indexes` antes y después de las preguntas (`resultados/p8_indices.txt`), sin reiniciar las estadísticas de la base.

## 5. Tablas e índices

[COMPLETAR: pegar la sección «Tablas de stgo» de `resultados/carga_resumen.txt`]

| Tabla `stgo` | Contenido |
|---|---|
| `edificios` | `building=*`: polígono reparado, `punto`, `area_m2`, `pisos` |
| `calles` | `highway=*` recortadas a la caja, con `jerarquia` resumida |
| `paraderos_osm` | nodos `highway=bus_stop` (caja + margen, `en_caja`) |
| `amenidades` | `amenity=*`, nodos y áreas (punto interior) |
| `paraderos_gtfs` | `stops.txt` de abordaje (caja + margen), `sirve_bus`, `salidas_dia` |
| `recorridos` | 1 LineString por `shape_id` |
| `red_ruta` | shapes unidos por ruta y sentido, `salidas_dia`, `km_red` |
| `rutas`, `viajes`, `servicio_paradero` | GTFS tipado y salidas en día hábil |
| `comunas`, `comunas_sub` | DPA 2023, completa y en la caja; piezas de 64 vértices |
| `registro`, `fuente`, `caja` | bitácora, fuentes y caja de estudio |

## 6. Qué no funcionó / limitaciones

[COMPLETAR con lo que ocurra al correrlo: tiempos, memoria, cambios de fuente.]

- Un paradero exactamente sobre el límite entre dos comunas cuenta en ambas.
- `red_ruta` ajusta a 1 m: dos variantes dibujadas por la misma calle pero separadas por más de 1 m quedan como líneas distintas y esos tramos se cuentan dos veces.
- El día hábil tipo ignora `calendar_dates` (feriados y excepciones puntuales).
- La P5 considera solo los paraderos de la ruta que están dentro de la caja.
