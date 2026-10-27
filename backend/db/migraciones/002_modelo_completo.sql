-- 002: modelo completo según la especificación.
--
-- No borra datos: solo agrega columnas, renombra otras y convierte la columna
-- "activa" en "estado" antes de eliminarla.

-- ─── usuarios ────────────────────────────────────────────────────────────────
ALTER TABLE usuarios
  ADD COLUMN dias_anticipacion_recordatorio INT NOT NULL DEFAULT 3
    CONSTRAINT usuarios_dias_anticipacion_check
    CHECK (dias_anticipacion_recordatorio BETWEEN 0 AND 30),
  ADD COLUMN pais VARCHAR(2) NOT NULL DEFAULT 'CO',
  ADD COLUMN permiso_notificaciones BOOLEAN NOT NULL DEFAULT FALSE;

-- ─── suscripciones ───────────────────────────────────────────────────────────
ALTER TABLE suscripciones RENAME COLUMN nombre TO nombre_servicio;
ALTER TABLE suscripciones RENAME COLUMN precio TO monto;
ALTER TABLE suscripciones RENAME COLUMN ciclo  TO frecuencia;

-- Las restricciones CHECK viejas tienen nombres generados por PostgreSQL
-- (suscripciones_ciclo_check, suscripciones_precio_check). Se borran todas las
-- CHECK de la tabla, sin depender de su nombre, y se crean de nuevo abajo con
-- nombres claros.
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT conname FROM pg_constraint
    WHERE conrelid = 'suscripciones'::regclass AND contype = 'c'
  LOOP
    EXECUTE format('ALTER TABLE suscripciones DROP CONSTRAINT %I', r.conname);
  END LOOP;
END $$;

ALTER TABLE suscripciones
  ADD COLUMN es_prueba_gratis BOOLEAN     NOT NULL DEFAULT FALSE,
  ADD COLUMN fecha_fin_prueba DATE        NULL,
  ADD COLUMN origen           VARCHAR(15) NOT NULL DEFAULT 'manual',
  ADD COLUMN estado           VARCHAR(25) NOT NULL DEFAULT 'activa',
  ADD COLUMN fecha_deteccion  TIMESTAMP   NULL;

-- Conserva lo que decía la columna vieja antes de borrarla.
UPDATE suscripciones SET estado = CASE WHEN activa THEN 'activa' ELSE 'cancelada' END;
ALTER TABLE suscripciones DROP COLUMN activa;

-- dias_aviso NULL = usar la preferencia global del usuario.
ALTER TABLE suscripciones
  ALTER COLUMN dias_aviso DROP NOT NULL,
  ALTER COLUMN dias_aviso DROP DEFAULT;

ALTER TABLE suscripciones
  ADD CONSTRAINT suscripciones_monto_check      CHECK (monto >= 0),
  ADD CONSTRAINT suscripciones_moneda_check     CHECK (moneda IN ('COP', 'USD')),
  ADD CONSTRAINT suscripciones_frecuencia_check CHECK (frecuencia IN ('semanal', 'mensual', 'anual')),
  ADD CONSTRAINT suscripciones_origen_check     CHECK (origen IN ('manual', 'notificacion')),
  ADD CONSTRAINT suscripciones_estado_check     CHECK (estado IN ('activa', 'marcada_para_cancelar', 'cancelada')),
  ADD CONSTRAINT suscripciones_dias_aviso_check CHECK (dias_aviso IS NULL OR dias_aviso BETWEEN 0 AND 30),
  -- Si es prueba gratis, la fecha de fin es obligatoria.
  ADD CONSTRAINT suscripciones_prueba_check     CHECK (NOT es_prueba_gratis OR fecha_fin_prueba IS NOT NULL);

-- Acelera la consulta más común: "suscripciones de este usuario en este estado".
CREATE INDEX idx_suscripciones_usuario_estado ON suscripciones (usuario_id, estado);

-- ─── Tablas nuevas (se usan en fases siguientes) ─────────────────────────────
CREATE TABLE historial_pagos (
  id             SERIAL PRIMARY KEY,
  suscripcion_id INT           NOT NULL REFERENCES suscripciones(id) ON DELETE CASCADE,
  monto          NUMERIC(12,2) NOT NULL CHECK (monto >= 0),
  fecha_pago     DATE          NOT NULL
);
CREATE INDEX idx_historial_pagos_suscripcion ON historial_pagos (suscripcion_id);

CREATE TABLE cancelaciones (
  id                      SERIAL PRIMARY KEY,
  suscripcion_id          INT           NOT NULL REFERENCES suscripciones(id) ON DELETE CASCADE,
  fecha_cancelacion       DATE          NOT NULL DEFAULT CURRENT_DATE,
  ahorro_proyectado_anual NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (ahorro_proyectado_anual >= 0)
);
CREATE INDEX idx_cancelaciones_suscripcion ON cancelaciones (suscripcion_id);

CREATE TABLE guias_cancelacion (
  id              SERIAL PRIMARY KEY,
  nombre_servicio VARCHAR(100) NOT NULL UNIQUE,
  pasos           TEXT         NOT NULL,
  enlace_directo  VARCHAR(500) NULL
);

CREATE TABLE notificaciones_enviadas (
  id             SERIAL PRIMARY KEY,
  usuario_id     INT         NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  tipo           VARCHAR(25) NOT NULL
    CHECK (tipo IN ('proximo_cobro', 'fin_prueba_gratis', 'cambio_precio', 'resumen_periodico')),
  fecha_envio    TIMESTAMP   NOT NULL DEFAULT NOW(),
  -- Si se borra la suscripción, el registro del aviso se conserva sin ella.
  suscripcion_id INT         NULL REFERENCES suscripciones(id) ON DELETE SET NULL
);
CREATE INDEX idx_notificaciones_usuario ON notificaciones_enviadas (usuario_id);
