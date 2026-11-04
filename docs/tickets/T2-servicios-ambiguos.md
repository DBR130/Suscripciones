# T2: Servicios ambiguos

## Qué
- `es_ambigua: true` en `backend/db/guias.json` para Rappi Pro, Apple,
  PlayStation Plus, Xbox Game Pass, YouTube Premium, Google One, Adobe,
  Prime Video y Microsoft 365.
- Migración 008: columnas `es_ambigua` (BOOLEAN) y `precio_referencia_cop`
  (NUMERIC, nullable; se usa en T5) en `guias_cancelacion`; `cargar-guias.js`
  las carga y `GET /api/guias` devuelve `es_ambigua`.
- Regla, en el celular y en el backend: un servicio ambiguo se propone solo
  con patrón (2 o más cobros con montos ±10 % y periodicidad semanal, mensual
  o anual), salvo que el comercio traiga señal de suscripción (T1).
- En el celular, un cobro suelto de un servicio ambiguo sin señal no sale
  (queda como compra puntual local).

## Criterios de aceptación
- Pedido de Rappi suelto → compra normal (no sale del celular; el backend
  responde `compra_normal`).
- Dos cobros mensuales iguales de Rappi → candidato.
- "GOOGLE *YouTubePremium" → candidato desde el primer pago.
- Juego de PlayStation suelto → compra normal.
