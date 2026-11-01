# Detección automática de suscripciones

Lectura de notificaciones de pago en Android (RF02, RF03, flujo B de la
especificación). Este documento describe la arquitectura, las decisiones de
privacidad y cómo probar cada parte. Se actualiza al terminar cada hito.

| Hito | Contenido | Estado |
|---|---|---|
| 1 | Lector nativo, cola local, canales con Flutter y pantalla de depuración | **Hecho** |
| 2 | Parser en Dart: comercio, monto, moneda, fecha y banco | Pendiente |
| 3 | Backend: pagos detectados y candidatos de suscripción | Pendiente |
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
| `depuracion_deteccion_page.dart` | Pantalla "Depuración: detección" (solo debug): estado, apps permitidas, eventos en vivo, cola y comando de simulación. Se abre desde Perfil. |

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
| Cola: `filesDir/deteccion/cola.json` (almacenamiento interno, solo SubTrack puede leerlo) | Solo las notificaciones que parecen cobros: huella, paquete, nombre de la app, título (el remitente, p. ej. "Bancolombia"), texto y hora de llegada | Máximo 200, se borran solas a los 30 días y al desinstalar. Desde el hito 3, también al enviarlas al backend |
| SharedPreferences `subtrack_deteccion` | Hora de la última conexión, desconexión y notificación, y una palabra de resultado ("guardada", "descartada"…) | Sin paquete, título ni texto |

El parser (hito 2) lee la cola en el mismo celular; no la copia a otro lado.

### 4. Qué va al backend (hito 3)

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

## Pendiente para los siguientes hitos

- Hito 2: parser por banco y normalización del comercio con el catálogo de guías.
- Hito 3: endpoints `/api/detecciones/*` y tablas de la migración 006.
- Hito 4: pantallas 03, 04 y 05, lectura de notificaciones activas
  (`getActiveNotifications`), flujo B e interruptor real en Perfil.
