-- 008: servicios ambiguos y precio de referencia en el catálogo (tickets T2 y T5).
--
-- es_ambigua: el comercio también vende cosas sueltas (un pedido por Rappi,
-- un juego en PlayStation, una compra en la App Store). Un cobro de un
-- servicio ambiguo solo se propone como suscripción con patrón (2 o más
-- cobros periódicos de monto similar) o con una señal de suscripción en el
-- comercio ("RAPPI PRO", "YouTubePremium"). Ver services/detecciones.js.
--
-- precio_referencia_cop: precio típico en Colombia, para sugerir el servicio
-- cuando un cobro llega por un procesador de pagos ("¿Es Crunchyroll?").
-- Vacío si no se conoce con seguridad.
--
-- Los valores se cargan desde db/guias.json con `npm run db:guias`.
ALTER TABLE guias_cancelacion
  ADD COLUMN es_ambigua BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN precio_referencia_cop NUMERIC(12,2) NULL CHECK (precio_referencia_cop > 0);
