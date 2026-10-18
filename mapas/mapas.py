#!/usr/bin/env python3
"""Mapas del informe desde el GeoPackage de salidas (no necesita la base de datos).
Cada mapa lleva título, barra de color o leyenda, escala, norte y la fecha de las fuentes
(capa 'fuentes'). Uso: python3 mapas/mapas.py <gpkg> <carpeta_salida>
"""
import os
import sys

import geopandas as gpd
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.lines import Line2D  # noqa: E402
from shapely.geometry import Point  # noqa: E402

GPKG, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
plt.rcParams.update({"font.size": 9, "figure.dpi": 120})

leer = lambda capa: gpd.read_file(GPKG, layer=capa)  # noqa: E731
COMUNAS = leer("comunas")
_f = {r.clave: f"{r.archivo} [{r.fecha_datos}]" for r in leer("fuentes").itertuples()}
NOTA = f"OSM {_f.get('osm', '?')} · GTFS {_f.get('gtfs', '?')} · DPA 2023 · EPSG:5361"


def decorar(ax, nombres=False):
    COMUNAS.boundary.plot(ax=ax, color="#4d4d4d", lw=0.5, zorder=8)
    if nombres:
        for r in COMUNAS.itertuples():
            q = r.geometry.representative_point()
            ax.annotate(r.nombre, (q.x, q.y), ha="center", fontsize=6, color="#1a1a1a", zorder=9)
    ax.set_axis_off()
    ax.set_aspect("equal")
    x0, x1 = ax.get_xlim(); y0, y1 = ax.get_ylim()
    largo = next(v for v in (10000, 5000, 2000, 1000, 500, 200) if v <= (x1 - x0) / 4)
    ax.plot([x0 + 0.03 * (x1 - x0)] * 2, [y0, y0], alpha=0)  # mantiene límites
    xb, yb = x0 + 0.03 * (x1 - x0), y0 + 0.04 * (y1 - y0)
    ax.plot([xb, xb + largo], [yb, yb], color="k", lw=2.5, solid_capstyle="butt", zorder=10)
    ax.text(xb + largo / 2, yb + 0.012 * (y1 - y0), f"{largo / 1000:g} km", ha="center", fontsize=7, zorder=10)
    ax.text(x1 - 0.04 * (x1 - x0), y1 - 0.07 * (y1 - y0), "N\n▲", ha="center", va="center", fontsize=8, fontweight="bold")


def guardar(fig, archivo, titulo):
    fig.suptitle(titulo, fontsize=12, fontweight="bold", y=0.98)
    fig.text(0.5, 0.01, "Datos: " + NOTA, ha="center", fontsize=6.5, color="#555555")
    fig.savefig(os.path.join(OUT, archivo), bbox_inches="tight")
    plt.close(fig)
    print("  ", archivo)


# P1
g = leer("p1_comunas")
fig, ax = plt.subplots(figsize=(7.5, 6.5))
g.plot(column="por_km2", cmap="GnBu", legend=True, ax=ax,
       legend_kwds={"label": "paraderos de bus por km² (parte en la caja)", "shrink": 0.65})
decorar(ax, nombres=True)
guardar(fig, "p1_paraderos_km2.png", "P1. Densidad de paraderos de bus (GTFS) por comuna")

# P2
g = leer("p2_comunas")
tope = float(max(g.pct_lejos_gtfs.max(), g.pct_lejos_osm.max()))
fig, axs = plt.subplots(1, 2, figsize=(12, 5.5))
for ax, col, sub in ((axs[0], "pct_lejos_gtfs", "Paraderos GTFS (operador)"), (axs[1], "pct_lejos_osm", "bus_stop de OSM (voluntarios)")):
    g.plot(column=col, cmap="YlOrRd", vmin=0, vmax=tope, legend=True, ax=ax,
           legend_kwds={"label": "% de edificios a más de 500 m", "shrink": 0.6})
    decorar(ax, nombres=True); ax.set_title(sub)
guardar(fig, "p2_lejos_de_paradero.png", "P2. Edificios a más de 500 m de un paradero, según la fuente")

# P3
g, todos = leer("p3_sin_pareja"), leer("p3_gtfs_bus")
fig, ax = plt.subplots(figsize=(7.5, 7))
todos.plot(ax=ax, color="#c7c7c7", markersize=1.2)
g[g.caso == "solo_gtfs"].plot(ax=ax, color="#e6550d", markersize=6, zorder=5)
g[g.caso == "solo_osm"].plot(ax=ax, color="#3182bd", marker="s", markersize=6, zorder=5)
decorar(ax)
ax.legend(handles=[Line2D([], [], ls="", marker="o", color="#c7c7c7", label="paradero GTFS de bus"),
                   Line2D([], [], ls="", marker="o", color="#e6550d", label=f"solo en GTFS ({(g.caso == 'solo_gtfs').sum()})"),
                   Line2D([], [], ls="", marker="s", color="#3182bd", label=f"solo en OSM ({(g.caso == 'solo_osm').sum()})")],
          loc="lower right", fontsize=7, title="sin pareja a 50 m", title_fontsize=7)
guardar(fig, "p3_solo_una_fuente.png", "P3. Paraderos que aparecen en una sola fuente")

# P5
lin = leer("p5_lineas")
if len(lin):
    ruta, salud = leer("p5_ruta"), leer("p5_salud")
    x0, y0, x1, y1 = lin.total_bounds; m = 1000
    fig, ax = plt.subplots(figsize=(10, 6))
    ruta.plot(ax=ax, color="#9e9ac8", lw=2.5, zorder=2)
    salud.cx[x0 - m:x1 + m, y0 - m:y1 + m].plot(ax=ax, color="#31a354", marker="P", markersize=14, zorder=4)
    lin.plot(ax=ax, column="metros", cmap="magma_r", lw=1.5, legend=True, zorder=5,
             legend_kwds={"label": "metros al establecimiento de salud más cercano", "shrink": 0.6})
    gpd.GeoSeries([Point(l.coords[0]) for l in lin.geometry], crs=lin.crs).plot(ax=ax, color="k", markersize=9, zorder=6)
    ax.set_xlim(x0 - m, x1 + m); ax.set_ylim(y0 - m, y1 + m)
    decorar(ax)
    nombre = ruta.nombre_corto.iloc[0] if len(ruta) else "?"
    ax.legend(handles=[Line2D([], [], color="#9e9ac8", lw=2.5, label=f"ruta {nombre}"),
                       Line2D([], [], ls="", marker="o", color="k", label="paradero"),
                       Line2D([], [], ls="", marker="P", color="#31a354", label="farmacia, clínica, hospital o médico")],
              loc="upper left", fontsize=7)
    guardar(fig, "p5_salud_por_paradero.png", f"P5. Salud más cercana a cada paradero de la ruta {nombre}")

# P6 (mapa principal)
h, top = leer("p6_hex"), leer("p6_top10")
fig, axs = plt.subplots(1, 2, figsize=(13, 6))
for ax, col, cmap, lab, sub in ((axs[0], "edificios", "OrRd", "edificios por celda", "Ciudad construida (OSM)"),
                                (axs[1], "rutas_bus", "BuPu", "rutas de bus distintas por celda", "Oferta de recorridos (GTFS)")):
    h.plot(column=col, cmap=cmap, legend=True, ax=ax, edgecolor="white", lw=0.1,
           legend_kwds={"label": lab, "shrink": 0.6})
    top.boundary.plot(ax=ax, color="#00a650", lw=1.8, zorder=7)
    decorar(ax); ax.set_title(sub)
axs[0].legend(handles=[Line2D([], [], color="#00a650", lw=2, label="10 celdas: muchos edificios, pocas rutas")], loc="lower right", fontsize=7)
guardar(fig, "p6_hexagonos.png", "P6. Hexágonos de 500 m: edificios frente a rutas de bus")

# P7
mu = leer("p7_muestras")
paleta = {"autopista": "#54278f", "primaria": "#d7301f", "secundaria": "#fc8d59", "terciaria": "#fdcc8a",
          "local": "#9ecae1", "servicio": "#c6dbef", "solo_bus": "#31a354", "sin_calle": "#000000"}
fig, ax = plt.subplots(figsize=(7.5, 7))
for via, color in paleta.items():
    sub = mu[mu.via == via]
    if len(sub):
        sub.plot(ax=ax, color=color, markersize=5 if via == "sin_calle" else 0.5, zorder=6 if via == "sin_calle" else 3)
decorar(ax)
ax.legend(handles=[Line2D([], [], ls="", marker="o", color=c, label=v.replace("sin_calle", "sin calle OSM a 20 m"))
                   for v, c in paleta.items() if (mu.via == v).any()], loc="lower right", fontsize=7, title="vía bajo el bus", title_fontsize=7)
guardar(fig, "p7_vias_del_bus.png", "P7. Por qué vías de OSM pasan los recorridos de bus")
