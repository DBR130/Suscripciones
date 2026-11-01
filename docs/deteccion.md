# Detección automática de suscripciones

Lectura de notificaciones de pago en Android (RF02, RF03, flujo B de la
especificación). Este documento describe la arquitectura, las decisiones de
privacidad y cómo probar cada parte. Se actualiza al terminar cada hito.

| Hito | Contenido | Estado |
|---|---|---|
| 1 | Lector nativo, cola local, canales con Flutter y pantalla de depuración | **Hecho** |
| 2 | Parser en Dart: comercio, monto, moneda, fecha y banco | **Hecho** |
| 3 | Backend: pagos detectados y candidatos de suscripción | **Hecho** |
| 4 | Pantallas 03, 04, 05 y flujo B | Pendiente |

## Arquitectura

```
 Notificación del banco o SMS
            │
            ▼
 ┌────────────────────────────────────────── Android (Kotlin, paquete deteccion/) ─┐
 │ LectorNotificacionesService  (NotificationListenerService)                     │
 │   1. ¿La app está en la lista permitida?  ── no ──► se ignora                  │
 │   2. ¿El texto parece un cobro? (FiltroCobros) ── no ──► se descarta           │
 │   3. Se guarda en ColaNotificaciones (filesDir/deteccion/cola.json)            │
 │   4. Si la app está abierta, se avisa en vivo                                  │
 └──────────────┬───────────────────────────────────────┬─────────────────────────┘
                │ MethodChannel "subtrack/deteccion"    │ EventChannel "subtrack/deteccion/eventos"
                ▼                                       ▼
 ┌──────────────────────────────────────── Flutter (lib/deteccion/) ───────────────┐
 │ LectorNotificaciones: estado, permiso, leer/borrar cola, eventos en vivo        │
 │ (hito 2) Parser → campos extraídos   (hito 4) Escaneo y resultados              │
 └──────────────┬──────────────────────────────────────────────────────────────────┘
                │ solo campos extraídos (comercio, monto, moneda, fecha, banco)
                ▼
          Backend (hito 3): pagos_detectados, candidatos_suscripcion
```

### Parte nativa (`android/app/src/main/kotlin/.../deteccion/`)

| Archivo | Qué hace |
|---|---|
| `LectorNotificacionesService.kt` | Servicio que Android ejecuta aunque la app esté cerrada. Recibe cada notificación (`onNotificationPosted`), aplica los filtros y guarda las que parecen cobros. Toma el texto largo (`EXTRA_BIG_TEXT`), el último mensaje si la app usa MessagingStyle (Google Mensajes) o el texto corto. Ignora resúmenes de grupo y notificaciones fijas. Al conectarse revisa las notificaciones activas de la barra (`getActiveNotifications`) y al desconectarse pide reconexión (`requestRebind`). |
| `RegistroDeteccion.kt` | Horas de la última conexión, desconexión y notificación (SharedPreferences) y el único punto de logs (tag `SubTrackDeteccion`, solo en debug). |
| `ReconexionReceiver.kt` | Al reiniciar el celular o actualizar la app, pide reconectar el lector. |
| `FiltroCobros.kt` | Decide si un texto "parece un cobro": debe tener un monto **y** una palabra de cobro, y no tener palabras excluidas. Compara sin tildes ni mayúsculas. |
| `ColaNotificaciones.kt` | Cola en `filesDir/deteccion/cola.json` (almacenamiento interno: solo esta app puede leerlo). Máximo 200 entradas, se borran solas a los 30 días, no guarda dos veces el mismo texto de la misma app y escribe de forma atómica. |
| `ConfiguracionDeteccion.kt` | Lee la configuración de `res/raw/deteccion_apps.json`. |
| `CanalDeteccion.kt` | MethodChannel y EventChannel con Flutter; abre los ajustes de "Acceso a notificaciones" y detecta si el permiso está concedido. |

El servicio está declarado en `AndroidManifest.xml` con el permiso
`BIND_NOTIFICATION_LISTENER_SERVICE`: solo el sistema puede conectarse a él, y
solo después de que el usuario lo autoriza en Ajustes.

**Canal de métodos** `subtrack/deteccion`:

| Método | Devuelve |
|---|---|
| `estado` | `{permiso, conectado, es_debug, modo_descubrimiento, ultima_conexion, ultima_desconexion, ultima_notificacion, ultimo_resultado}` (horas en milisegundos) |
| `abrirAjustesAcceso` | Abre el ajuste de SubTrack en "Acceso a notificaciones" (Android 11+) o la lista general |
| `reconectar` | Si hay permiso pero el servicio está desconectado, pide a Android reconectarlo (`requestRebind`) |
| `recuperarActivas` | Revisa las notificaciones activas de la barra y guarda las que falten. Devuelve cuántas guardó, o `-1` si el servicio no está conectado |
| `leerCola` | Lista de `{id, paquete, app, titulo, texto, recibida_en}` |
| `borrarDeCola` `{ids}` / `vaciarCola` | Quita las procesadas / todas |
| `configuracion` | Apps permitidas y palabras de cobro |
| `modoDescubrimiento` `{activo}` | Solo en debug; en release responde "no implementado" (ver privacidad) |

**Canal de eventos** `subtrack/deteccion/eventos`: `{tipo: guardada, notificacion}`,
y en modo descubrimiento (solo debug) también `{tipo: descartada, paquete, motivo}` y
`{tipo: descubierta, paquete}`, sin título ni texto.

### Configuración (`android/app/src/main/res/raw/deteccion_apps.json`)

```json
{
  "apps_permitidas": [ { "paquete": "com.google.android.apps.messaging", "nombre": "Mensajes de Google (SMS)" } ],
  "apps_solo_debug": [ { "paquete": "com.android.shell", "nombre": "Shell (simulación con adb)" } ],
  "palabras_cobro": ["compra", "compraste", "pago", "pagaste", "debito", "transaccion"],
  "palabras_excluidas": ["codigo", "clave", "otp", "contrasena"]
}
```

- `apps_permitidas` solo tiene paquetes verificados en el celular real con
  el modo descubrimiento (ver "Cómo probar"): por ahora, Mensajes de Google.
  Los bancos se agregan cuando se identifiquen. Después de editarlo hay que
  recompilar la app.
- `apps_solo_debug` solo se carga en compilaciones debug (`flutter run`). En
  release nadie puede simular pagos con el shell.

### Parte Flutter (`lib/deteccion/`)

| Archivo | Qué hace |
|---|---|
| `lector_notificaciones.dart` | Puente con la parte nativa. Fuera de Android (Chrome, tests) no hace nada. |
| `notificacion_capturada.dart` | Modelos: notificación capturada, evento en vivo, estado y configuración. |
| `depuracion_deteccion_page.dart` | Pantalla "Depuración: detección" (solo debug): estado, apps permitidas, eventos en vivo, cola con lo que extrae el parser y comando de simulación. Se abre desde Perfil. |
| `parser_pagos.dart` | Parser (hito 2): de un texto de cobro saca banco, monto, moneda, comercio normalizado, fecha y medio. |
| `catalogo_servicios.dart` | Nombres y alias del catálogo de guías (`GET /api/guias`) para reconocer servicios conocidos. |

Al abrir la app y cada vez que vuelve a primer plano, `main.dart` llama a
`sincronizar()`: pide reconectar el servicio si está detenido y recupera las
notificaciones activas de la barra.

## Problema encontrado en la primera prueba (hito 1) y solución

**Síntoma (Xiaomi, Android 16).** Con la app abierta en la pantalla de
depuración, el pago simulado quedaba en la cola. Con la app en segundo plano
o cerrada desde recientes, la notificación aparecía en el celular pero no
quedaba en la cola, ni siquiera al tocar "Actualizar".

**Diagnóstico (revisión del código, sin acceso al celular):**

1. El guardado ya era 100 % nativo: `onNotificationPosted` escribe la cola
   antes de avisar a Flutter y no usa el motor de Flutter. El problema no era
   que el guardado dependiera de la pantalla.
2. **Error que podía matar el servicio.** El aviso en vivo se enviaba al hilo
   principal fuera del `try/catch`. Al cerrar la app, el motor de Flutter se
   destruye pero nadie quitaba el oyente: la siguiente notificación podía
   llamar a un `EventSink` muerto, lanzar una excepción en el hilo principal
   y **cerrar el proceso completo, servicio incluido**. MIUI no siempre lo
   vuelve a iniciar hasta que se abre la app.
3. **MIUI/HyperOS al quitar la app de recientes** suele forzar su cierre.
   Android desconecta el lector de una app detenida y **no le vuelve a
   entregar** las notificaciones publicadas mientras estuvo desconectado.
4. **Duplicados a propósito.** La cola no guarda dos veces el mismo texto de
   la misma app: si una prueba repite el texto de otra, queda como "repetida".

**Solución:**

- El aviso en vivo nunca puede lanzar una excepción: está protegido en el
  servicio y en el canal, y `MainActivity.cleanUpFlutterEngine` quita el
  oyente al cerrar la app.
- **Recuperación desde la barra:** al conectarse el servicio, al abrir la app
  y al volver a primer plano se leen las notificaciones activas
  (`getActiveNotifications`) de las apps permitidas y se agregan a la cola sin
  duplicar (misma huella, o misma app y texto). Así se recupera lo que llegó
  mientras el servicio estaba detenido, **siempre que siga en la barra** (si
  el usuario la borró antes de abrir la app, se pierde).
- **Reconexión:** `requestRebind` al abrir la app, al volver a primer plano,
  cuando el servicio se desconecta y tras reiniciar el celular o actualizar
  la app (`ReconexionReceiver`).
- **Diagnóstico visible:** la pantalla de depuración muestra si el servicio
  está conectado ahora y las horas de la última conexión, desconexión y
  notificación recibida (con su resultado). Además hay logs con el tag
  `SubTrackDeteccion`.

### Ver los logs (PowerShell)

```powershell
# Limpiar lo anterior y ver solo los logs del lector, con hora:
adb logcat -c
adb logcat -v time -s SubTrackDeteccion:V

# Igual, pero mostrando también si la app se cierra por un error:
adb logcat -v time -s SubTrackDeteccion:V AndroidRuntime:E
```

`-s` deja en silencio todo lo demás y muestra solo los tags indicados. Se
detiene con Ctrl+C. Mensajes que deben aparecer:

| Log | Significa |
|---|---|
| `Servicio conectado` | Android conectó el lector |
| `Notificaciones activas revisadas: N, guardadas: M` | Recuperación desde la barra |
| `Recibida de com.android.shell: guardada` | Pago guardado en la cola |
| `Recibida de ...: repetida` | Ya estaba en la cola (mismo texto) |
| `Recibida de ...: descartada (no tiene palabras de cobro)` | No parecía un cobro |
| `Recibida de ...: app no permitida` | App fuera de la lista (no se lee su texto) |
| `Cola escrita: N notificaciones` | Se guardó el archivo de la cola |
| `Servicio desconectado: se pide reconexión` | Android o MIUI detuvo el lector |

Los logs solo salen en compilaciones debug (en release no hay ninguno) y
**nunca incluyen el texto ni el título** de la notificación; de un error solo
se anota su tipo (por ejemplo `JSONException`).

### Comandos útiles de diagnóstico

```powershell
# ¿El sistema tiene el lector conectado? (buscar la línea con LectorNotificacionesService)
adb shell dumpsys notification | Select-String LectorNotificacionesService

# Dar el acceso a notificaciones desde el PC (solo para pruebas)
adb shell cmd notification allow_listener com.example.flutter_suscripciones/com.example.flutter_suscripciones.deteccion.LectorNotificacionesService
```

## Parser (hito 2)

`ParserPagos.interpretar(texto, titulo:, recibidaEn:)` devuelve un
`InterpretacionPago`: un `PagoExtraido` o el motivo por el que **no es un
cobro**. Es código Dart puro (sin Flutter ni red), probado en
`test/deteccion_parser_test.dart` con los SMS reales de
`test/fixtures/notificaciones_reales.json`.

### Pasos

1. **¿Es claramente otra cosa?** Se descarta si el texto (sin tildes ni
   mayúsculas) tiene palabras de:

   | Motivo | Palabras |
   |---|---|
   | código de verificación | código, clave, OTP, contraseña, verificación |
   | dinero recibido | recibiste, recibió, te enviaron, te envió, te consignaron, consignación, abono |
   | transferencia | transferiste, transferencia, enviaste |
   | recarga | recarga, recargaste, recargar |
   | retiro de dinero | retiro, retiraste |
   | publicidad | aprovecha, descuento, promoción, oferta, sorteo, participa, gana |

2. **Banco.** Por el título de la notificación, el remitente al inicio del
   texto ("Bancolombia: …", "NEQUI: …") o el texto. Bancos reconocidos:
   Bancolombia, Nequi, Davivienda, Daviplata, BBVA, Banco de Bogotá y
   Scotiabank Colpatria. **Sin banco conocido no hay cobro** (un SMS personal
   con "te pagué 15.000" no cuenta).
3. **Forma del cobro:** "compraste / pagaste / compra / pago / débito / realizaste
   una compra" + (por/de) + **monto** + "en"/"a" + **comercio**. El comercio
   termina en " con tu", " desde", ", ", " el <fecha>", un punto final o el
   fin del texto.
4. **Monto y moneda.** "$19.900,00" → 19900, "$26.900" → 26900, "68.139,27" →
   68139.27, "COP 26,900.00" → 26900, "USD 20.00" → 20 USD. Si hay punto y coma,
   el último es el decimal; si hay uno solo, es de miles cuando lo siguen
   grupos de 3 dígitos y decimal cuando lo siguen 1 o 2. Sin "USD"/"US$" se
   asume COP. Un número ambiguo ("12.3456") no se adivina.
5. **Fecha.** "el 23/10/2026 a las 07:20", "23/10/26 18:05" o solo la fecha. Si
   no la trae, o es imposible (31/02), se usa la hora de llegada de la
   notificación (`fechaDelMensaje = false`).
6. **Medio:** "T.Deb", "T.Cred", "tarjeta de crédito"… **sin los dígitos** de la
   tarjeta. Los teléfonos del mensaje tampoco se guardan en ningún campo.
7. **Comercio normalizado:**
   - Se quitan prefijos de pasarelas: `GOOGLE *`, `APPLE.COM/BILL`, `PAYPAL *`,
     `EBANX`. Si no queda nada ("APPLE.COM/BILL" solo), el comercio es la
     pasarela (Apple).
   - "SUB" (o "suscripción", "subscription") marca `indicaSuscripcion` y se
     quita del nombre.
   - Se busca en el catálogo de guías, igual que `buscarGuia` del backend
     (palabras completas, gana el alias más largo): "NETFLIX.COM",
     "Netflix*Bogota" y "NETFLIX INC" → **Netflix**; "ANTHROPIC* CLAUDE SUB" →
     **Claude**. Si lo encuentra, `servicio` es el nombre del catálogo.
   - Si no está en el catálogo, se deja legible: sin ".COM", "INC", "SAS", sin
     la ciudad después de "*", y con mayúscula inicial ("DIDI FOOD" →
     "Didi Food"). `servicio` queda en null: **compra normal**.

**Claude** (alias "Claude Pro", "Claude Max", "Anthropic") se agregó al
catálogo (`backend/db/guias.json`) como servicio conocido, con una guía de
cancelación general. En una BD que ya existía hay que cargarlo con
`npm run db:guias`.

### Los 3 ejemplos reales

| SMS | Banco | Monto | Comercio | Fecha | Servicio |
|---|---|---|---|---|---|
| Bancolombia: Compraste $19.900,00 en GOOGLE *Crunchyroll con tu T.Deb *0000, el 23/10/2026 a las 07:20. Si tienes dudas… | Bancolombia | 19.900 COP | Crunchyroll | 23/10/2026 07:20 (del mensaje) | Crunchyroll |
| NEQUI: Pagaste 68.139,27 en ANTHROPIC* CLAUDE SUB | Nequi | 68.139,27 COP | Claude (SUB) | llegada | Claude |
| Bancolombia: Compraste $18.900,00 en DIDI FOOD con tu T.Deb *0000, el 30/10/2026 a las 13:10. | Bancolombia | 18.900 COP | Didi Food | 30/10/2026 13:10 (del mensaje) | ninguno (compra normal) |

El tercero se interpreta bien, pero no es un servicio del catálogo. Que un solo
pago así **no cree un candidato de suscripción** lo decide el backend en el
hito 3 (hacen falta pagos repetidos, o un servicio conocido).

### Decisiones del parser

- **Conservador:** ante la duda, "no es un cobro". Es peor inventar una
  suscripción que perder un cobro (el usuario siempre puede agregarla a mano).
- **Solo bancos conocidos.** Evita que un SMS de spam con "Compraste $… en …"
  pase como cobro. Para agregar un banco basta una línea en `_bancos`.
- **El catálogo viene del backend.** Así hay una sola lista de servicios y
  alias. Sin conexión, el parser funciona igual, pero no reconoce servicios.

## Backend de detecciones (hito 3)

Archivos: `backend/db/migraciones/006_detecciones.sql`,
`backend/src/services/detecciones.js` (reglas),
`backend/src/controllers/detecciones.controller.js`,
`backend/src/routes/detecciones.routes.js` y
`backend/test/detecciones.test.js`.

### Tablas (migración 006)

| Tabla | Qué guarda |
|---|---|
| `pagos_detectados` | Cada cobro ya interpretado: comercio (como venía y normalizado), monto, moneda, fecha, banco, huella y, si corresponde, la suscripción a la que pertenece. `UNIQUE (usuario_id, huella)`: la misma notificación nunca se registra dos veces |
| `candidatos_suscripcion` | Posibles suscripciones: comercio, monto, moneda, frecuencia estimada, estado (`pendiente`, `confirmada`, `descartada`), suscripción creada, si es un servicio conocido, banco y fecha del último pago. Un solo candidato por usuario y comercio (sin importar mayúsculas) |

La huella es única **por usuario** y no global: así nadie puede averiguar,
enviando una huella, si otro usuario ya la registró.

### Endpoints (todos con sesión)

| Método y ruta | Qué hace |
|---|---|
| `POST /api/detecciones/pagos` | Recibe `{pagos: [...]}` (máx. 100) y devuelve `{resultados, candidatos_nuevos}` |
| `GET /api/detecciones/candidatos` | Candidatos pendientes (`?estado=pendiente,confirmada,descartada` para otros), con `num_pagos` |
| `POST /api/detecciones/candidatos/:id/confirmar` | Crea la suscripción. Cuerpo opcional con los datos corregidos (mismos campos que una suscripción); lo que falte sale del candidato. 201 `{suscripcion, candidato, pagos_enlazados}` |
| `POST /api/detecciones/candidatos/:id/descartar` | El comercio no se vuelve a proponer. `{candidato}` |

Cada pago del lote:

```json
{
  "huella": "<SHA-256 en hexadecimal, 64 caracteres>",
  "comercio": "GOOGLE *Crunchyroll",
  "comercio_normalizado": "Crunchyroll",
  "monto": 19900,
  "moneda": "COP",
  "fecha": "2026-10-23T07:20:00",
  "banco": "Bancolombia"
}
```

- `fecha` es la hora local de Colombia, **sin zona** (como
  `DateTime.toIso8601String()` en Dart, que también se acepta con milisegundos).
- Si un pago no es válido, se rechaza **todo el lote** (400) y no se guarda nada.
- **Privacidad:** si un pago trae `texto` o `titulo`, se rechaza con 400. El
  texto de la notificación nunca debe llegar al servidor.
- Confirmar o descartar un candidato que ya no está pendiente: 409. Uno de
  otro usuario: 404 (como en suscripciones, no se revela que existe).

### Reglas de cada pago

Los pagos del lote se procesan en orden de fecha, en una transacción.

| Orden | Caso | Condición | Qué pasa | `resultado` |
|---|---|---|---|---|
| 0 | Repetido | La huella ya estaba | Nada | `repetido` |
| 1 | **a)** Suscripción existente | El comercio coincide con una suscripción activa o marcada para cancelar del usuario: uno contiene al otro ("Netflix" y "Netflix Estándar") o llevan a la misma guía ("Max" y "HBO Max") | Se enlaza el pago y se agrega al historial. Si el monto cambió **más de 5 %**, se registra en `cambios_precio` y se actualiza el monto (RF08 automático) | `suscripcion_existente` |
| 2 | **b)** Servicio conocido | El comercio está en el catálogo de guías (incluye Claude) | Candidato pendiente desde el primer pago, frecuencia mensual (o la estimada si ya hay varios pagos). Se guarda con el nombre del catálogo | `candidato_nuevo` / `candidato_actualizado` |
| 3 | **c)** Comercio desconocido | 2 o más pagos al mismo comercio, en la misma moneda, con montos a ±10 % y **todos** los intervalos semanales (6-8 días), mensuales (26-35) o anuales (355-375) | Candidato pendiente con esa frecuencia | `candidato_nuevo` / `candidato_actualizado` |
| 4 | Compra normal | Comercio desconocido sin esa periodicidad (DiDi Food con un pago) | Solo queda el pago registrado | `compra_normal` |

Además: si el comercio ya fue **descartado**, `comercio_descartado` (no se vuelve
a proponer); si ya se **confirmó** y su suscripción existe, `ya_confirmado`. Si
el usuario borró esa suscripción, el comercio se vuelve a proponer.
`candidatos_nuevos` trae los candidatos creados en este envío: la app los usará
para la notificación del flujo B (hito 4).

Detalles del caso a):

- **Tolerancia de 5 %**: un cobro en USD que el banco convierte a COP (Claude
  por Nequi) varía un poco cada mes por la tasa de cambio; eso no es un cambio
  de precio. 26.900 → 29.900 (11 %) sí lo es.
- Si el proceso automático de cobros ya registró ese cobro (±3 días), no se
  duplica en el historial.
- Un pago en otra moneda que la suscripción solo se enlaza: `historial_pagos`
  no guarda moneda.
- Un pago viejo que llega después de uno más nuevo no cambia el precio.

Al **confirmar**: la suscripción se crea con `origen = 'notificacion'`,
`fecha_deteccion` = cuando se creó el candidato y, si no se envía, el próximo
cobro = el primero después de hoy contando desde el último pago. Los pagos
detectados de ese comercio se enlazan y pasan al historial.

## Privacidad (RNF01, Habeas Data, Ley 1581 de 2012)

La detección trata datos personales (pagos y, de paso, cualquier notificación
del celular), así que se diseñó con dos principios de la Ley 1581 de 2012:

- **Finalidad** (art. 4, literal b): los datos se usan solo para lo que se le
  informa al usuario, detectar cobros de suscripciones. Nada más.
- **Minimización**: de cada notificación se usa lo mínimo necesario para esa
  finalidad, y todo lo demás se descarta lo antes posible. (La ley no usa esa
  palabra; se desprende del principio de finalidad. Para el informe conviene
  citarla así.)

También se apoyan en los principios de **libertad** (literal c: nada funciona
sin la autorización del usuario), **seguridad** (literal g) y **acceso y
circulación restringida** (literal f).

### 1. Qué recibe Android al dar el acceso

Al activar SubTrack en "Acceso a notificaciones", Android le entrega al
servicio **todas** las notificaciones de **todas** las apps: chats, correo,
redes sociales, bancos. Es una limitación de Android: no existe un permiso
"solo de estas apps". Por eso el primer paso del servicio es filtrar, y
Android muestra una advertencia fuerte al activarlo.

### 2. Qué se descarta en memoria (sin guardarse)

| Notificación | Qué se mira | Qué pasa |
|---|---|---|
| De una app **fuera de la lista** (WhatsApp, Gmail, Instagram…) | Solo el **nombre del paquete**, para compararlo con la lista | Se descarta en el acto. **No se lee ni el título ni el texto** (en chats y SMS el título es el nombre del contacto) |
| De una app permitida, pero **no parece un cobro** ("prueba" de un contacto, "Recibiste…", publicidad sin monto) | El texto, en memoria, para decidir | Se descarta: no se guarda ni se escribe en ningún log |
| Con "código", "clave", "OTP" o "contraseña" | El texto, en memoria | Se descarta siempre, aunque tenga monto |
| Resúmenes de grupo y notificaciones fijas (música, descargas) | Solo sus banderas | Se ignoran |

Apps permitidas hoy: **Mensajes de Google (SMS)**, encontrada con el modo
descubrimiento en el celular de pruebas. Los bancos y billeteras se agregarán
cuando se identifiquen sus paquetes (no se inventan nombres de paquete).

### 3. Qué se guarda en el celular

| Dónde | Qué | Límites |
|---|---|---|
| Cola: `filesDir/deteccion/cola.json` (almacenamiento interno, solo SubTrack puede leerlo) | Solo las notificaciones que parecen cobros: huella, paquete, nombre de la app, título (el remitente, p. ej. "Bancolombia"), texto y hora de llegada | Máximo 200, se borran solas a los 30 días y al desinstalar. Desde el hito 4, también al enviarlas al backend |
| SharedPreferences `subtrack_deteccion` | Hora de la última conexión, desconexión y notificación, y una palabra de resultado ("guardada", "descartada"…) | Sin paquete, título ni texto |

El parser (hito 2) lee la cola en el mismo celular; no la copia a otro lado.

### 4. Qué va al backend (hitos 3 y 4)

Solo los **campos extraídos** por el parser: banco, comercio normalizado,
monto, moneda, fecha y una huella para no repetir pagos, con la sesión del
usuario. **Nunca** el texto crudo, el título, los dígitos de la tarjeta ni los
teléfonos que traen los mensajes.

### 5. Herramientas de desarrollo (no existen en release)

- **Modo descubrimiento**: en debug, muestra el **paquete** de las apps no
  permitidas, sin título ni texto. Vive solo en memoria y se apaga al salir de
  la pantalla. En release el método nativo responde "no implementado".
- **Pantalla de depuración**: en release la ruta no se registra
  (`Routers.crear(depuracion: kDebugMode)`), la fila de Perfil no existe y el
  compilador elimina la pantalla. No se puede abrir ni escribiendo la ruta.
- **Simulación con adb** (`com.android.shell`): solo se permite en debug.
- **Logs** (`SubTrackDeteccion`): solo en debug, con el paquete y el resultado,
  **nunca con el texto ni el título**; de un error solo se anota su tipo. En
  release no se escribe ningún log.

### 6. Autorización y revocación

Nada funciona hasta que el usuario activa SubTrack en "Acceso a
notificaciones", y puede quitarlo cuando quiera desde los ajustes de Android.

## Cómo probar (hito 1)

### Preparación

1. Conecta el Xiaomi por USB y lanza la app en **debug** con la configuración
   "Celular USB (localhost)" (y `adb reverse tcp:3000 tcp:3000` para el backend).
2. Entra a **Perfil → Depuración: detección**.
3. Toca **Dar acceso** y activa SubTrack en "Acceso a notificaciones". Al
   volver, la pantalla debe decir *Acceso: Concedido* y *Servicio: Conectado*.
4. En Xiaomi, sigue la guía de la misma pantalla: **Inicio automático** activado
   y **Ahorro de batería → Sin restricciones**.

> **"Ajuste restringido"** (Android 13+): si al activar el acceso aparece ese
> aviso, ve a Ajustes → Apps → SubTrack → menú ⋮ → **Permitir ajustes
> restringidos**, y vuelve a intentarlo. Suele pasar con apps instaladas desde
> un archivo APK.

### Simular un pago desde el PC

En debug, el paquete `com.android.shell` está permitido, así que `adb` puede
publicar notificaciones de prueba. Formato del comando (`adb shell cmd notification help`,
o `--help` según la versión, muestra la ayuda completa en el celular):

```
cmd notification post [-S <estilo>] [-t <título>] <etiqueta> <texto>
```

- `-S bigtext`: estilo de texto largo (como los SMS largos).
- `<etiqueta>`: identifica la notificación. Si repites la misma, se reemplaza
  la anterior: usa `pago1`, `pago2`, etc.

**Hay dos capas que interpretan el signo `$`**: PowerShell en el PC y el shell
del celular (`adb shell` une los argumentos y el celular los vuelve a
interpretar). Por eso el texto va entre comillas simples dentro de comillas
dobles, y en PowerShell el `$` lleva una comilla invertida antes:

**PowerShell:**

```powershell
adb shell "cmd notification post -S bigtext -t 'Bancolombia' pago1 'Bancolombia: Compraste `$19.900,00 en GOOGLE *Crunchyroll con tu T.Deb *0000, el 23/10/2026 a las 07:20.'"
```

**Git Bash:**

```bash
adb shell "cmd notification post -S bigtext -t 'Bancolombia' pago1 'Bancolombia: Compraste \$19.900,00 en GOOGLE *Crunchyroll con tu T.Deb *0000, el 23/10/2026 a las 07:20.'"
```

Verificación hecha sin celular: lo que PowerShell entrega a `adb` y cómo lo
parte el shell del celular, simulado con `sh`. El texto llega como un solo
argumento con `$19.900,00` intacto. Sin las comillas simples internas, el
shell del celular convierte `$19.900,00` en `9.900,00` (lee `$1` como una
variable vacía).

Más pruebas (PowerShell):

```powershell
# Nequi, sin fecha en el texto
adb shell "cmd notification post -S bigtext -t 'Nequi' pago2 'NEQUI: Pagaste 68.139,27 en ANTHROPIC* CLAUDE SUB'"

# Debe DESCARTARSE: no es un cobro (transferencia recibida)
adb shell "cmd notification post -S bigtext -t 'Nequi' pago3 'NEQUI: Recibiste 50.000 de JUAN PEREZ'"

# Debe DESCARTARSE: código de verificación, aunque tenga monto
adb shell "cmd notification post -S bigtext -t 'Bancolombia' pago4 'Bancolombia: tu codigo para la compra de `$19.900 es 123456'"

# Borrar una notificación de prueba
adb shell "cmd notification cancel pago1"
```

### Qué debe pasar

| Caso | Resultado esperado |
|---|---|
| Pago simulado con la app **abierta** en la pantalla de depuración | Aparece en "En vivo" como **GUARDADA** y en "Cola guardada" |
| Pago simulado con la app **en segundo plano** (botón de inicio) | Al volver, está en "Cola guardada". En logcat: `Recibida de com.android.shell: guardada` |
| Pago simulado con la app **cerrada** (deslízala fuera de recientes) | Al abrirla, está en "Cola guardada": la guardó el servicio, o se recuperó de la barra al abrir (log `Notificaciones activas revisadas`). Si borraste la notificación de la barra antes de abrir la app y el servicio estaba detenido, se pierde |
| "Recibiste…" o código de verificación | No queda en la cola. Con modo descubrimiento: **DESCARTADA** con el motivo |
| Mismo texto enviado dos veces con otra etiqueta | Queda una sola vez en la cola |
| Notificación de WhatsApp o Gmail con modo descubrimiento | **APP NO PERMITIDA**: solo el paquete, sin título ni texto |
| SMS personal ("prueba") de un contacto | No queda en la cola. Con modo descubrimiento: **DESCARTADA** (no tiene palabras de cobro / monto), sin el nombre del contacto |
| Celular reiniciado | Tras desbloquearlo, el servicio vuelve a conectarse (puede tardar) |

### Identificar los paquetes del banco y del SMS

1. En la pantalla de depuración, activa **Modo descubrimiento**.
2. Espera (o provoca) un SMS de Bancolombia o Nequi, o una notificación de la
   app del banco.
3. Aparece como **APP NO PERMITIDA** con su paquete. Selecciónalo y cópialo.
4. Agrégalo a `apps_permitidas` en `res/raw/deteccion_apps.json`, recompila y
   repite: ahora debe salir como **GUARDADA** (si es un cobro).

## Cómo probar (hito 2)

1. Si la BD ya existía, carga Claude en el catálogo: en `backend/`,
   `npm run db:guias`. Arranca el backend y `adb reverse tcp:3000 tcp:3000`.
2. Lanza la app en debug en el Xiaomi, **inicia sesión** (el catálogo se pide
   con la sesión) y entra a **Perfil → Depuración: detección**. En "Apps
   permitidas" debe decir *Catálogo de servicios: 20 (de /api/guias)*.
3. Toca **Vaciar cola**: la cola no guarda dos veces el mismo texto, y las
   pruebas del hito 1 usaban algunos de estos.
4. Simula los 3 ejemplos (PowerShell):

```powershell
# 1) Bancolombia, Crunchyroll (con los teléfonos del mensaje real)
adb shell "cmd notification post -S bigtext -t 'Bancolombia' real1 'Bancolombia: Compraste `$19.900,00 en GOOGLE *Crunchyroll con tu T.Deb *0000, el 23/10/2026 a las 07:20. Si tienes dudas, encuentranos aqui: 6045109095 o 018000931987. Estamos cerca.'"

# 2) Nequi, Claude, sin fecha
adb shell "cmd notification post -S bigtext -t 'Nequi' real2 'NEQUI: Pagaste 68.139,27 en ANTHROPIC* CLAUDE SUB'"

# 3) Bancolombia, DiDi Food (compra normal)
adb shell "cmd notification post -S bigtext -t 'Bancolombia' real3 'Bancolombia: Compraste `$18.900,00 en DIDI FOOD con tu T.Deb *0000, el 30/10/2026 a las 13:10.'"
```

En Git Bash, cambia `` `$ `` por `\$`.

5. Debajo de cada entrada de "Cola guardada" debe aparecer:

| Notificación | Lo que muestra |
|---|---|
| real1 | Banco Bancolombia · Monto 19.900 COP · Comercio *Crunchyroll (servicio conocido)* · Original GOOGLE *Crunchyroll · Fecha 23/10/2026 07:20 (del mensaje) · Medio T.Deb |
| real2 | Banco Nequi · Monto 68.139,27 COP · Comercio *Claude (servicio conocido)* · Fecha = hora en que llegó (de llegada) · Indica suscripción (SUB) |
| real3 | Banco Bancolombia · Monto 18.900 COP · Comercio *Didi Food (no está en el catálogo)* · Fecha 30/10/2026 13:10 (del mensaje) |

Más pruebas: cualquier texto que pase el filtro nativo pero no el parser
muestra **"No es un cobro (motivo)"**:

```powershell
# Pasa el filtro nativo (tiene "pago" y monto) pero no es de un banco: no es un cobro
adb shell "cmd notification post -S bigtext -t 'Juan' real4 'Ya te hice el pago de 15.000 del almuerzo'"

# Formato USD
adb shell "cmd notification post -S bigtext -t 'Bancolombia' real5 'Bancolombia: Compraste USD 20.00 en NETFLIX.COM con tu T.Cred *0000'"
```

## Cómo probar (hito 3)

El hito 3 es solo backend: se prueba llamando la API desde el PC. **Usa una
cuenta de prueba**: confirmar un candidato crea una suscripción real en esa
cuenta.

1. Aplica la migración (solo agrega dos tablas; no cambia datos) y arranca el
   backend, en `backend/`:

```powershell
npm run db:migrate   # debe mostrar + 006_detecciones.sql
npm run db:guias     # si no lo hiciste en el hito 2 (Claude)
npm run dev
```

2. En otra terminal de PowerShell, crea la cuenta de prueba y guarda el token:

```powershell
$api = "http://localhost:3000/api"
$r = Invoke-RestMethod -Method Post "$api/auth/registro" -ContentType "application/json" -Body '{"nombre":"Prueba deteccion","correo":"deteccion@prueba.com","password":"secreta123"}'
$h = @{ Authorization = "Bearer $($r.token)" }
# Si la cuenta ya existe, inicia sesión en su lugar:
# $r = Invoke-RestMethod -Method Post "$api/auth/login" -ContentType "application/json" -Body '{"correo":"deteccion@prueba.com","password":"secreta123"}'
```

3. Envía los 3 ejemplos reales, como los mandará la app:

```powershell
function Huella($t) { -join ([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($t)) | ForEach-Object { $_.ToString("x2") }) }
$pagos = @(
  @{ huella = Huella "real1"; comercio = "GOOGLE *Crunchyroll"; comercio_normalizado = "Crunchyroll"; monto = 19900; moneda = "COP"; fecha = "2026-10-23T07:20:00"; banco = "Bancolombia" },
  @{ huella = Huella "real2"; comercio = "ANTHROPIC* CLAUDE SUB"; comercio_normalizado = "Claude"; monto = 68139.27; moneda = "COP"; fecha = "2026-10-28T10:15:00"; banco = "Nequi" },
  @{ huella = Huella "real3"; comercio = "DIDI FOOD"; comercio_normalizado = "Didi Food"; monto = 18900; moneda = "COP"; fecha = "2026-10-30T13:10:00"; banco = "Bancolombia" }
)
$res = Invoke-RestMethod -Method Post "$api/detecciones/pagos" -Headers $h -ContentType "application/json" -Body (ConvertTo-Json @{ pagos = $pagos } -Depth 4)
$res.resultados | Format-Table resultado, candidato_id, suscripcion_id
$res.candidatos_nuevos | Format-Table id, comercio_normalizado, monto, frecuencia_estimada, es_servicio_conocido
```

   Esperado: Crunchyroll y Claude `candidato_nuevo` (servicios conocidos),
   DiDi Food `compra_normal`.

4. Repite el mismo envío: los 3 deben salir `repetido`.
5. Lista, confirma y descarta:

```powershell
$c = (Invoke-RestMethod "$api/detecciones/candidatos" -Headers $h).candidatos
$c | Format-Table id, comercio_normalizado, monto, num_pagos
$crunchy = ($c | Where-Object comercio_normalizado -eq "Crunchyroll").id
$claude = ($c | Where-Object comercio_normalizado -eq "Claude").id

# Confirmar Crunchyroll con la categoría (los demás datos salen del candidato)
Invoke-RestMethod -Method Post "$api/detecciones/candidatos/$crunchy/confirmar" -Headers $h -ContentType "application/json" -Body '{"categoria":"Streaming"}'

# Descartar Claude
Invoke-RestMethod -Method Post "$api/detecciones/candidatos/$claude/descartar" -Headers $h
```

   Crunchyroll debe aparecer en la app (con esa cuenta) con su pago del 23/10 en
   el historial. Un nuevo pago de Claude saldrá `comercio_descartado`.

6. Cambio de precio automático (caso a): un cobro de Crunchyroll más caro.

```powershell
$p = @{ huella = Huella "real4"; comercio = "GOOGLE *Crunchyroll"; comercio_normalizado = "Crunchyroll"; monto = 23900; moneda = "COP"; fecha = "2026-11-23T07:20:00"; banco = "Bancolombia" }
(Invoke-RestMethod -Method Post "$api/detecciones/pagos" -Headers $h -ContentType "application/json" -Body (ConvertTo-Json @{ pagos = @($p) } -Depth 4)).resultados
```

   Esperado: `suscripcion_existente` con `cambio_precio: true`. En la app, el
   detalle de Crunchyroll muestra el cambio de 19.900 a 23.900.

## Pendiente para los siguientes hitos

- Hito 4: pantallas 03, 04 y 05, lectura de notificaciones activas
  (`getActiveNotifications`), flujo B e interruptor real en Perfil.
