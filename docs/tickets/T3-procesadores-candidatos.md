# T3: Procesadores: detección y candidatos separados por monto

## Qué
- `backend/db/procesadores.json` (nombre y alias): EBANX, PayU, dLocal,
  Mercado Pago, PayPal, Stripe, 2Checkout (Verifone), Paddle, FastSpring,
  ePayco, Wompi, PlacetoPay (Evertec), Kushki, Bold. El backend lo lee al
  arrancar y lo entrega en `GET /api/guias` como `procesadores`.
- Un comercio es de un procesador si contiene un alias como palabra completa
  y no es un servicio del catálogo (el catálogo tiene prioridad).
- Un procesador se propone solo con patrón (igual que un comercio
  desconocido).
- Migración 009: columna `procesador` en `candidatos_suscripcion`; el índice
  único por comercio pasa a ser parcial (`WHERE procesador IS NULL`).
- Candidato de procesador: `comercio_normalizado` y `procesador` = nombre del
  procesador. Los grupos con montos fuera de ±10 % son candidatos distintos.
- En el celular, el análisis agrupa por procesador (o por comercio) y separa
  por monto.
- Fixtures de EBANX **reconstruidos** (marcados como tales, para reemplazar
  por el SMS real).

## Criterios de aceptación
- "Servicios Web Ebanx Co" es EBANX.
- Dos cobros mensuales de EBANX de $19.900 y dos de $34.900 → dos candidatos
  "EBANX" con montos distintos.
- "PAYPAL *NETFLIX" sigue siendo Netflix.
