# T1: Nombres pegados y señal de suscripción

## Qué
- Antes de buscar en el catálogo, separar palabras pegadas por mayúsculas:
  `YouTubePremium` → "YouTube Premium". Igual en Dart (parser y catálogo) y en
  JS (`normalizar` / búsqueda del catálogo).
- Señal de suscripción en el comercio, como palabra completa: SUB, SUBS,
  SUBSCRIPTION, SUSCRIPCION, MEMBRESIA, PRIME, PRO, PLUS, PREMIUM. "PRO" no
  coincide con "PRODUCTOS".

## Criterios de aceptación
- "Bancolombia: Compraste $26.900,00 en GOOGLE *YouTubePremium …" →
  servicio YouTube Premium, con señal de suscripción.
- Un comercio "PRODUCTOS RAPPI" no tiene señal.
- El backend reconoce "YouTubePremium" como el servicio YouTube Premium.

## Fuera de alcance
Formatos de SMS nuevos.
