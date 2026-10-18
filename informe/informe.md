---
title: "Santiago centro en PostGIS: ciudad construida y transporte público"
subtitle: "Tarea 1 · Procesamiento Masivo de Datos · USM 2026-2"
author: "[COMPLETAR]"
geometry: margin=2cm
fontsize: 10pt
---

<!-- Plantilla: máximo 6 páginas. Cifras de resultados/*.txt, mapas de salidas/mapas/.
     Las interpretaciones se escriben a partir de SUS resultados; las notas "Mirar:" se borran.
     PDF: pandoc informe/informe.md -o informe/informe.pdf -->

**Datos.** OSM Geofabrik al [COMPLETAR]; GTFS DTPM [COMPLETAR versión y vigencia], con salidas de un miércoles reconstruidas desde `frequencies.txt`; DPA 2023. Caja lon −70,75…−70,52 · lat −33,52…−33,36. SRID 5361. Repositorio: [COMPLETAR].

Todo lo que dice "OSM" describe lo que voluntarios han mapeado, y todo lo que dice "GTFS" describe lo que el operador declara.

## P1. Densidad de paraderos

[Tabla breve (5 más densas y 3 menos densas) + mapa `p1_paraderos_km2.png`.]
[Interpretación. Mirar: ¿la densidad se concentra en el centro o sigue los ejes? Cuidado con las comunas con poco `pct_en_caja`.]

## P2. Cobertura a 500 m

[Tabla por comuna con % lejos según GTFS y según OSM + tabla de acuerdo entre fuentes + mapa `p2_lejos_de_paradero.png`.]
[Interpretación. Mirar: ¿qué comunas quedan peor? ¿El orden cambia según la fuente? La tabla de acuerdo dice cuántos edificios cambian de categoría al cambiar de fuente.]

## P3. Paraderos en una sola fuente

[Dos cifras + tabla por cuartil de salidas + sensibilidad 20/50/100 m + mapa `p3_solo_una_fuente.png`.]
[Interpretación. Mirar: si a OSM le faltan sobre todo los paraderos de pocas salidas, la brecha es de mapeo en zonas periféricas; los "solo OSM" pueden ser paraderos retirados.]

## P4. Km de red de bus por comuna

[Tabla km por comuna y km/km² + tabla de tiempos según `ST_Subdivide`.]
[Interpretación + efecto de subdividir. Mirar: dónde está el mínimo de tiempo y por qué (bbox más ajustadas contra más pares línea-pieza).]

## P5. Salud cerca de los paraderos de la ruta [COMPLETAR]

[Mediana, máximo, % a 400 m o menos + mapa `p5_salud_por_paradero.png`.]

## P6. Hexágonos de 500 m (mapa principal)

[Mapa `p6_hexagonos.png` + tabla de las 10 celdas.]
[Interpretación. Mirar: ¿qué barrios aparecen? ¿Están entre ejes troncales? ¿Qué dice la correlación edificios-rutas?]

## P7. Pregunta propia: ¿por qué vías de OSM pasan los buses del GTFS?

**Pregunta.** ¿Qué parte de los bus-km diarios circula por cada jerarquía vial de OSM, y qué parte de los trazados del operador no coincide con ninguna calle mapeada?
**Método.** Red de cada ruta y sentido muestreada cada 50 m; para cada muestra, la calle OSM transitable más cercana a 20 m como máximo (KNN con índice parcial), con el peso de las salidas diarias de la ruta.
[Tabla por jerarquía + rutas con más tramo sin calle + mapa `p7_vias_del_bus.png`.]
[Interpretación. Mirar: concentración en primarias y secundarias; los tramos sin calle, ¿son errores del GTFS, calles faltantes en OSM o vías exclusivas con otra etiqueta?]

## Decisiones del pipeline

- **Infraestructura:** PostGIS oficial sin modificar; herramientas (GDAL, osmium, Python) en una imagen aparte.
- **SRID 5361**; las fuentes quedan intactas en `fuente_*` y se transforman una vez.
- **Punto interior** (`ST_PointOnSurface`) para distancias y conteos; polígono solo para áreas.
- **Reparaciones:** [COMPLETAR N] inválidos, motivo principal [COMPLETAR], [COMPLETAR N] edificios reparados, [COMPLETAR N] descartados.
- **Margen de 600 m** de paraderos para evitar el efecto borde.
- **Salidas reales:** `frequencies.txt` expandido para un miércoles; `stop_times` ([COMPLETAR N] filas) por `COPY`.
- **Varios shapes por ruta:** se unen por ruta y sentido (`red_ruta`) en vez de elegir uno; km sumando shapes [COMPLETAR] contra red unida [COMPLETAR].
- **Índices:** GiST en toda geometría + tres parciales. Inútiles según `p8_indices.txt`: [COMPLETAR y explicar por qué no se usaron].
- **Sin índice:** los anti-join pasarían de `Index Scan … geom && st_expand(…)` a comparar cada edificio contra todos los paraderos.
