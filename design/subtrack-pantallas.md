# SubTrack · Referencia de pantallas para Claude Code

Acompaña a `subtrack-simulacion.html` (misma carpeta). Ese archivo se abre en cualquier navegador sin instalar nada. Este documento lista las 14 pantallas con sus componentes, colores y textos exactos para recrearlas en Flutter.

## Cómo usar este documento

- **Fuente visual:** la simulación HTML. Los valores de este documento salen de su CSS, y si algo no coincide, manda la simulación.
- **Código base:** la app Flutter `flutter_suscripciones` ya tiene `AppTheme`/`AppColors`, go_router (`Routers`), `AuthService` (JWT + flutter_secure_storage) y las páginas `LoginPage`, `RegistroPage` y `DashboardPage`. Hay que reutilizarlas, no reemplazarlas.
- **"Hoy" en la simulación** es el 17 sep 2026. Los textos relativos ("Se cobra mañana") se calculan contra esa fecha. En la app se calculan contra la fecha real.

## Prioridad acordada con David

1. **Funcional primero:** 07 Dashboard, 13 Agregar/Editar, 09 Detalle (y editar y eliminar desde el detalle). Lista y dashboard leen del **backend real**.
2. **Login (02):** se mantiene la autenticación real con el backend. Solo cambia el diseño.
3. **Después:** onboarding (01, 03, 06) y escaneo/detección (04, 05).
4. **04 y 05 usan datos de ejemplo** y llevan la etiqueta visible "Datos de ejemplo · provisional" hasta que exista la detección real.
5. Avisos (11), Ahorro (12) y Guía (10) usan datos de ejemplo hasta que existan sus endpoints. Esto no está dentro de la prioridad 1.

---

## 1. Tokens de diseño

### Colores

| Token | Hex | Uso | En `AppColors` hoy |
|---|---|---|---|
| page | `#080D18` | Fondo fuera del teléfono (solo simulación) | no aplica |
| bg | `#0B1220` | Fondo de pantalla (scaffold) | `bg` ✓ |
| surface | `#141D2F` | Tarjetas, inputs, switch apagado | `surface` ✓ |
| surface-2 | `#16273F` | Avisos informativos, chip "Es mía", ícono de permisos | nuevo |
| surface-3 | `#1C2942` | Avatar, número de paso en la guía | nuevo |
| bar | `#0E1626` | Barra de pestañas y pie con botón fijo | nuevo |
| line | `#243149` | Borde de tarjetas e inputs, separador interno de tarjeta | `line` ✓ |
| line-2 | `#2C3B58` | Borde de botones outline, pills, chips | nuevo |
| divider | `#1E2A40` | Separador de filas en listas de datos y borde superior de barras | nuevo |
| text | `#E9EFFA` | Texto principal | `text` ✓ |
| text-2 | `#D6E3FB` | Texto de botones outline y pasos | nuevo |
| muted | `#9AAAC4` | Texto secundario y etiquetas | `muted` ✓ |
| muted-hero | `#A6B6D0` | Texto secundario sobre el degradado | nuevo |
| primary | `#2563EB` | Botón principal, pill activa, contador, switch encendido, logo "S" | `primary` ✓ |
| accent | `#60A5FA` | Foco de input, checks, punto activo del onboarding | `accent` ✓ |
| link | `#7DB3FF` | Enlaces, pestaña activa, ahorro (+$) | nuevo |
| accent-soft | `#A9CCFF` | Chip informativo azul, ícono de escaneo | nuevo |
| amber | `#FBD167` | Botones de atención (cancelar, rechazar permiso), texto de flags ámbar | nuevo |
| amber-strong | `#FCD34D` | Chip de prueba gratis en el dashboard, aviso "marcada" | nuevo |
| amber-line | `rgba(251,191,36,.45)` | Borde de botones ámbar (1.5 px) | nuevo |
| amber-bg | `rgba(251,191,36,.13)` | Fondo de flags ámbar | nuevo |
| error | `#F87171` | Bordes y textos de error de validación | `error` ✓ |
| error-soft | `#FCA5A5` | Texto del banner de error del servidor | nuevo |
| error-bg / error-line | `rgba(248,113,113,.12)` / `.45` | Banner de error del servidor | nuevo |
| danger | `#DC2626` | Botón destructivo del diálogo de confirmación | nuevo |
| card-flag bg | `#17203A` | Fondo de tarjeta destacada (prueba gratis o marcada) | nuevo |

**Degradado del encabezado (hero):** `linear-gradient(140deg, #0D1526 0%, #152443 55%, #1E3A6E 100%)`. En Flutter es `LinearGradient` con `begin: Alignment.topLeft` y `end: Alignment.bottomRight`. Esquinas inferiores de 26 px. La bienvenida usa el mismo degradado a 160°.

**Glass (tarjeta del total y banner push):** fondo `rgba(255,255,255,.15)`, borde 1 px `rgba(255,255,255,.36)`, brillo interior arriba `rgba(255,255,255,.5)`, sombra `0 12 26 rgba(0,0,0,.16)` y desenfoque de 14 px. En Flutter: `ClipRRect` + `BackdropFilter(ImageFilter.blur(14,14))`.

**Orbes decorativos:** dos círculos con degradado radial azul (`rgba(59,130,246,.45)` y `rgba(37,99,235,.38)`) arriba a la derecha y a la izquierda, detrás del contenido.

**Colores de marca de los servicios** (fondo del logo): Disney+ `#113CCF`, GeForce NOW `#3F6B00`, Netflix `#C1121F`, Spotify `#12833F`, iCloud+ `#2F3437`, Smart Fit `#8A7A00`, Adobe Photoshop `#0A2F52`, Canva Pro `#0B7285`, Paramount+ `#0064FF`. Las suscripciones manuales usan `#334155`.

### Tipografía

Fuente **Inter** (paquete `google_fonts` o asset), pesos 400 a 900. Interlineado base de 1.35. Los montos usan cifras tabulares (`FontFeature.tabularFigures()`).

| Estilo | Tamaño / peso / tracking | Dónde |
|---|---|---|
| Display | 31 / 800 / -0.03em, interlineado 1.12 | Título del onboarding |
| Monto grande | 38 / 800 / -0.025em | Total del dashboard |
| Monto detalle | 32–36 / 800 | Detalle, ahorro |
| Título de pantalla | 24 / 800 / -0.025em | Login, permisos, preferencia |
| Título de hero | 21 / 800 / -0.025em | Suscripciones, Avisos, Agregar |
| Nombre en tarjeta | 15.5 / 700 / -0.015em | Tarjetas de suscripción |
| Cuerpo | 13.5 / 500–600 | Descripciones |
| Meta | 12.5 / 500 | Categoría, líneas de estado |
| Eyebrow / label | 11.5 / 800 / +0.09em, MAYÚSCULAS | "GASTO EN SUSCRIPCIONES · MES", etiquetas de campos |
| Pestaña | 10 / 700 | Barra inferior |

### Forma y espacio

- Radios: teléfono 38, hero 26 (abajo), glass 22, tarjetas 14, inputs y pills 12, logos 12, marca "S" 9, botones 999 (píldora).
- Márgenes de pantalla: 16 px en listas y 24 px en pantallas de formulario o texto. Separación entre tarjetas: 11 px. Padding de tarjeta: 14 px.
- Alto mínimo del botón principal: unos 48 px (padding vertical de 14). `AppTheme` ya usa 52 con `StadiumBorder`, y sirve.

---

## 2. Componentes

| Componente | Especificación | Notas Flutter |
|---|---|---|
| **Marca** | Cuadro de 28×28, radio 9, `primary`, letra "S" 13/900 en blanco, más "SubTrack" 17/800 | Ya existe `widgets/app_marca.dart`; ajustarlo |
| **Hero** | Degradado, radio inferior 26, padding 10/16/20 | Widget `HeroHeader(child)` |
| **Botón volver** | Píldora con fondo `rgba(255,255,255,.1)`, borde `rgba(255,255,255,.22)`, ícono ‹, texto 12.5/700 "Volver" | También para "Editar" (ícono lápiz) y "Dashboard" |
| **Botón primario** | Píldora `primary`, texto blanco 14/700, ancho completo | `FilledButton` del tema |
| **Botón outline** | Transparente, borde 1 px `line-2`, texto `text-2` 13.5/700 | `OutlinedButton` |
| **Botón ámbar** | Transparente, borde 1.5 px `amber-line`, texto `amber` | "Cancelar esta suscripción", "Prefiero agregarlas a mano", "Eliminar cuenta…" |
| **Botón punteado** | Como outline pero con borde discontinuo | "+ Agregar suscripción manualmente" (paquete `dotted_border` o `CustomPainter`) |
| **Botón destructivo de texto** | Sin borde, texto `error` 13/700 | "Eliminar suscripción" en modo editar |
| **Input** | Fondo `surface`, borde `line`, radio 12, texto 14.5/600, placeholder `muted` al 60 %. Con foco: borde `accent` de 1.5. Con error: borde `error` y mensaje 12/600 en `error` debajo | La etiqueta va **arriba** del campo (11.5/800 en mayúsculas), no como label flotante. `AppTextField` debe cambiar a este patrón |
| **Banner de error del servidor** | Fondo `error-bg`, borde `error-line`, texto `error-soft` 13/600, ícono ⓘ | Reemplaza el SnackBar de error en login y registro |
| **Tarjeta de suscripción** | Fila: logo de 44 + nombre/categoría + monto/periodo. Flag opcional. Pie con separador `line`: 📅 línea de fecha + botón "Ver detalle ›" pequeño primario | Ver reglas de flags abajo |
| **Tarjeta destacada** | Fondo `#17203A`, borde 2 px ámbar `rgba(251,191,36,.55)` | Si es prueba gratis o está marcada para cancelar |
| **Flag ámbar** | Fondo `amber-bg`, borde discontinuo ámbar, texto `amber` 12/700, ícono ⓘ | Prueba gratis, marcada por el usuario |
| **Flag azul** | Fondo `surface-2`, borde `line-2`, texto `accent-soft` | Cobro cercano, cambio de precio |
| **Chip** | Píldora 12/700. Ámbar (prueba) o neutral (`#1A263D`, borde `line-2`) | Dentro de la tarjeta glass del dashboard |
| **Contador** | Píldora `primary` 11/800 junto al título de sección | "Próximos 7 días (3)" |
| **Logo de servicio** | Cuadrado de 44 (38 en listas compactas, 52 en el detalle), radio 12, color de marca, iniciales 13.5/800 en blanco | Iniciales: campo propio o las 2 primeras letras del nombre |
| **Lista de datos (facts)** | Tarjeta `surface` con filas clave/valor separadas por `divider`. Clave 12.5/600 `muted`, valor 13/700 | Detalle, historial, perfil |
| **Selector de días** | 3 pills (1 día / 3 días / 7 días). Activa: `primary` con texto blanco. Inactiva: transparente con borde `line-2` | Se repite en 06, 09 y 14 |
| **Switch** | 46×27, perilla de 21. Encendido: `primary` con perilla blanca. Apagado: `surface`, borde `line-2`, perilla `#5B6A85` | `Switch` con colores del tema |
| **Barra de pestañas** | Fondo `bar`, borde superior `divider`, 4 pestañas con ícono de 20 y texto 10/700. Activa en `link`, inactiva en `muted` | Resumen · Suscripciones · Avisos · Perfil. `ShellRoute` + `NavigationBar` |
| **Toast** | Tarjeta `surface`, borde `line-2`, radio 14, ✓ en `accent` y texto 13/600, a 96 px del fondo (sobre las pestañas) y 2.4 s | `SnackBar` flotante del tema |
| **Diálogo de confirmación** | Hoja inferior `surface`, radio 22, título 17/800, cuerpo 13.5 `muted`, botón destructivo `#DC2626` y "No, volver" | `showModalBottomSheet` |
| **Estado vacío** | Ícono + en un cuadro `surface-2` de 54, título 17/800, texto `muted` y botón primario | Dashboard y lista sin suscripciones |
| **Etiqueta provisional** | Fondo `amber-bg`, borde discontinuo ámbar, 10.5/800 en mayúsculas: "DATOS DE EJEMPLO · PROVISIONAL" | Solo en 04 y 05 |

### Reglas de la tarjeta de suscripción (flag y destacado)

Se evalúan en este orden y gana la primera que se cumple:

1. `estado = marcada_para_cancelar` → flag ámbar **"Marcada por ti para cancelar"** y tarjeta destacada.
2. `es_prueba_gratis` → flag ámbar **"Prueba gratis: se convierte en {monto}/mes en {n} días"** y tarjeta destacada.
3. El precio cambió (existe un monto anterior distinto) → flag azul **"Subió de {anterior} a {actual} este mes"**.
4. Faltan menos días que la preferencia de aviso → flag azul **"Se cobra hoy"**, **"Se cobra mañana"** o **"Se cobra en {n} días"**.

Línea del pie: `Próximo cobro: 20 sep`, o `Prueba termina 19 sep` si es prueba gratis.

**Regla del producto (spec v2):** ninguna pantalla etiqueta una suscripción como "no usada" u "olvidada". Los avisos son solo por fecha, monto y cambio de precio.

### Formatos

- Dinero: `$38.900` (es-CO, sin decimales). `NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0)`.
- Periodo: `/mes`, `/año`, `/semana`.
- Fecha corta: `20 sep`. Con año: `20 sep 2026`. Mes y año: `mar 2024`. Meses en minúscula y abreviados: ene, feb, mar, abr, may, jun, jul, ago, sep, oct, nov, dic.
- Gasto mensual equivalente: mensual = monto, anual = monto/12, semanal = monto×4.33. Una prueba gratis activa suma 0.

---

## 3. Pantallas

Para cada pantalla se indica: **ruta sugerida**, **datos**, estructura y textos exactos.

### 01 Bienvenida (onboarding) · prioridad 3
- Ruta: `/` cuando no hay sesión. Reemplaza el `HomePage` actual. Datos: ninguno.
- Fondo con degradado a 160°. Marca arriba. 3 slides con título display y texto:
  1. **"Todo lo que pagas cada mes, en una sola lista."** / "Monto, frecuencia y próxima fecha de cobro de cada suscripción. Sin tener que revisar el extracto línea por línea."
  2. **"Te avisamos antes del cobro, no después."** / "Recordatorios antes de cada cobro recurrente, antes de que termine una prueba gratis y cuando un precio cambia."
  3. **"No adivinamos qué usas. Tú decides."** / "La app nunca marca una suscripción como olvidada. Te da datos reales a tiempo y la decisión de cancelar es siempre tuya."
- Indicador de 3 puntos: el activo mide 22×7 en `accent` y los demás 7×7 en `line-2`.
- Botón primario "Siguiente" que en el último slide dice "Crear mi cuenta" (lleva a 02 en modo registro). Botón de texto "Ya tengo cuenta" (lleva a 02 en modo login).

### 02 Login / Registro · prioridad 2 (backend real)
- Rutas: `/login` y `/registro` (las actuales). Datos: `AuthService.login` / `AuthService.registro`.
- Marca arriba, título y subtítulo:
  - Login: **"Hola de nuevo"** / "Entra para ver tus próximos cobros."
  - Registro: **"Crea tu cuenta"** / "Con tu correo empezamos a ordenar tus cobros."
- Campos (etiqueta arriba):
  - Registro: NOMBRE ("Tu nombre"), CORREO ("tucorreo@ejemplo.com"), CONTRASEÑA ("mínimo 6 caracteres"), CONFIRMAR CONTRASEÑA ("repite la contraseña").
  - Login: CORREO y CONTRASEÑA ("tu contraseña").
- Validación por campo, con los mismos textos de `Validators`: "Ingresa tu nombre", "Ingresa tu correo electrónico", "Correo no válido", "Ingresa tu contraseña", "Mínimo 6 caracteres", "Las contraseñas no coinciden".
- Error del backend en el **banner rojo** arriba del formulario, con el mensaje tal cual: "Correo o contraseña incorrectos", "Ya existe una cuenta con ese correo" o "No se pudo conectar con el servidor".
- Botón primario "Entrar" / "Crear cuenta". Mientras carga queda deshabilitado, con spinner y el texto "Entrando…" / "Creando cuenta…".
- Enlace inferior: "No tengo cuenta, quiero registrarme" / "¿Ya tienes cuenta? Inicia sesión".
- Pie legal 11 px `muted`: "Al continuar aceptas el tratamiento de datos descrito en la política de privacidad (Habeas Data). Puedes eliminar tu cuenta y todos tus datos en cualquier momento."
- Al entrar: toast "Hola, {primer nombre}" (neutral, reemplaza "Bienvenido, …"). El registro continúa a 03 y el login va a 07.
- Se quitó "Continuar con cuenta social" porque el backend no la soporta.

### 03 Permisos · prioridad 3
- Ícono de campana en un cuadro `surface-2` de 46. Título **"Permiso para leer notificaciones de pago"**. Texto: "Con este permiso detectamos automáticamente qué suscripciones tienes, cuánto cuestan y cada cuánto se cobran."
- Tarjeta con 3 líneas, cada una con un ✓ en `accent`: "Solo leemos notificaciones que parecen cobros: comercio, monto y fecha." · "No leemos mensajes personales, chats ni el contenido de otras apps." · "Puedes revocar el permiso desde Configuración cuando quieras."
- Nota: "En iOS no es posible leer notificaciones de otras apps: allí el registro es manual o por reenvío de correos de cobro."
- Botones: primario "Dar permiso y detectar" (lleva a 04) y ámbar "Prefiero agregarlas a mano" (lleva a 13, y después a 06).

### 04 Escaneo · prioridad 3 · **datos de ejemplo, provisional**
- Centrado: etiqueta provisional, círculo pulsante de 96 con lupa, **"Revisando tus notificaciones de pago…"**, "Buscamos cobros que se repitan con el mismo monto y comercio." y una barra de progreso de 6 px (`primary` sobre `surface`). A los 1.9 s pasa a 05.

### 05 Resultados de detección · prioridad 3 · **datos de ejemplo, provisional**
- Hero: eyebrow "PRIMERA DETECCIÓN" + etiqueta provisional. **"Encontramos {n} suscripciones"**. "Confirma las que sí son tuyas. Puedes descartar el resto."
- Filas compactas (logo de 38): nombre y "{monto} · {frecuencia} · 3 cobros detectados", con un botón conmutable "Es mía" (relleno `surface-2`, texto `accent-soft`) o "Descartada" (borde discontinuo, texto `muted`).
- Pie fijo: "Confirmar {n} suscripciones" (lleva a 06).

### 06 Preferencia de recordatorio · prioridad 3
- **"¿Cuántos días antes te avisamos?"** / "Se aplica a todos los cobros. Después puedes cambiarlo por suscripción."
- 3 opciones grandes con título y pista: "1 día antes" (Aviso justo antes del cobro) · "3 días antes" (Recomendado: alcanzas a cancelar) · "7 días antes" (Para planear el mes completo). Por defecto: 3.
- Tarjeta con switch: "Resumen mensual" / "Cada inicio de mes, con tu gasto total".
- Botón "Ir a mi dashboard".

### 07 Dashboard · **prioridad 1 · backend real**
- Ruta: `/resumen` (la actual), con barra de pestañas. Datos: suscripciones activas del usuario.
- Hero: marca a la izquierda y avatar con iniciales del usuario a la derecha (lleva a 14).
- Tarjeta glass: eyebrow "GASTO EN SUSCRIPCIONES · MES", total mensual equivalente (38/800), "{n} activas · proyección anual {total×12}". Chips: ámbar "1 prueba gratis termina en {n} días" (solo si hay pruebas que terminan en 7 días o menos; con varias: "{n} pruebas gratis terminan esta semana") y neutral "Próximo cobro: {fecha}".
- Sección **"Próximos 7 días"** con contador y nota a la derecha "{suma} por cobrar". Sección **"Más adelante"** con contador y nota "Ordenadas por cobro". Ambas se ordenan por fecha (fin de prueba o próximo cobro) y una sección vacía no se muestra.
- Tarjetas de suscripción (ver reglas). "Ver detalle" lleva a 09.
- Al final: botón punteado "+ Agregar suscripción manualmente" (lleva a 13).
- **Estado vacío:** total $0, "0 activas · proyección anual $0", sin chips. Título **"Aún no tienes suscripciones"**, texto "Agrega la primera con su monto y la fecha del próximo cobro. Te avisaremos {n} días antes." y botón "Agregar suscripción".
- **Carga y error** (no están en la simulación): un indicador de carga dentro del área de lista, y si falla, el banner de error con el mensaje del servidor y un botón "Reintentar".

### 08 Suscripciones · prioridad 1 · backend real
- Pestaña 2. Hero: **"Suscripciones"** / "{n} activas · {m} canceladas · avisos {d} días antes".
- Filas: logo, nombre (15/700), línea de estado ("Mensual · próximo 20 sep", "Prueba gratis hasta 19 sep" o "Marcada para cancelar · 20 sep") y botón outline "{monto} ›" que lleva a 09. Las filas destacadas usan el mismo estilo ámbar.
- Al final: "+ Agregar suscripción". Si no hay ninguna: "Tu lista está vacía" / "Las suscripciones que agregues aparecerán aquí."

### 09 Detalle de suscripción · **prioridad 1 · backend real**
- Ruta sugerida: `/suscripcion/:id`. Mantiene la barra de pestañas (con "Suscripciones" activa).
- Hero: **"‹ Volver"** a la izquierda y **"✎ Editar"** a la derecha (lleva a 13 en modo editar). Logo de 52, nombre 20/800, categoría. Monto 32/800 + periodo.
- Si está marcada: aviso ámbar "Tú marcaste esta suscripción para cancelar."
- Datos: Frecuencia · (si es prueba) Fin de la prueba · Próximo cobro (o "Primer cobro" en pruebas) · Pagado en total · Desde (`mar 2024`) · Origen ("Detección por notificación" o "Registro manual").
- **"Historial de pagos"**: los 3 últimos (fecha y monto). Vacío: "Sin pagos registrados aún" o "Sin pagos aún: está en prueba gratis", con $0.
- Tarjeta "Recordatorio de esta suscripción" / "Sobrescribe tu preferencia global" con el selector de días.
- Botones: ámbar "Cancelar esta suscripción" (lleva a 10) y outline "Marcar como \"quiero cancelar\"" / "Quitar marca de \"quiero cancelar\"".

### 10 Guía de cancelación · datos de ejemplo
- Hero: Volver, **"Cómo cancelar {servicio}"** y "4 pasos · unos 3 minutos".
- Pasos numerados (cuadro de 26 en `surface-3`): 1 "Abre {servicio} en el navegador e inicia sesión con el correo de la suscripción." 2 "Entra a Cuenta → Suscripción y planes. En móvil el menú está detrás del avatar." 3 "Toca \"Cancelar suscripción\" y rechaza la oferta de descuento si aparece." 4 "Guarda el correo de confirmación: es tu comprobante si vuelven a cobrarte."
- Nota: "El catálogo de guías se actualiza desde el servidor: si el proveedor cambia su flujo, no hace falta publicar una nueva versión de la app."
- Pie fijo: primario "Ya cancelé, confirmar" (estado `cancelada`, registra el ahorro anual y lleva a 12) y texto "Lo haré después" (vuelve).

### 11 Avisos · datos de ejemplo
- Pestaña 3. Hero: **"Avisos"** / "Recordatorios enviados · {d} días antes de cada cobro".
- Tarjetas tocables (abren el detalle): tipo en mayúsculas 11/800 `muted` y fecha a la derecha, título 14/700 y cuerpo 12.5 `muted`. Tipos: "Fin de prueba gratis", "Próximo cobro", "Cambio de precio", "Resumen mensual".

### 12 Ahorro · datos de ejemplo
- Hero: "‹ Dashboard", eyebrow "AHORRO PROYECTADO AL AÑO", monto 36/800 y "{n} suscripciones canceladas · {x} menos al mes".
- Recién cancelada: aviso azul con ✓ "{servicio} quedó en canceladas. Sumamos el ahorro proyectado y apagamos sus recordatorios."
- "Evolución del gasto mensual": 6 barras (abr a sep). La del mes actual va en `primary` y las demás en `#1E2E4A` con borde `line`.
- "Canceladas": logo de 38, nombre, "Cancelada el {fecha}" y a la derecha "+{ahorro}" en `link` con "al año".

### 13 Agregar / Editar suscripción · **prioridad 1 · backend real**
- Rutas sugeridas: `/suscripcion/nueva` y `/suscripcion/:id/editar`. Es la misma pantalla en dos modos.
- Hero: Volver + **"Agregar suscripción"** / **"Editar suscripción"**.
- Campos (en modo editar vienen precargados):
  - SERVICIO ("ej. HBO Max"), obligatorio. Error: "Ingresa el nombre del servicio".
  - PLAN O CATEGORÍA (OPCIONAL) ("ej. Streaming · Estándar").
  - MONTO (COP) ("24900", teclado numérico), obligatorio y mayor a 0. Error: "Ingresa un monto mayor a 0".
  - FRECUENCIA: pills Mensual / Anual / Semanal (por defecto Mensual).
  - PRÓXIMO COBRO (selector de fecha), obligatorio. Error: "Elige la fecha del próximo cobro". Si es prueba, la etiqueta cambia a "PRIMER COBRO (AL TERMINAR LA PRUEBA)".
  - Switch "Es una prueba gratis" / "Activa el aviso de fin de prueba". Encendido, aparece FIN DE LA PRUEBA (fecha), obligatorio. Error: "Elige cuándo termina la prueba".
- Pie fijo: primario "Guardar suscripción" / "Guardar cambios". En modo editar, debajo va el botón de texto rojo **"Eliminar suscripción"**.
- Eliminar abre el diálogo **"¿Eliminar {servicio}?"** / "Se borra de tu lista junto con su historial de pagos y sus recordatorios. Esto no cancela el servicio con el proveedor y no se puede deshacer.", con los botones "Eliminar suscripción" y "No, volver".
- Al guardar: en modo agregar vuelve a la pantalla anterior con el toast "{servicio} se agregó a tu lista". En modo editar vuelve al detalle con el toast "Cambios guardados". Al eliminar va al dashboard con el toast "{servicio} se eliminó de tu lista".
- Una suscripción nueva queda con `origen = manual`, `estado = activa` y color de logo `#334155`.

### 14 Perfil y configuración · prioridad 1 para nombre, correo y cerrar sesión; el resto después
- Pestaña 4. Hero: avatar de 52 con iniciales, nombre 18/800 y "{correo} · Colombia (COP)". Los datos vienen de `Usuario` (backend).
- Tarjeta "Avisarme antes de cada cobro" / "Preferencia global" con el selector de días.
- Lista: "Permiso de notificaciones" con switch ("Activo · detección automática encendida" / "Desactivado · solo registro manual") · "Resumen mensual" con switch ("Cada 1 del mes") · "Historial y ahorro" con "{ahorro} ›" en `link` (lleva a 12) · "Agregar suscripción manual ›" (lleva a 13).
- Botones: outline "Cerrar sesión" (borra el token y lleva a 02 login) y ámbar "Eliminar cuenta y todos mis datos", que abre el diálogo "¿Eliminar tu cuenta?" / "Borramos tu cuenta, tus suscripciones, el historial y los recordatorios. Esto no se puede deshacer." con el botón "Eliminar cuenta y datos".

### Notificación push (simulada)
Banner glass arriba (top 44, márgenes de 12, radio 20) con la marca "S", título 12.5/800, cuerpo 12.5 y "SubTrack · ahora". Al tocarlo abre el detalle de esa suscripción. Ejemplos:
- "Netflix se cobra en 3 días" / "$38.900 el 20 de septiembre. Si ya no la quieres, este es el momento."
- "Tu prueba de GeForce NOW termina en 2 días" / "El 19 de septiembre pasa a $89.900/mes."
- "Adobe Photoshop subió de precio" / "De $41.900 a $47.900/mes desde este cobro."
- "¿Tienes una suscripción a Smart Fit?" / "Detectamos 3 cobros de $89.900 con la misma periodicidad."

---

## 4. Datos que necesitan las pantallas de prioridad 1

Campos de `suscripciones` según la spec (sección 8), más los que pide el diseño:

| Campo | Lo usa | Nota |
|---|---|---|
| `id`, `nombre_servicio`, `monto`, `moneda`, `frecuencia` (mensual/anual/semanal) | 07, 08, 09, 13 | Spec |
| `fecha_proximo_cobro`, `es_prueba_gratis`, `fecha_fin_prueba` | 07, 08, 09, 13 | Spec |
| `origen` (notificacion/manual), `estado` (activa/marcada_para_cancelar/cancelada) | 08, 09 | Spec |
| `fecha_deteccion` o fecha de creación | 09 "Desde" | Spec |
| `categoria` (texto opcional) | 07, 08, 09, 13 | **No está en la spec.** El diseño la muestra bajo el nombre. Si no se agrega, mostrar "{Frecuencia} · Registro manual" |
| `historial_pagos` (fecha, monto) | 09 historial y "Pagado en total" | Tabla de la spec |
| `dias_anticipacion` por suscripción | 09 selector | **No está en la spec** (solo existe la global en `usuarios`). Opcional en prioridad 1 |
| Monto anterior (cambio de precio) | flag "Subió de…" | Se puede derivar del historial de pagos |
| Color e iniciales del logo | tarjetas | Se calculan en la app a partir del nombre. No hace falta guardarlos |

Operaciones necesarias: listar las activas del usuario, ver una, crear, actualizar, eliminar y cambiar `estado` (marcar o cancelar). Todas usan el JWT que `AuthService` ya maneja.

## 5. Navegación (go_router)

- Sin sesión: `/` (01) → `/registro` o `/login` (02) → `/permisos` (03) → `/escaneo` (04) → `/deteccion` (05) → `/preferencias` (06) → `/resumen`.
- Con sesión: `ShellRoute` con barra de pestañas: `/resumen` (07), `/suscripciones` (08), `/avisos` (11), `/perfil` (14). Dentro del shell: `/suscripcion/:id` (09) y `/ahorro` (12).
- Fuera del shell (sin pestañas): `/suscripcion/nueva` y `/suscripcion/:id/editar` (13), `/suscripcion/:id/cancelar` (10).
- "Volver" usa `context.pop()`. Las pestañas usan `context.go()`.
- Mientras el onboarding no se implemente, `main.dart` puede seguir abriendo `/` y `/login` como hoy.
