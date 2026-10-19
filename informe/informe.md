---
title: "Santiago centro en PostGIS: ciudad construida y transporte público"
subtitle: "Tarea 1 · Procesamiento Masivo de Datos · ELE051-B · USM 2026-2"
author: "Joaquín Mondaca · Vicente Hermosilla · Andrés Pérez"
geometry:
  - top=1.2cm
  - bottom=1.2cm
  - left=1.3cm
  - right=1.3cm
fontsize: 8.5pt
papersize: a4
header-includes:
  - \usepackage{microtype}
  - \usepackage{parskip}
  - \usepackage{float}
  - \floatplacement{figure}{H}
  - \setlength{\parskip}{2pt}
  - \setlength{\abovecaptionskip}{2pt}
  - \setlength{\belowcaptionskip}{2pt}
---

**Fuentes y contexto.** OSM Geofabrik `chile-261017.osm.pbf` (datos al 2026-10-17T20:20:51Z, sha `67705ad6`), GTFS DTPM `GTFS_20261003.zip` (versión V168, vigencia 2026-10-03 a 2026-12-31, sha `e2dded09`), DPA 2023 (`comunas_cl.sql`, sha `761e0c5c`). Bounding Box: lon -70,75..-70,52 / lat -33,52..-33,36 (**SRID 5361**, UTM 19S SIRGAS-Chile). 30 comunas tocan la caja; **13** quedan íntegras. "OSM" = mapeo voluntario; "GTFS" = declaración oficial DTPM vigente. Repositorio: `JMondacav/tarea1_v2`.

## P1. Densidad de paraderos GTFS por comuna

La caja concentra **6 569 paraderos de bus** en 390,3 km2 netos, con una densidad media de **17,3 par./km2**.

| Comuna | km2 caja | % en caja | par./km2 | salidas/día |
|---|---:|---:|---:|---:|
| San Ramón | 0,16 | 3 % | **36,9** | 1 560 |
| Lo Espejo | 4,04 | 49 % | **29,2** | 34 520 |
| Lo Prado | 6,54 | 100 % | **29,2** | 56 717 |
| Conchalí | 10,94 | 100 % | **28,4** | 77 684 |
| Santiago | 23,18 | 100 % | 24,7 | 248 276 |
| Vitacura | 26,35 | 92 % | 7,4 | 62 006 |
| Lo Barnechea | 2,81 | 0 % | 1,8 | 1 693 |

**Interpretación.** Lo Prado, Conchalí y Lo Espejo superan a Santiago (>28 par./km2) por alta concentración de recorridos en corredores estructurantes (Av. Independencia, El Salto, Alameda-Pajaritos). Vitacura y Lo Barnechea presentan densidades bajas debido a patrones residenciales de baja densidad. San Ramón (3 % en caja) y Lo Barnechea (0 %) presentan distorsión estadística por efecto de borde.

**Plan.** `GroupAggregate` sobre `comunas_sub` (129 piezas <=64 vértices, Seq Scan externo en 0,022 ms) + inner `Index Scan using paraderos_gtfs_gix` filtrando `sirve_bus AND en_caja AND ST_Intersects`. **Tiempo: 7,3 ms**. `comunas_sub_gix` marca 0 usos porque las 129 piezas van al lado externo del Nested Loop (Seq Scan más eficiente en ese volumen).

![](salidas/mapas/p1_paraderos_km2.png){width=65%}

## P2. Cobertura a 500 m

El **98,9 % de los 119 015 edificios** tiene paradero de bus a <=500 m en ambas fuentes. Solo **1 355 edificios** (1,1 %) están lejos de alguna fuente.

| Comuna | Edif. | % lejos GTFS | % lejos OSM | solo GTFS lejos | solo OSM lejos |
|---|---:|---:|---:|---:|---:|
| Lo Barnechea | 78 | 57,7 % | 57,7 % | 0,0 % | 0,0 % |
| Huechuraba | 1 269 | 10,7 % | 10,4 % | 0,6 % | 0,2 % |
| Quilicura | 2 295 | 7,3 % | 7,3 % | 0,1 % | 0,1 % |
| Recoleta | 3 085 | 1,8 % | 1,0 % | **0,9 %** | 0,0 % |
| Providencia | 12 129 | 0,7 % | 0,1 % | **0,6 %** | 0,0 % |

*Acuerdo global:* Ambos cerca: **117 660** (98,9 %) | Lejos solo OSM: **25** (0,0 %) | Lejos solo GTFS: **215** (0,2 %) | Ambos lejos: **1 115** (0,9 %).

**Interpretación.** El déficit en Lo Barnechea y Huechuraba es orográfico y de baja densidad. En Recoleta y Providencia, el 0,9 % y 0,6 % "solo GTFS lejos" corresponde a paradas mapeadas en OSM pero sin servicios activos en el feed GTFS. Los 25 edificios "solo OSM lejos" corresponden a paradas no mapeadas por voluntarios en OSM. En el centro el acuerdo entre fuentes es prácticamente total.

**Plan.** Nested Loop Anti Join: `Parallel Seq Scan` en `edificios` (3 workers, externo) + inner `Index Scan using paraderos_gtfs_bus_gix` (parcial GiST, `st_expand(punto, 500)`). Sin índice: ~781 M comparaciones. Con índice: ~119 k accesos directos. **Tiempo: 404 ms** (paralelizado).

![](salidas/mapas/p2_lejos_de_paradero.png){width=88%}

## P3. Paraderos en una sola fuente

En la caja: GTFS bus **6 569** (375 sin OSM a <=50 m, **5,7 %**) | OSM bus_stop **6 572** (362 sin GTFS a <=50 m, **5,5 %**).

*Sensibilidad al umbral:* 20 m: 1 269 huerfanos | 50 m: 375 | 100 m: 136. Por cuartil de salidas: Q1 (2-115 salidas/día): **8,3 %** sin OSM vs Q4 (419-2 348 salidas): **4,0 %**.

**Interpretación.** El 5,7 % de paradas GTFS sin contraparte OSM se duplica en el cuartil de baja frecuencia (8,3 % en Q1), lo que revela subcobertura del mapeo voluntario en zonas periféricas. Los 362 nodos OSM sin GTFS corresponden a paradas sin trazados vigentes o desfase de geocodificación (el salto a 1 269 huérfanos a 20 m evidencia un offset posicional sistemático entre el poste y la calzada).

**Plan.** Nested Loop Anti Join: `Seq Scan` en `paraderos_gtfs` (6 569 filas, externo) + inner `Index Scan using paraderos_osm_gix` (`st_expand(geom, 50)`). Sin índice: 43 M evaluaciones `ST_DWithin`. Con índice: ~6 500 accesos. **Tiempo: 37,8 ms**.

![](salidas/mapas/p3_solo_una_fuente.png){width=65%}

## P4. Km de red de bus por comuna

Km de red unida por ruta y sentido dentro de la caja (trazados de ida y vuelta contabilizados por separado):

| Comuna | km bus | rutas | km/km2 |
|---|---:|---:|---:|
| Santiago | 1 117,6 | 149 | 48,2 |
| Estación Central | 522,3 | 78 | 36,3 |
| Lo Prado | 208,1 | 68 | 31,8 |
| Providencia | 394,3 | 80 | 27,3 |
| La Granja | 15,1 | 20 | 14,0 |
| Lo Barnechea | 7,7 | 10 | 2,7 |

*Evaluación de ST_Subdivide (longitud total invariante: 8 403,2 km):*
Sin subdividir (30 polígonos): **475 ms** (referencia) | 256 vértices (34 piezas): 494 ms (+4 %) | 128 vértices (62 piezas): 620 ms (+31 %) | 64 vértices (129 piezas): 968 ms (+104 %) | 32 vértices (301 piezas): 1 634 ms (+244 %) | 16 vértices (749 piezas): 1 260 ms (+165 %).

**Interpretación.** Santiago lidera ampliamente (1 117 km) por convergencia troncal. `ST_Subdivide` resulta contraproducente: las comunas tienen geometrías simples (5 106 vértices totales); subdividirlas multiplica los pares línea-pieza y las consultas al índice sin simplificar el costo unitario de intersección.

**Plan.** Nested Loop: `Seq Scan` en `comunas` (30 filas, externo) + inner `Index Scan using red_ruta_gix` (**484 ms**). Con `comunas_sub` (64 vértices, 129 piezas) el tiempo asciende a **901 ms** (+86 %) por sobrecarga de accesos al índice GiST.

## P5. Salud cerca de los paraderos de la ruta I09

Ruta evaluada: **I09** (473 salidas/día hábil, máxima frecuencia en la caja). Total en caja: **24 paraderos**.

| Paradero (abreviado) | Establecimiento más cercano | Tipo OSM | Distancia |
|---|---|---|---:|
| PI387 / Paradero 12 Pajaritos | CESFAM Clotario Blest | clinic | 583 m |
| PI388 / Col. Sta. María de Maipú | CESFAM Clotario Blest | clinic | 712 m |
| PI395 / Paradero 6 Pajaritos | CESFAM Santiago Occidente | clinic | 145 m |
| PA215 / (M) La Moneda | Cruz Verde | pharmacy | 10 m |
| PI394 / Paradero 7 Pajaritos | Farmacias Ahumada | pharmacy | 75 m |

*Distribución:* Mediana: **121 m** | Máximo: **712 m** | **79,2 % de paraderos a <=400 m**.

**Interpretación.** En Av. Pajaritos (poniente), los paraderos distan entre 583 m y 712 m del CESFAM más próximo, distancia crítica para usuarios vulnerables. En el eje Alameda-La Moneda, la densidad de farmacias reduce la mediana a 121 m.

**Plan.** Nested Loop: `Seq Scan` en `p5_paraderos` (24 filas, externo) + `Limit 1` + inner `Index Scan using amenidades_salud_gix Order By geom <-> pa.geom` (KNN sobre índice parcial GiST de salud, 56 kB). Evita ordenar las 20 983 amenidades globales. **Tiempo: 0,5 ms**.

![](salidas/mapas/p5_salud_por_paradero.png){width=65%}

## P6. Hexágonos de 500 m (ciudad construida vs. red de bus)

**636 celdas** cubren la caja: **604 con edificios**, **34 con edificios pero sin rutas**. Correlación edificios-rutas: **0,18** (desacople espacial).

*Top celdas con más edificios y déficit de transporte:*
Celda 491 (Las Condes: 755 edif., 0 rutas; lon -70,57 / lat -33,43) | Celda 446 (Ñuñoa: 1 344 edif., 3 rutas) | Celda 445 (Ñuñoa: 765 edif., 2 rutas) | Celda 483 (Peñalolén: 702 edif., 2 rutas) | Celda 426 (Providencia: 456 edif., 1 ruta).

**Interpretación.** La baja correlación (0,18) confirma que la malla de buses prioriza vías troncales sobre tejido residencial interior. Las Condes oriente (celda 491, 755 edif. sin bus) y sectores de Ñuñoa evidencian celdas densas servidas únicamente por vías perimetrales. Las 34 celdas sin servicio formal representan déficit directo de cobertura.

**Plan.** `GroupAggregate` sobre Nested Loop: `Seq Scan` en `recorridos` (690 shapes) + inner `Index Scan using hex_gix` (GiST, 636 celdas, 690 usos). **Tiempo: 206 ms**. Sin índice: 438 840 evaluaciones completas de `ST_Intersects`.

![](salidas/mapas/p6_hexagonos.png){width=88%}

## P7. Pregunta propia: jerarquía vial OSM de los recorridos de bus

**Pregunta y método:** ¿Por qué jerarquías viales de OSM circulan los buses del GTFS y cuánto no coincide con calles mapeadas? Muestreo cada 50 m de rutas GTFS ponderado por salidas diarias, asociado vía KNN (<=20 m) al índice parcial `calles_bus_gix`.

| Jerarquía vial OSM | km de red | bus-km/día | % bus-km |
|---|---:|---:|---:|
| Primaria | 2 891,7 | 286 511 | **36,8 %** |
| Secundaria | 2 180,6 | 202 250 | **26,0 %** |
| Terciaria | 1 439,5 | 131 831 | 16,9 % |
| Solo bus (carril exclusivo) | 737,3 | 68 973 | 8,9 % |
| Autopista | 609,9 | 42 591 | 5,5 % |
| Local | 400,4 | 36 494 | 4,7 % |
| Servicio | 93,6 | 8 808 | 1,1 % |
| **Sin calle OSM a <=20 m** | 6,7 | 501 | **0,1 %** |

*Rutas con mayor tramo sin calle OSM (>=2 km en caja):* D17 (5,7 %), C26c (3,5 %), 117c (3,1 %).

**Interpretación.** El 62,8 % del bus-km diario discurre por vías primarias y secundarias, validando el modelo troncal del sistema RED. El 8,9 % en `solo_bus` refleja carriles exclusivos adecuadamente etiquetados en OSM. El residual de 0,1 % sin calle se debe a obras recientes, túneles o desfase GPS, certificando una completitud sobresaliente de OSM en corredores de transporte.

**Plan.** Nested Loop Left Join: `Seq Scan` en `p7_muestras` (2 000 filas, externo) + `Limit 1` + inner `Index Scan using calles_bus_gix Order By geom <-> muestras.geom, Filter: ST_DWithin(geom, punto, 20)`. El índice parcial filtra 30 007 vías peatonales/no vehiculares (~30 % del grafo vial). **Tiempo: 32,8 ms**.

![](salidas/mapas/p7_vias_del_bus.png){width=65%}

## Decisiones del pipeline

**Infraestructura y reproducibilidad.** PostGIS 16-3.4 oficial sin capas personalizadas. Soporte (GDAL, osmium, psql, Python) en contenedor Ubuntu 24.04 (`herramientas`). Sincronización mediante healthcheck `pg_isready`. Carga automatizada íntegra en **139 s**. El procesamiento de DPA utilizó base temporal para no sobreescribir el esquema principal (`paso_dpa.sh`). Detección elástica de archivos de entrada (`GTFS*.zip`, `chile*.osm.pbf`).

**Proyección y caja territorial.** SRID 5361 (UTM 19S SIRGAS-Chile). Datos crudos preservados en `fuente_*` (4326/texto). Transformación única en `{osm,gtfs,dpa}_derivar.sql`. Densificación de la caja previa a proyectar. `ST_DWithin(geom, punto, 500)` garantiza radios euclidianos de 500 m exactos.

**Calidad geométrica y reparaciones OSM.** 16 multipolygons inválidos (todos autointersecciones de anillo, 0 líneas inválidas) corregidos con `ST_MakeValid + ST_CollectionExtract(..., 3)`: **10 edificios reparados**, **0 descartados**. Punto interior: `edificios.punto = ST_PointOnSurface(geom)` asegura inclusión dentro del polígono (el centroide cae fuera en formas en L o cóncavas).

**GTFS y modelado de red.** `stop_times.txt` (**1 098 529 filas**) cargado en streaming vía `COPY FROM STDIN`. Frecuencias expandidas para miércoles hábil representativo (`wednesday=1`, 14 542 tramos de `frequencies.txt` convertidos mediante `ceil((end-start)/headway)`): **68 834 salidas/día**. `red_ruta` consolida los shapes por ruta-sentido con `ST_Union` (grilla 1 m), evitando duplicar tramos compartidos: 14 932 km brutos de shapes vs. **12 357 km** de red unificada (-17 %).

**Auditoría de índices (`pg_stat_user_indexes`).** 32 índices en esquema `stgo`. Mayor frecuencia de uso: `calles_bus_gix` (169 191 usos), `paraderos_osm_gix` (151 860), `paraderos_gtfs_gix` (125 845), `edificios_punto_gix` (765). Índices con 0 usos: `amenidades_gix` y `calles_geom_gix` no fueron requeridos al operar sobre los parciales especializados `amenidades_salud_gix` y `calles_bus_gix`; `edificios_geom_gix` fue omitido al trabajar con `edificios.punto`; `comunas_caja_gix` y `comunas_sub_gix` no se ejecutaron porque el planificador selecciona Seq Scan sobre 30 y 129 filas. Todos poseen justificación técnica. En `ST_Subdivide`, la invariancia métrica (8 403,2 km en las 6 ejecuciones) certifica consistencia geométrica absoluta.