# T1: Nombres pegados, limpieza del comercio y señal de suscripción

## Qué
- Antes de buscar en el catálogo, separar palabras pegadas por mayúsculas:
  `YouTubePremium` → "YouTube Premium". Igual en Dart (parser y catálogo) y en
  JS (`normalizar` / búsqueda del catálogo).
- Señal de suscripción en el comercio, como palabra completa: SUB, SUBS,
  SUBSCRIPTION, SUSCRIPCION, MEMBRESIA, PRIME, PRO, PLUS, PREMIUM. "PRO" no
  coincide con "PRODUCTOS".

- Limpieza del comercio con formatos vistos en SMS reales (Nequi, septiembre
  de 2026):
  - quitar un teléfono pegado al final: "STEAMGAMES.COM 4259522985" →
    "Steamgames";
  - `DLO*` es el prefijo de pasarela de dLocal: "DLO*DiDi Food CO Payin" →
    "DiDi Food" (se quitan "CO" y "Payin" al final);
  - las palabras con mayúsculas y minúsculas mezcladas se conservan ("DiDi").

## Criterios de aceptación
- "Bancolombia: Compraste $26.900,00 en GOOGLE *YouTubePremium …" →
  servicio YouTube Premium, con señal de suscripción.
- Un comercio "PRODUCTOS RAPPI" no tiene señal.
- El backend reconoce "YouTubePremium" como el servicio YouTube Premium.
- "NEQUI: Pagaste 39.381,00 en STEAMGAMES.COM 4259522985" → 39.381 COP,
  comercio "Steamgames" (el teléfono no es monto ni parte del nombre).
- "NEQUI: Pagaste 18.900,00 en DLO*DiDi Food CO Payin" → comercio "DiDi Food".

## Fuera de alcance
Formatos de SMS nuevos.
