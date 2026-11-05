-- 009: candidatos de procesadores de pago (ticket T3).
--
-- Un procesador (EBANX, PayU, dLocal...) cobra en nombre de otros servicios:
-- el SMS trae su nombre ("SERVICIOS WEB EBANX CO") y no el del servicio. Un
-- mismo procesador puede cobrar dos servicios distintos, así que sus cobros
-- se separan por monto (±10 %): cada grupo es un candidato distinto, todos
-- con comercio_normalizado = procesador = "EBANX". La lista de procesadores
-- está en db/procesadores.json.
ALTER TABLE candidatos_suscripcion
  ADD COLUMN procesador VARCHAR(50) NULL;

-- El índice "un candidato por comercio" ya no aplica a los procesadores: el
-- código los distingue por monto (services/detecciones.js).
DROP INDEX candidatos_usuario_comercio_key;
CREATE UNIQUE INDEX candidatos_usuario_comercio_key
  ON candidatos_suscripcion (usuario_id, lower(comercio_normalizado))
  WHERE procesador IS NULL;
