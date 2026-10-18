-- Índices después de cargar (crearlos al final es más rápido que mantenerlos fila a fila)
\set ON_ERROR_STOP on
CREATE INDEX edificios_punto_gix   ON stgo.edificios USING gist (punto);
CREATE INDEX edificios_geom_gix    ON stgo.edificios USING gist (geom);
CREATE INDEX calles_geom_gix       ON stgo.calles USING gist (geom);
-- parcial: la P7 solo busca calles por donde puede pasar un bus
CREATE INDEX calles_bus_gix        ON stgo.calles USING gist (geom) WHERE jerarquia <> 'no_vehicular';
CREATE INDEX paraderos_osm_gix     ON stgo.paraderos_osm USING gist (geom);
CREATE INDEX paraderos_gtfs_gix    ON stgo.paraderos_gtfs USING gist (geom);
-- parcial: P2 y P3 comparan solo paraderos con servicio de bus
CREATE INDEX paraderos_gtfs_bus_gix ON stgo.paraderos_gtfs USING gist (geom) WHERE sirve_bus;
CREATE INDEX amenidades_gix        ON stgo.amenidades USING gist (geom);
CREATE INDEX amenidades_tipo_ix    ON stgo.amenidades (amenity);
-- parcial: la P5 busca el vecino más cercano solo entre establecimientos de salud
CREATE INDEX amenidades_salud_gix  ON stgo.amenidades USING gist (geom)
  WHERE amenity IN ('pharmacy', 'hospital', 'clinic', 'doctors');
CREATE INDEX recorridos_gix        ON stgo.recorridos USING gist (geom);
CREATE INDEX recorridos_ruta_ix    ON stgo.recorridos (route_id);
CREATE INDEX red_ruta_gix          ON stgo.red_ruta USING gist (geom);
CREATE INDEX comunas_gix           ON stgo.comunas USING gist (geom);
CREATE INDEX comunas_caja_gix      ON stgo.comunas USING gist (geom_caja);
CREATE INDEX comunas_sub_gix       ON stgo.comunas_sub USING gist (geom);
CREATE INDEX stop_times_trip_ix    ON fuente_gtfs.stop_times (trip_id);

VACUUM ANALYZE stgo.edificios;
VACUUM ANALYZE stgo.calles;
ANALYZE stgo.paraderos_osm, stgo.paraderos_gtfs, stgo.amenidades, stgo.recorridos, stgo.red_ruta,
        stgo.comunas, stgo.comunas_sub, stgo.rutas, stgo.viajes, stgo.servicio_paradero, fuente_gtfs.stop_times;

INSERT INTO stgo.registro (etapa, descripcion, n)
SELECT 'indices', 'índices en stgo', count(*) FROM pg_indexes WHERE schemaname = 'stgo';
