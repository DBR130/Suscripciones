-- 006: detección automática de suscripciones (RF02, RF03, flujo B).
--
-- Al backend solo llegan los campos que extrae el parser del celular; el
-- texto de la notificación nunca sale del teléfono (ver docs/deteccion.md).

-- Cada cobro detectado en una notificación, ya interpretado.
CREATE TABLE pagos_detectados (
  id                   SERIAL PRIMARY KEY,
  usuario_id           INT           NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  -- Como venía en el mensaje ("GOOGLE *Crunchyroll") y normalizado ("Crunchyroll").
  comercio             VARCHAR(100)  NOT NULL,
  comercio_normalizado VARCHAR(100)  NOT NULL,
  monto                NUMERIC(12,2) NOT NULL CHECK (monto > 0),
  moneda               VARCHAR(3)    NOT NULL CHECK (moneda IN ('COP', 'USD')),
  -- Hora local de Colombia (la del mensaje o la de llegada).
  fecha                TIMESTAMP     NOT NULL,
  banco                VARCHAR(50)   NOT NULL,
  -- Identifica la notificación para no registrarla dos veces. La calcula el
  -- celular (SHA-256 en hexadecimal).
  huella               VARCHAR(64)   NOT NULL,
  -- Caso a): la suscripción del usuario a la que corresponde, si existe.
  suscripcion_id       INT           NULL REFERENCES suscripciones(id) ON DELETE SET NULL,
  creado_en            TIMESTAMP     NOT NULL DEFAULT NOW(),
  -- Única por usuario: así un usuario no puede averiguar, enviando una
  -- huella, si otro usuario ya la registró.
  CONSTRAINT pagos_detectados_usuario_huella_key UNIQUE (usuario_id, huella)
);
-- Para buscar los pagos anteriores al mismo comercio (caso c).
CREATE INDEX idx_pagos_detectados_comercio
  ON pagos_detectados (usuario_id, lower(comercio_normalizado), fecha);

-- Posibles suscripciones que el usuario confirma o descarta (pantalla 05).
CREATE TABLE candidatos_suscripcion (
  id                   SERIAL PRIMARY KEY,
  usuario_id           INT           NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  comercio_normalizado VARCHAR(100)  NOT NULL,
  monto                NUMERIC(12,2) NOT NULL CHECK (monto >= 0),
  moneda               VARCHAR(3)    NOT NULL CHECK (moneda IN ('COP', 'USD')),
  frecuencia_estimada  VARCHAR(10)   NOT NULL CHECK (frecuencia_estimada IN ('semanal', 'mensual', 'anual')),
  estado               VARCHAR(12)   NOT NULL DEFAULT 'pendiente'
    CHECK (estado IN ('pendiente', 'confirmada', 'descartada')),
  suscripcion_id       INT           NULL REFERENCES suscripciones(id) ON DELETE SET NULL,
  -- Servicio del catálogo de guías (caso b) o comercio con pagos periódicos (caso c).
  es_servicio_conocido BOOLEAN       NOT NULL DEFAULT FALSE,
  banco                VARCHAR(50)   NOT NULL,
  fecha_ultimo_pago    DATE          NOT NULL,
  creado_en            TIMESTAMP     NOT NULL DEFAULT NOW(),
  -- Solo la suscripción confirmada queda enlazada.
  CONSTRAINT candidatos_confirmada_check CHECK (estado = 'confirmada' OR suscripcion_id IS NULL)
);
-- Un candidato por comercio y usuario: un comercio descartado no se vuelve a
-- proponer (sin importar mayúsculas).
CREATE UNIQUE INDEX candidatos_usuario_comercio_key
  ON candidatos_suscripcion (usuario_id, lower(comercio_normalizado));
