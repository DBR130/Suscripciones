-- 007: minimización de datos en la detección (historial de SMS y "Compartir").
--
-- 1) fecha_aproximada: el texto del SMS no traía fecha (Nequi) y la fecha es
--    la hora de llegada. El mismo cobro puede llegar por la notificación
--    (postTime) y por el historial de SMS (hora de recepción) con unos
--    segundos de diferencia: con esta marca el backend lo reconoce como
--    repetido dentro de una tolerancia de 5 minutos (services/detecciones.js).
ALTER TABLE pagos_detectados
  ADD COLUMN fecha_aproximada BOOLEAN NOT NULL DEFAULT FALSE;

-- 2) Las compras normales ya no se guardan en el servidor: el celular solo
--    envía pagos de servicios conocidos y de comercios con patrón recurrente,
--    y el backend borra los que no terminan en una suscripción o un
--    candidato pendiente (purgarComprasNormales). Aquí se borran las que ya
--    estaban guardadas: pagos sin suscripción cuyo comercio no tiene un
--    candidato pendiente o confirmado. (Los alias del catálogo, como "Max" y
--    "HBO Max", los revisa además la tarea diaria con la misma regla del
--    código.)
DELETE FROM pagos_detectados p
WHERE p.suscripcion_id IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM candidatos_suscripcion c
    WHERE c.usuario_id = p.usuario_id
      AND lower(c.comercio_normalizado) = lower(p.comercio_normalizado)
      AND c.estado IN ('pendiente', 'confirmada')
  )
  AND NOT EXISTS (
    -- Por si el nombre del candidato es el del catálogo y el del pago un alias:
    -- se conservan los de cualquier comercio con candidato del usuario que
    -- comparta una palabra. La tarea diaria aplica luego la regla exacta.
    SELECT 1 FROM candidatos_suscripcion c
    WHERE c.usuario_id = p.usuario_id
      AND c.estado IN ('pendiente', 'confirmada')
      AND (' ' || lower(p.comercio_normalizado) || ' ') LIKE ('% ' || lower(c.comercio_normalizado) || ' %')
  );
