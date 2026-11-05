-- 010: reapertura de candidatos descartados (ticket T7).
--
-- Un descarte no es para siempre: si un comercio descartado acumula después
-- 3 o más cobros periódicos con montos similares, el candidato vuelve a
-- pendiente UNA sola vez (reabierto = TRUE), con el motivo que se le muestra
-- al usuario ("Vimos 3 cobros mensuales de $99.900"). Si lo descarta otra
-- vez, ya no se reabre solo (solo con "Volver a proponer" en Perfil).
--
-- Para poder contar esos cobros, los pagos de un comercio descartado se
-- conservan hasta 400 días (ver purgarComprasNormales en
-- services/detecciones.js y la sección de privacidad de docs/deteccion.md).
ALTER TABLE candidatos_suscripcion
  ADD COLUMN reabierto BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN motivo TEXT NULL;
