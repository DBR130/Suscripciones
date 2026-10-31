-- 005: catálogo de guías de cancelación (RF09, RNF08).
--
-- El contenido no va aquí: está en db/guias.json y se carga con
-- `npm run db:guias`. Así se puede actualizar sin publicar otra versión de la app.

-- Los pasos se guardan como JSON: un arreglo de textos, en orden.
-- (La tabla estaba vacía, así que la conversión no pierde datos.)
ALTER TABLE guias_cancelacion
  ALTER COLUMN pasos TYPE JSONB USING pasos::jsonb;

ALTER TABLE guias_cancelacion
  ADD CONSTRAINT guias_pasos_arreglo_check CHECK (jsonb_typeof(pasos) = 'array'),
  -- Otros nombres con que el usuario puede escribir el servicio.
  ADD COLUMN alias TEXT[] NOT NULL DEFAULT '{}',
  ADD COLUMN duracion_minutos INT NULL CHECK (duracion_minutos > 0),
  ADD COLUMN actualizada_en TIMESTAMP NOT NULL DEFAULT NOW(),
  -- La guía "Otro servicio", que se usa cuando no hay una específica.
  ADD COLUMN es_generica BOOLEAN NOT NULL DEFAULT FALSE;

-- Solo puede haber una guía genérica.
CREATE UNIQUE INDEX guias_una_generica ON guias_cancelacion (es_generica) WHERE es_generica;
