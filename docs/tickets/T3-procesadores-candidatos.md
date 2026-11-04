# T3: Procesadores: detección y candidatos separados por monto

## Qué
- `backend/db/procesadores.json` (nombre y alias; dLocal incluye "DLO"): EBANX, PayU, dLocal,
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
- Fixtures **reales** (SMS de Nequi de Santiago, septiembre de 2026):
  - "NEQUI: Pagaste 19.900,00 en SERVICIOS WEB EBANX CO" (16/09 12:43):
    Nequi, 19.900 COP, procesador EBANX, fecha de llegada.
  - "NEQUI: Pagaste 39.381,00 en STEAMGAMES.COM 4259522985" (16/09 20:44):
    compra puntual, sin candidato.
  - "NEQUI: Pagaste 64.925,65 en ANTHROPIC* CLAUDE SUB" (19/09 18:10): con el
    de octubre (68.139,27), dos cobros mensuales de Claude (4,95 % de
    diferencia por la tasa del dólar).
  - "NEQUI: Pagaste 18.900,00 en DLO*DiDi Food CO Payin" y "… 16.140,00 …"
    (25/09 19:44 y 19:46): comercio DiDi Food (no "pago procesado por
    dLocal": el SMS trae el comercio real), compras normales sin candidato.
- En Truecaller el remitente de esos SMS aparece como "Robocall · Potential
  fraud", pero llegan igual: el filtro no usa el título.

## Criterios de aceptación
- "Servicios Web Ebanx Co" es EBANX; "DLO*DiDi Food CO Payin" es DiDi Food.
- Dos cobros mensuales de EBANX de $19.900 y dos de $34.900 → dos candidatos
  "EBANX" con montos distintos.
- "PAYPAL *NETFLIX" sigue siendo Netflix.
