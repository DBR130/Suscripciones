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
| `LectorNotificacionesService.kt` | Servicio que Android ejecuta aunque la app esté cerrada. Recibe cada notificación (`onNotificationPosted`), aplica los filtros y guarda las que parecen cobros. Toma el texto largo (`EXTRA_BIG_TEXT`), el último mensaje si la app usa MessagingStyle (Google Mensajes) o el texto corto. Ignora resúmenes de grupo y notificaciones fijas. |
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
| `estado` | `{permiso, conectado, es_debug, modo_descubrimiento}` |
| `abrirAjustesAcceso` | Abre el ajuste de SubTrack en "Acceso a notificaciones" (Android 11+) o la lista general |
| `reconectar` | Si hay permiso pero el servicio está desconectado, pide a Android reconectarlo (`requestRebind`) |
| `leerCola` | Lista de `{id, paquete, app, titulo, texto, recibida_en}` |
| `borrarDeCola` `{ids}` / `vaciarCola` | Quita las procesadas / todas |
| `configuracion` | Apps permitidas y palabras de cobro |
| `modoDescubrimiento` `{activo}` | Solo en debug (ver privacidad) |

**Canal de eventos** `subtrack/deteccion/eventos`: `{tipo: guardada, notificacion}`,
y en modo descubrimiento también `{tipo: descartada, paquete, titulo, motivo}` y
`{tipo: descubierta, paquete, titulo}`.

### Configuración (`android/app/src/main/res/raw/deteccion_apps.json`)

```json
{
  "apps_permitidas": [ { "paquete": "com.ejemplo.mensajes", "nombre": "App de SMS" } ],
  "apps_solo_debug": [ { "paquete": "com.android.shell", "nombre": "Shell (simulación con adb)" } ],
  "palabras_cobro": ["compra", "compraste", "pago", "pagaste", "debito", "transaccion"],
  "palabras_excluidas": ["codigo", "clave", "otp", "contrasena"]
}
```

- `apps_permitidas` está **vacía a propósito**: los paquetes del banco y de la
  app de SMS se identifican en el celular real con la pantalla de depuración
  (ver "Cómo probar") y luego se agregan aquí. Después de editarlo hay que
  recompilar la app.
- `apps_solo_debug` solo se carga en compilaciones debug (`flutter run`). En
  release nadie puede simular pagos con el shell.

### Parte Flutter (`lib/deteccion/`)

| Archivo | Qué hace |
|---|---|
| `lector_notificaciones.dart` | Puente con la parte nativa. Fuera de Android (Chrome, tests) no hace nada. |
| `notificacion_capturada.dart` | Modelos: notificación capturada, evento en vivo, estado y configuración. |
| `depuracion_deteccion_page.dart` | Pantalla "Depuración: detección" (solo debug): estado, apps permitidas, eventos en vivo, cola y comando de simulación. Se abre desde Perfil. |

Al abrir la app, `main.dart` llama a `reconectarSiHaceFalta()` por si MIUI
detuvo el servicio.

## Privacidad (RNF01, Habeas Data)

1. **Lista de apps permitidas.** Solo se procesan notificaciones de bancos,
   billeteras y la app de SMS. Las de cualquier otra app (correo, chats, redes
   sociales) se ignoran: el servicio ni siquiera lee su texto.
2. **Solo lo que parece un cobro.** Lo que no tiene un monto y una palabra de
   cobro se descarta en el acto, sin guardarse. Este filtro se aplica a **todas**
   las apps permitidas, no solo al SMS: los bancos también envían códigos y
   publicidad. Los textos con "código", "clave", "OTP" o "contraseña" se
   descartan siempre, aunque tengan monto, para no guardar nunca un código de
   verificación.
3. **Almacenamiento local y temporal.** La cola está en el almacenamiento
   interno de la app, máximo 200 entradas y 30 días. Se borra al desinstalar.
4. **El texto crudo nunca sale del celular.** Al backend (hito 3) solo se
   envían los campos extraídos por el parser.
5. **Modo descubrimiento, solo para desarrollo.** Para encontrar los paquetes
   hace falta ver qué apps publican notificaciones. En compilaciones debug, la
   pantalla de depuración puede activar un modo que muestra el **paquete y el
   título** de cualquier notificación, **nunca su texto**. Vive solo en memoria,
   no se guarda y se apaga al salir de la pantalla. En release no existe.
6. **Permiso explícito.** Nada funciona hasta que el usuario activa SubTrack en
   "Acceso a notificaciones", y puede quitarlo en cualquier momento.

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
| Pago simulado con la app **cerrada** (deslízala fuera de recientes) | Al abrirla y entrar a la pantalla, está en "Cola guardada" |
| "Recibiste…" o código de verificación | No queda en la cola. Con modo descubrimiento: **DESCARTADA** con el motivo |
| Mismo texto enviado dos veces con otra etiqueta | Queda una sola vez en la cola |
| Notificación de WhatsApp o Gmail con modo descubrimiento | **APP NO PERMITIDA**: paquete y título, sin texto |
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
