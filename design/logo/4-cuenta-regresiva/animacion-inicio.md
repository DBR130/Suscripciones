# Animación de inicio de SubTrack

Duración total: 1500 ms de animación más 300 ms de pausa antes de pasar a la primera pantalla (1800 ms en total). Fondo fijo `#0B1220` desde el primer frame, igual que el splash nativo de Android, para que no haya salto.

Se basa en `logo-nombre-oscuro.svg`. Sus elementos tienen id: `anillo-fondo`, `anillo`, `punto`, `s` y `nombre`.

## Pasos

| # | Elemento | Inicio | Duración | Qué pasa | Curva (CSS) | Curva (Flutter) |
|---|---|---|---|---|---|---|
| 1 | `anillo-fondo` | 0 ms | 200 ms | Opacidad 0 → 1 | `cubic-bezier(0.33, 1, 0.68, 1)` | `Curves.easeOutCubic` |
| 2 | `anillo` | 100 ms | 700 ms | Se dibuja desde arriba en sentido horario hasta las 9 en punto (270°). Va de `stroke-dashoffset` 127.2 a 0 (largo del arco: 2π·27·0.75 ≈ 127.2) | `cubic-bezier(0.65, 0, 0.35, 1)` | `Curves.easeInOutCubic` |
| 3 | `punto` | 100 ms | 700 ms | Recorre el anillo pegado a la punta del trazo, de las 12 hasta su posición final a las 9. Mismo tiempo y misma curva que el paso 2. Al arrancar crece de escala 0 a 1 en 120 ms | `cubic-bezier(0.65, 0, 0.35, 1)` | `Curves.easeInOutCubic` |
| 4 | `s` | 750 ms | 450 ms | Escala 0.6 → 1 desde el centro (54, 54) con un pequeño rebote (pasa a ~1.06 y vuelve). La opacidad va de 0 a 1 en los primeros 150 ms | `cubic-bezier(0.34, 1.56, 0.64, 1)` | `Curves.easeOutBack` |
| 5 | `nombre` | 1100 ms | 400 ms | Opacidad 0 → 1 y se desliza 12 px de izquierda a derecha | `cubic-bezier(0.33, 1, 0.68, 1)` | `Curves.easeOutCubic` |
| — | Pausa | 1500 ms | 300 ms | Todo quieto, luego navega | — | — |

## Notas para implementar

- En Flutter, lo más simple es un solo `AnimationController` de 1500 ms con un `Interval` por paso (por ejemplo, el anillo usa `Interval(100/1500, 800/1500, curve: Curves.easeInOutCubic)`). El anillo y el punto se dibujan con un `CustomPainter` a partir del mismo valor, así el punto siempre va en la punta del trazo.
- El ángulo del punto es `-90° + 270° × t` (0° = las 3 en punto, medido en sentido horario), con centro (54, 54) y radio 27 en la cuadrícula de 108.
- Si el sistema tiene las animaciones reducidas (`MediaQuery.disableAnimations`), se muestra el estado final directamente y se pasa a la app después de 300 ms.
- El splash nativo de Android 12+ no admite esta secuencia: ahí va solo `icono-foreground.svg` sobre `#0B1220`, y la animación corre en la primera pantalla de Flutter.
