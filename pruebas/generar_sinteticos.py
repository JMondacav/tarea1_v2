#!/usr/bin/env python3
"""Genera datos SINTÉTICOS pequeños con la misma forma que las fuentes reales
(PBF de OSM, ZIP GTFS, comunas_cl.sql) para probar que el pipeline corre de punta a
punta en minutos. Los resultados con estos datos NO significan nada: solo sirven para
verificar que los scripts no fallan.

Uso:  python3 pruebas/generar_sinteticos.py   (requiere osmium en el PATH)
Deja: pruebas/sinteticos/{chile-latest.osm.pbf, GTFS_PRUEBA.zip, comunas_cl.sql}
"""
import csv, io, os, random, subprocess, zipfile
from xml.sax.saxutils import quoteattr

random.seed(51)
AQUI = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(AQUI, "sinteticos")
os.makedirs(OUT, exist_ok=True)

LON0, LON1, LAT0, LAT1 = -70.70, -70.57, -33.49, -33.40   # zona de prueba dentro de la caja
PASO = 0.004                                               # ~400 m entre calles

# ---------------------------------------------------------------- OSM
nodos, ways, rels = [], [], []
nid, wid = 1, 1

def nodo(lon, lat, tags=None):
    global nid
    nodos.append((nid, lon, lat, tags or {})); nid += 1
    return nid - 1

def way(refs, tags):
    global wid
    ways.append((wid, refs, tags)); wid += 1
    return wid - 1

lats = [LAT0 + i * PASO for i in range(int((LAT1 - LAT0) / PASO) + 1)]
lons = [LON0 + j * PASO for j in range(int((LON1 - LON0) / PASO) + 1)]
grid = {(i, j): nodo(lo, la) for i, la in enumerate(lats) for j, lo in enumerate(lons)}
for i in range(len(lats)):
    way([grid[i, j] for j in range(len(lons))], {"highway": "primary" if i % 5 == 0 else "residential", "name": f"Calle {i}"})
for j in range(len(lons)):
    way([grid[i, j] for i in range(len(lats))], {"highway": "secondary" if j % 5 == 0 else "residential", "name": f"Avenida {j}"})
# un sendero peatonal (no vehicular)
way([nodo(LON0 + 0.001, LAT0 + 0.001), nodo(LON0 + 0.02, LAT0 + 0.015)], {"highway": "footway"})

# edificios: cuadrados de ~20 m en las manzanas; algunos "corbatín" inválidos
def cuadrado(lon, lat, d=0.0002, invalido=False):
    a = nodo(lon, lat); b = nodo(lon + d, lat); c = nodo(lon + d, lat + d); e = nodo(lon, lat + d)
    refs = [a, c, b, e, a] if invalido else [a, b, c, e, a]
    return refs

n_edif = 0
for i in range(len(lats) - 1):
    for j in range(len(lons) - 1):
        # densidad decreciente hacia el este, para que el mapa tenga gradiente
        k = int(12 * (1 - j / len(lons))) + random.randint(0, 3)
        for _ in range(k):
            lo = lons[j] + random.uniform(0.0004, PASO - 0.0008)
            la = lats[i] + random.uniform(0.0004, PASO - 0.0008)
            way(cuadrado(lo, la, invalido=random.random() < 0.02), {"building": random.choice(["yes", "house", "apartments"])})
            n_edif += 1

# amenidades: farmacias/clínicas como nodos, un hospital como polígono
for _ in range(25):
    nodo(random.uniform(LON0, LON1), random.uniform(LAT0, LAT1),
         {"amenity": random.choice(["pharmacy", "pharmacy", "clinic", "doctors", "school", "cafe"]), "name": "Amenidad"})
way(cuadrado(-70.64, -33.45, d=0.001), {"amenity": "hospital", "name": "Hospital de Prueba", "building": "hospital"})

# ---------------------------------------------------------------- GTFS
# 4 rutas de bus a lo largo de calles de la grilla + 1 línea de metro
rutas = [("B01", "101", 3, ("fila", 5)), ("B02", "102", 3, ("fila", 10)),
         ("B03", "201", 3, ("col", 5)), ("B04", "202", 3, ("col", 15)), ("L1", "L1", 1, ("fila", 15))]
stops, shapes, trips, stop_times, frequencies = [], [], [], [], []
stop_id = 1
for rid, rsn, rtype, (eje, idx) in rutas:
    if eje == "fila":
        pts = [(lo, lats[idx]) for lo in lons]
    else:
        pts = [(lons[idx], la) for la in lats]
    # ida = pts, vuelta = invertido con un pequeño desvío (variante)
    for dirn, seq in ((0, pts), (1, list(reversed(pts)))):
        sid = f"{rid}_{dirn}"
        dens = [(lo + random.uniform(-1e-5, 1e-5), la + random.uniform(-1e-5, 1e-5)) for lo, la in seq]
        filas = [(sid, la, lo, k + 1) for k, (lo, la) in enumerate(dens)]
        random.shuffle(filas)               # desordenado a propósito: el SQL debe ordenar
        shapes += filas
        # paraderos cada 2 nodos de grilla, ligeramente desplazados de la calle
        ids = []
        for k, (lo, la) in enumerate(seq[::2]):
            off = 0.00012 if dirn == 0 else -0.00012
            s_lon, s_lat = (lo, la + off) if eje == "fila" else (lo + off, la)
            stops.append((f"PA{stop_id}", f"PA{stop_id}", f"Paradero {stop_id}", s_lat, s_lon, 0))
            ids.append(f"PA{stop_id}")
            # 70% de los paraderos GTFS también están en OSM (a menos de 50 m)
            if rtype == 3 and random.random() < 0.7:
                nodo(s_lon + random.uniform(-0.0002, 0.0002), s_lat, {"highway": "bus_stop", "name": f"Paradero {stop_id}"})
            stop_id += 1
        if rtype == 3:
            frequencies.append((f"{rid}_{dirn}_0", "06:00:00", "09:00:00", 600))
        for t in range(6 if rtype == 3 else 12):
            tid = f"{rid}_{dirn}_{t}"
            trips.append((rid, "LAB", tid, dirn, sid))
            for k, s in enumerate(ids):
                hh = 6 + t
                stop_times.append((tid, f"{hh:02d}:{k:02d}:00", f"{hh:02d}:{k:02d}:00", s, k + 1))
# paraderos OSM sin contraparte GTFS
for _ in range(15):
    nodo(random.uniform(LON0, LON1), random.uniform(LAT0, LAT1), {"highway": "bus_stop"})
# una estación (location_type=1) que debe quedar fuera de paraderos_gtfs
stops.append(("EST1", "", "Estación de prueba", lats[15], lons[3], 1))

# ---------------------------------------------------------------- escribir OSM
osm = os.path.join(OUT, "prueba.osm")
with open(osm, "w", encoding="utf-8") as f:
    f.write('<?xml version="1.0" encoding="UTF-8"?>\n<osm version="0.6" generator="t1-prueba">\n')
    for i, lo, la, tags in nodos:
        if tags:
            f.write(f'<node id="{i}" version="1" lat="{la:.7f}" lon="{lo:.7f}">')
            for k, v in tags.items():
                f.write(f'<tag k={quoteattr(k)} v={quoteattr(v)}/>')
            f.write('</node>\n')
        else:
            f.write(f'<node id="{i}" version="1" lat="{la:.7f}" lon="{lo:.7f}"/>\n')
    for i, refs, tags in ways:
        f.write(f'<way id="{i}" version="1">' + "".join(f'<nd ref="{r}"/>' for r in refs))
        for k, v in tags.items():
            f.write(f'<tag k={quoteattr(k)} v={quoteattr(v)}/>')
        f.write('</way>\n')
    f.write('</osm>\n')
pbf = os.path.join(OUT, "chile-latest.osm.pbf")
subprocess.run(["osmium", "cat", "--overwrite", "-o", pbf, osm,
                "--output-header=osmosis_replication_timestamp=2026-01-01T00:00:00Z"], check=True)
os.remove(osm)

# ---------------------------------------------------------------- escribir GTFS
def csvtxt(header, rows, bom=False):
    b = io.StringIO()
    w = csv.writer(b, lineterminator="\r\n")
    w.writerow(header); w.writerows(rows)
    return ("﻿" if bom else "") + b.getvalue()

with zipfile.ZipFile(os.path.join(OUT, "GTFS_PRUEBA.zip"), "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("agency.txt", csvtxt(["agency_id", "agency_name", "agency_url", "agency_timezone"],
                                    [("DTPM", "Prueba", "https://example.org", "America/Santiago")]))
    z.writestr("routes.txt", csvtxt(["route_id", "agency_id", "route_short_name", "route_long_name", "route_type"],
                                    [(r, "DTPM", s, f"Ruta {s}", t) for r, s, t, _ in rutas], bom=True))
    z.writestr("trips.txt", csvtxt(["route_id", "service_id", "trip_id", "direction_id", "shape_id"], trips))
    z.writestr("stops.txt", csvtxt(["stop_id", "stop_code", "stop_name", "stop_lat", "stop_lon", "location_type"], stops))
    z.writestr("shapes.txt", csvtxt(["shape_id", "shape_pt_lat", "shape_pt_lon", "shape_pt_sequence"], shapes))
    z.writestr("stop_times.txt", csvtxt(["trip_id", "arrival_time", "departure_time", "stop_id", "stop_sequence"], stop_times))
    z.writestr("frequencies.txt", csvtxt(["trip_id", "start_time", "end_time", "headway_secs"], frequencies))
    z.writestr("calendar.txt", csvtxt(["service_id", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "start_date", "end_date"],
                                      [("LAB", 1, 1, 1, 1, 1, 0, 0, "20260101", "20261231")]))
    z.writestr("feed_info.txt", csvtxt(["feed_publisher_name", "feed_publisher_url", "feed_lang", "feed_start_date", "feed_end_date", "feed_version"],
                                       [("Prueba", "https://example.org", "es", "20260101", "20261231", "PRUEBA")]))

# ---------------------------------------------------------------- escribir DPA (formato tipo shp2pgsql)
cortes = [(-70.80, "13101", "Comuna Oeste"), (-70.66, "13102", "Comuna Centro"), (-70.61, "13103", "Comuna Este")]
with open(os.path.join(OUT, "comunas_cl.sql"), "w", encoding="utf-8") as f:
    f.write("SET client_encoding = 'UTF8';\nCREATE EXTENSION postgis;\nCREATE SCHEMA dpa2023;\nSET search_path = dpa2023, public;\n")   # falla inofensivamente
    f.write("CREATE TABLE comunas_cl (gid serial PRIMARY KEY, cut_com varchar(5), comuna varchar(80), "
            "region varchar(80), geom geometry(MultiPolygon, 4326));\n")
    bordes = [c[0] for c in cortes] + [-70.40]
    for k, (x0, cut, nom) in enumerate(cortes):
        x1 = bordes[k + 1]
        wkt = f"MULTIPOLYGON((({x0} -33.60,{x1} -33.60,{x1} -33.30,{x0} -33.30,{x0} -33.60)))"
        f.write(f"INSERT INTO comunas_cl (cut_com, comuna, region, geom) VALUES "
                f"('{cut}', '{nom}', 'Metropolitana', ST_GeomFromText('{wkt}', 4326));\n")

print(f"OK: {len(nodos)} nodos, {len(ways)} ways ({n_edif} edificios), {len(stops)} stops, "
      f"{len(shapes)} puntos de shape, {len(stop_times)} stop_times -> {OUT}")
