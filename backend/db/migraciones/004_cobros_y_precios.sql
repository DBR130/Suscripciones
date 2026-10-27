-- 004: historial de pagos sin duplicados y cambios de precio (RF08).

-- Un mismo cobro (suscripción + fecha) solo se registra una vez. Así, aunque
-- el proceso de cobros corra dos veces el mismo día, no duplica pagos.
ALTER TABLE historial_pagos
  ADD CONSTRAINT historial_pagos_suscripcion_fecha_key UNIQUE (suscripcion_id, fecha_pago);

-- El índice UNIQUE anterior ya cubre las búsquedas por suscripcion_id.
DROP INDEX IF EXISTS idx_historial_pagos_suscripcion;

-- Cada vez que cambia el monto de una suscripción queda un registro aquí.
CREATE TABLE cambios_precio (
  id             SERIAL PRIMARY KEY,
  suscripcion_id INT           NOT NULL REFERENCES suscripciones(id) ON DELETE CASCADE,
  monto_anterior NUMERIC(12,2) NOT NULL CHECK (monto_anterior >= 0),
  monto_nuevo    NUMERIC(12,2) NOT NULL CHECK (monto_nuevo >= 0),
  fecha_cambio   TIMESTAMP     NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_cambios_precio_suscripcion ON cambios_precio (suscripcion_id, fecha_cambio DESC);
