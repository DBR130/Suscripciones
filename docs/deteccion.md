# Detección automática de suscripciones

Lectura de notificaciones de pago en Android (RF02, RF03, flujo B de la
especificación). Este documento describe la arquitectura, las decisiones de
privacidad y cómo probar cada parte. Se actualiza al terminar cada hito.

| Hito | Contenido | Estado |
|---|---|---|
| 1 | Lector nativo, cola local, canales con Flutter y pantalla de depuración | **Hecho** |
| 2 | Parser en Dart: comercio, monto, moneda, fecha y banco | **Hecho** |
| 3 | Backend: pagos detectados y candidatos de suscripción | **Hecho** |
| 4 | Pantallas 03, 04, 05 y flujo B | **Hecho** |
| 5 | Historial de SMS (opcional, READ_SMS), "Compartir" y análisis en el celular | **Hecho** |
| 6 | Procesadores de pago, servicios ambiguos, deshacer descartes y aviso de pago registrado | **Hecho** |

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
| `LectorNotificacionesService.kt` | Servicio que Android ejecuta aunque la app esté cerrada. Recibe cada notificación (`onNotificationPosted`), aplica los filtros y guarda las que parecen cobros. Toma el texto largo (`EXTRA_BIG_TEXT`), el último mensaje si la app usa MessagingStyle (Google Mensajes) o el texto corto. Ignora resúmenes de grupo, notificaciones fijas y llamadas (categorías `call` y `missed_call`). Al conectarse revisa las notificaciones activas de la barra (`getActiveNotifications`) y al desconectarse pide reconexión (`requestRebind`). |
| `RegistroDeteccion.kt` | Horas de la última conexión, desconexión y notificación (SharedPreferences) y el único punto de logs (tag `SubTrackDeteccion`, solo en debug). |
| `ReconexionReceiver.kt` | Al reiniciar el celular o actualizar/reinstalar la app (`MY_PACKAGE_REPLACED`), intenta reconectar el lector. |
| `ReconexionLector.kt` | Reconexión escalonada: `requestRebind` y, si no basta, reiniciar el componente del servicio (ver "Lector desconectado tras reinstalar o actualizar"). |
| `FiltroCobros.kt` | Decide si un texto "parece un cobro": debe tener un monto **y** una palabra de cobro, y no tener palabras excluidas. Compara sin tildes ni mayúsculas. Los números de teléfono no cuentan como monto. |
| `AppSmsPredeterminada.kt` | La app de SMS predeterminada del usuario (`Telephony.Sms.getDefaultSmsPackage`), que se permite aunque no esté en la lista fija. Se consulta al abrir la app y al conectarse el lector. |
| `ColaNotificaciones.kt` | Cola en `filesDir/deteccion/cola.json` (almacenamiento interno: solo esta app puede leerlo). Máximo 200 entradas, se borran solas a los 30 días, no guarda dos veces el mismo texto de la misma app y escribe de forma atómica. |
| `ConfiguracionDeteccion.kt` | Lee la configuración de `res/raw/deteccion_apps.json` y decide si una app está permitida (lista fija o app de SMS predeterminada). |
| `CanalDeteccion.kt` | MethodChannel y EventChannel con Flutter; abre los ajustes de "Acceso a notificaciones" y detecta si el permiso está concedido. |

El servicio está declarado en `AndroidManifest.xml` con el permiso
`BIND_NOTIFICATION_LISTENER_SERVICE`: solo el sistema puede conectarse a él, y
solo después de que el usuario lo autoriza en Ajustes.

**Canal de métodos** `subtrack/deteccion`:

| Método | Devuelve |
|---|---|
| `estado` | `{permiso, conectado, es_debug, modo_descubrimiento, app_sms_paquete, app_sms_nombre, ultima_conexion, ultima_desconexion, ultima_notificacion, ultimo_resultado, ultima_reconexion, resultado_reconexion}` (horas en milisegundos). También vuelve a consultar la app de SMS predeterminada |
| `abrirAjustesAcceso` | Abre el ajuste de SubTrack en "Acceso a notificaciones" (Android 11+) o la lista general |
| `reconectar` `{motivo}` | Si hay permiso pero el servicio está desconectado, inicia la reconexión escalonada (`ReconexionLector`). Responde enseguida; el resultado se ve en `estado` |
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
  "apps_permitidas": [
    { "paquete": "com.google.android.apps.messaging", "nombre": "Mensajes de Google (SMS)" },
    { "paquete": "com.truecaller", "nombre": "Truecaller (SMS)" },
    { "paquete": "com.samsung.android.messaging", "nombre": "Mensajes de Samsung (SMS)" },
    { "paquete": "com.android.mms", "nombre": "Mensajes de Xiaomi/MIUI (SMS)" }
  ],
  "apps_solo_debug": [ { "paquete": "com.android.shell", "nombre": "Shell (simulación con adb)" } ],
  "palabras_cobro": ["compra", "compraste", "pago", "pagaste", "debito", "transaccion"],
  "palabras_excluidas": ["codigo", "clave", "otp", "contrasena", "llamada", "llamadas", "llamando", "spam", "estafa", "call", "calling", "missed"]
}
```

- Además de `apps_permitidas`, el lector permite **siempre la app de SMS
  predeterminada** del usuario, sea cual sea (ver "Cualquier app de SMS").
- `apps_permitidas` es el respaldo, con paquetes verificados: Mensajes de
  Google (con el modo descubrimiento en el Xiaomi de pruebas), Truecaller,
  Mensajes de Samsung y Mensajes de Xiaomi/MIUI (en Google Play y en
  sysapps.bayton.org). Los bancos se agregan cuando se identifiquen. Después
  de editarlo hay que recompilar la app.
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
| `huella_pago.dart` | Huella del cobro y lo que se envía al backend (solo campos extraídos). |
| `procesador_detecciones.dart` | Une todo: cola + notificaciones activas → parser → backend → borra lo procesado. |
| `deteccion_service.dart` / `candidato_suscripcion.dart` | Llamadas a `/api/detecciones` y modelo del candidato. |
| `permisos_page.dart`, `escaneo_page.dart`, `resultados_deteccion_page.dart` | Pantallas 03, 04 y 05. |

Al abrir la app y cada vez que vuelve a primer plano, `main.dart` pide
reconectar el servicio si está detenido y recupera las notificaciones activas
de la barra. Si además hay sesión y permiso, procesa la cola y avisa de los
candidatos nuevos (flujo B, ver hito 4).

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
| `Servicio desconectado: se intenta reconectar` | Android o MIUI detuvo el lector |
| `Reconexión (motivo): requestRebind enviado` | Primer intento de reconexión |
| `Reconexión (motivo): funcionó con requestRebind` | Bastó con el primer intento |
| `Reconexión (motivo): componente del lector reiniciado (deshabilitar y habilitar)` | Segundo intento, a los 2,5 s |
| `Reconexión (motivo): conectado tras reiniciar el componente` | El segundo intento funcionó |
| `Reconexión (motivo): sigue desconectado: hay que apagar y encender el acceso a mano` | Ningún intento funcionó: la app muestra "Detección pausada" |

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

## Lector desconectado tras reinstalar o actualizar (HyperOS)

**Síntoma (Xiaomi, HyperOS, Android 16).** Después de reinstalar la app (APK
release y luego la debug encima), el permiso seguía concedido pero un SMS real
no se detectaba. Perfil decía "Activo" aunque la detección no funcionaba.

**Cómo se detectó (logs).** Con `adb logcat -v time -s SubTrackDeteccion:V`
se repetía `App abierta con el servicio desconectado: se pide reconexión` y
nunca aparecía `Servicio conectado`. Al apagar y encender el acceso de
SubTrack en los ajustes, el lector se conectó y detectó el SMS real ("Bancolombia:
Compraste $19.900,00 en GOOGLE *Crunchyroll…") y lo propuso como suscripción
mensual de $19.900. El lector y el parser funcionaban; fallaba la reconexión.

**Causa.** Al reinstalar o actualizar una app, Android desenlaza su
NotificationListenerService y debería volver a enlazarlo solo. HyperOS no
siempre lo hace, y `requestRebind()` tampoco lo consigue. Le pasaría a un
usuario real después de cada actualización.

**Solución:**

1. **Reconexión escalonada** (`ReconexionLector.kt`), al abrir la app, al
   volver a primer plano, al recibir `MY_PACKAGE_REPLACED` o
   `BOOT_COMPLETED` y al desconectarse el servicio:
   1. `requestRebind()`.
   2. Si a los 2,5 s sigue desconectado: **reiniciar el componente** del
      servicio con `PackageManager.setComponentEnabledSetting` (deshabilitar
      y volver a habilitar, con `DONT_KILL_APP` porque el servicio vive en el
      proceso de la app). Android lo trata como un cambio del paquete y vuelve
      a enlazar el lector, igual que al apagar y encender el acceso. Después,
      otro `requestRebind()`.
   3. A los 3 s se anota el resultado en los logs y en la pantalla de
      depuración ("Reconexión forzada").

   No se reinicia el componente más de una vez cada 15 s. En el receiver se
   usa `goAsync()` para que Android no mate el proceso a mitad de la secuencia.
2. **Estado real en la app** (`VigilanteDeteccion`): "permiso concedido" ya no
   es lo mismo que "detección activa".

   | Permiso | Lector | Estado | Perfil | Dashboard |
   |---|---|---|---|---|
   | No | — | Sin permiso | "Desactivado · solo registro manual" | — |
   | Sí | Conectado | Activa | "Activo · detección automática encendida" | — |
   | Sí | Desconectado, reconectando (hasta 9 s) | Comprobando | "Comprobando la detección…" | — |
   | Sí | Sigue desconectado tras los intentos | **Pausada** | "Detección pausada · toca para reactivarla" | Aviso "La detección está pausada…" con el botón **Abrir el ajuste** |

   - El botón del aviso (y tocar el interruptor en Perfil) abre directamente
     el ajuste de SubTrack en "Acceso a notificaciones", para apagarlo y
     encenderlo.
   - La **pantalla 03**, si el permiso ya está dado, primero intenta reconectar
     ("Comprobando el lector…"). Si conecta, sigue al escaneo; si no, muestra
     el mismo aviso.
   - Aun con la detección pausada, la cola guardada antes se sigue enviando al
     backend.

**Riesgo conocido.** Reiniciar el componente es una técnica usada en la
práctica, pero no está documentada por Android como garantía. Si en algún
celular Android quitara el acceso al reiniciarlo, el log lo dice ("Android
quitó el acceso al reiniciar el componente") y la app muestra "Sin permiso",
que lleva a la pantalla 03.

### Cómo probarlo en el Xiaomi

1. Instala la app debug, inicia sesión y da el acceso a notificaciones.
   Perfil debe decir "Activo · detección automática encendida".
2. En una terminal, deja corriendo los logs:

   ```powershell
   adb logcat -c
   adb logcat -v time -s SubTrackDeteccion:V
   ```

3. Reproduce el problema **reinstalando encima** (en otra terminal, desde la
   carpeta del proyecto):

   ```powershell
   flutter build apk --debug
   adb install -r build\app\outputs\flutter-apk\app-completa-debug.apk
   ```

   En los logs debe aparecer `Evento del sistema (app actualizada): se intenta
   reconectar el lector` y, después, `Servicio conectado` (solo, con
   `requestRebind` o con el reinicio del componente).
4. Abre la app. Resultado esperado, en este orden de preferencia:
   - Se reconectó sola: Perfil dice "Activo" y en los logs aparece
     `Servicio conectado`. En **Perfil → Depuración: detección**, la fila
     "Reconexión forzada" muestra qué paso funcionó.
   - No se reconectó: a los pocos segundos Perfil dice "Detección pausada ·
     toca para reactivarla" y el dashboard muestra el aviso. **Abrir el
     ajuste** → apaga y enciende SubTrack → al volver, el aviso desaparece y
     Perfil dice "Activo".
5. Comprueba que detecta: simula un pago (por ejemplo `real1` de "Cómo
   probar (hito 4)") o pide que te envíen un SMS de cobro.

## Cualquier app de SMS (app predeterminada)

**Razón.** Con probadores nuevos, a Santiago (Xiaomi) no le funcionó la
detección: su app de SMS predeterminada es **Truecaller**, y la lista fija
solo permitía Mensajes de Google. Cristian (Samsung) puede usar **Mensajes de
Samsung**. Agregar apps de SMS una por una no escala: cada probador puede tener
otra.

**Cambio.**

1. El lector permite, además de la lista fija, la **app de SMS predeterminada**
   del usuario (`Telephony.Sms.getDefaultSmsPackage`, en
   `AppSmsPredeterminada.kt`). Se le aplica el mismo filtro de cobro que a
   cualquier app permitida: un SMS personal se descarta sin guardarse.
2. Se vuelve a consultar al abrir la app o volver a ella (método `estado`) y
   cuando el lector se conecta, por si el usuario cambió de app de SMS. El log
   avisa cuando cambia: `App de SMS predeterminada (motivo): paquete`.
3. La lista fija queda como respaldo (por ejemplo, si el usuario recibe los SMS
   en una app que no es la predeterminada) y ahora incluye Truecaller
   (`com.truecaller`), Mensajes de Samsung (`com.samsung.android.messaging`) y
   Mensajes de Xiaomi/MIUI (`com.android.mms`). Los tres paquetes se
   verificaron antes de agregarlos: Truecaller en Google Play (informe de
   Exodus Privacy), y Mensajes de Samsung y de Xiaomi en sysapps.bayton.org
   (base de datos de apps preinstaladas por fabricante).
4. La pantalla de depuración muestra la fila **App de SMS predeterminada** con
   el nombre y el paquete detectados.
5. Para ver el nombre de la app (por ejemplo "Truecaller"), el manifiesto
   declara en `<queries>` las apps que responden a "enviar a `smsto:`" (todas
   las apps de SMS). No se pide `QUERY_ALL_PACKAGES`.

**Truecaller no solo muestra SMS.** También publica el identificador de
llamadas, llamadas perdidas, llamadas bloqueadas y alertas de spam, casi
siempre con un número de teléfono que parece un monto ("3001234567"). Para
que no pasen como cobro hay tres defensas:

| Defensa | Dónde | Ejemplo descartado |
|---|---|---|
| Notificaciones de categoría llamada (`call`, `missed_call`) se ignoran sin leer su texto | `LectorNotificacionesService.kt` | El identificador de llamadas mientras suena el teléfono |
| Palabras excluidas nuevas: llamada(s), llamando, spam, estafa, call, calling, missed | `deteccion_apps.json` | "Llamada perdida: Pagos y Cobros SAS 3001234567" |
| Los teléfonos (+57…, celulares de 10 dígitos que empiezan por 3, fijos 60…, líneas 01 8000) no cuentan como monto | `FiltroCobros.kt` | "Pago Facil Colombia · 3001234567" |

Y aunque algo pasara el filtro, el parser (hito 2) solo acepta
"compraste/pagaste MONTO en COMERCIO" de un banco conocido.

**Tests (sin celular).**

- `test/fixtures/avisos_no_sms.json`: 10 avisos tipo Truecaller (llamadas,
  spam, identificador). Los usan las dos capas:
  - `android/app/src/test/.../FiltroCobrosTest.kt` (JUnit, con las palabras
    reales de `deteccion_apps.json`): ningún aviso pasa el filtro nativo, los
    3 SMS reales sí, y un teléfono no cuenta como monto.
  - `test/deteccion_parser_test.dart`: el parser tampoco los acepta.
- `test/deteccion_lector_test.dart`: la pantalla de depuración muestra la app
  de SMS predeterminada.

Correr los tests nativos (PowerShell, desde la carpeta del proyecto; Gradle
necesita el Java que trae Android Studio):

```powershell
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
cd android
.\gradlew.bat :app:testCompletaDebugUnitTest
cd ..
```

El informe queda en `build/app/reports/tests/testCompletaDebugUnitTest/index.html`.

**Guía para probadores** (instalar, permisos, batería, SMS de prueba):
[probar-la-app.md](probar-la-app.md).

### Cómo probarlo

1. En el celular del probador, abre **Perfil → Depuración: detección** (solo
   en la app debug): la fila "App de SMS predeterminada" debe mostrar su app
   (por ejemplo "Truecaller (com.truecaller)").
2. Pide que le envíen un SMS de cobro (ver la guía). En logcat:
   `Recibida de com.truecaller: guardada`.
3. Pide que lo llamen y no contesten: la llamada perdida de Truecaller debe
   salir como `ignorada (llamada)` o `descartada (palabra excluida…)`, nunca
   `guardada`.
4. Cambia la app de SMS predeterminada (Ajustes → Apps → Apps predeterminadas
   → App de SMS), vuelve a SubTrack: en logcat aparece `App de SMS
   predeterminada (app abierta): …` con la nueva y la fila de depuración se
   actualiza.

## Tres caminos: notificaciones, historial de SMS y "Compartir" (hito 5)

**Problema.** El escaneo inicial (pantalla 04) solo veía las notificaciones
que seguían en la barra, así que casi siempre decía "Encontramos 0
suscripciones" (un probador con Samsung). Y el lector de notificaciones no
puede leer SMS antiguos: no encontraba suscripciones pagadas antes de
instalar la app (un probador con DiDi).

**Decisión.** Tres caminos, cada uno con su propio consentimiento:

| Camino | Qué lee | Permiso | Cuándo |
|---|---|---|---|
| **1. Lector de notificaciones** (el de siempre) | Las notificaciones nuevas de la app de SMS predeterminada y de la lista fija; solo guarda las que parecen cobros | "Acceso a notificaciones" (pantalla 03) | Siempre, en segundo plano |
| **2. Historial de SMS** (opcional) | Los SMS **recibidos** de los últimos **6 meses**, desde el proveedor de SMS de Android (funciona con cualquier app de SMS, también Truecaller). Los que no parecen cobros se descartan en la parte nativa | **READ_SMS**, pedido solo si el usuario toca "Buscar en mis SMS" después de una divulgación destacada | Una vez, cuando el usuario lo pide (al final del onboarding o desde Perfil). Se puede repetir sin duplicar |
| **3. Compartir** | Solo el texto que el usuario comparte a propósito desde su app de mensajes | Ninguno (intent `ACTION_SEND`, `text/plain`) | Cuando el usuario quiera |

No se usa **RECEIVE_SMS**: los cobros nuevos ya llegan por el camino 1.

### Consentimientos

1. **Pantalla 03** (como antes): acceso a notificaciones para los cobros
   nuevos.
2. **"¿Buscamos suscripciones que ya pagas?"** (`historial_sms_page.dart`):
   pantalla aparte y opcional, después de la 03 y en Perfil ("Buscar
   suscripciones en mis SMS"). Es la divulgación destacada (*prominent
   disclosure*) que pide Google Play antes del permiso: explica qué se lee
   (solo los SMS que parecen cobros de bancos), para qué (encontrar
   suscripciones), qué sale del celular (solo monto, comercio y fecha de las
   suscripciones encontradas), que es una sola revisión de 6 meses y cómo
   revocarlo en los ajustes de Android. Botones **Buscar en mis SMS** y
   **Ahora no**.
   - Solo "Buscar en mis SMS" muestra el diálogo de Android (READ_SMS).
   - Si lo rechaza: "Sin problema: seguimos detectando los cobros nuevos" y
     sigue el escaneo de notificaciones. La app funciona igual.
   - Si Android ya no pregunta (rechazos anteriores), la pantalla explica
     cómo darlo en los ajustes y abre los permisos de SubTrack; al volver con
     el permiso, busca.

### El escaneo del historial

`LectorHistorialSms.kt` (versión completa) consulta
`Telephony.Sms.Inbox` con `date >= hace 6 meses`, en un hilo aparte. Por cada
SMS aplica **el mismo filtro de cobro** (`FiltroCobros`); a Flutter solo pasan
el texto y la fecha de los que parecen cobros. En Flutter pasan por **el mismo
parser**; si el texto no trae fecha (Nequi), se usa la fecha del propio SMS.
Progreso en la pantalla 04 ("Revisando tus mensajes del banco…": leyendo,
analizando, guardando) y resultados en la 05.

**Xiaomi y los SMS de servicio.** Hay reportes de que MIUI/HyperOS oculta a
las apps los SMS de números cortos (los de los bancos) detrás de un permiso
propio de Xiaomi, aunque READ_SMS esté concedido. No hay documentación
oficial y no se pudo confirmar sin el celular, así que se detecta en la
práctica: la lectura cuenta cuántos SMS vienen de remitentes de empresa
(números cortos o nombres). Si se leyeron SMS pero **ninguno** de empresa y no
salió ningún cobro, la pantalla 04 muestra "No vimos SMS de bancos", con un
botón que abre el editor de permisos de MIUI
(`miui.intent.action.APP_PERM_EDITOR`; si no existe, la información de la
app) y "Buscar de nuevo". El log dice `Historial de SMS: N leídos (M de
empresas), K parecen cobro` (solo cantidades).

### Análisis en el celular (minimización)

El análisis se hace **en el celular** (`analizador_pagos.dart`), con la misma
regla que el backend. Agrupa por comercio normalizado y moneda, y solo deja
salir:

- los pagos a **servicios conocidos** del catálogo de guías, y
- los de comercios con **patrón recurrente**: 2 o más cobros con montos
  similares (±10 %) y periodicidad semanal (6–8 días), mensual (26–35) o
  anual (355–375).

Las **compras puntuales** y los SMS que no son cobros **no salen del
celular**. Se envían en lotes de máximo 100.

Esto aplica a los dos caminos automáticos (notificaciones e historial): los
dos pasan por el mismo `ProcesadorDetecciones` → parser → almacén local →
análisis → envío.

### Decisión: las compras normales se quedan en el celular

**Antes**, el flujo en vivo enviaba al backend todo cobro interpretado, y el
backend guardaba para siempre las compras normales (por ejemplo, DiDi Food)
porque las necesitaba para notar un patrón recurrente más adelante.

**Ahora** (dos capas):

1. **En el celular**: `AlmacenPagosLocales` guarda los pagos interpretados
   (solo campos extraídos, nunca el texto), cifrados en el almacenamiento
   seguro de Android, durante **400 días** (lo justo para ver dos cobros de
   una suscripción anual), con un tope de 1000, y se borran al cerrar sesión.
   Así el patrón recurrente se detecta en el celular: cuando llega el segundo
   cobro mensual de un comercio, salen los dos. Una compra que nunca se
   repite no sale nunca.
2. **En el backend** (red de seguridad, migración 007):
   `purgarComprasNormales` borra los pagos que no están enlazados a una
   suscripción ni corresponden a un candidato pendiente o confirmado (con los
   alias del catálogo). Corre al final de cada lote, al descartar un candidato
   (sus pagos ya no hacen falta) y en una tarea diaria (00:20). La migración
   007 borra las compras normales que ya estaban guardadas.

**Por qué así y no solo una retención en el backend:** con solo una
retención, las compras puntuales igual viajarían y se guardarían unos meses
en el servidor sin ninguna necesidad. Dejarlas en el celular cumple mejor la
minimización (Ley 1581, finalidad) y lo que exige Google Play para READ_SMS:
no sacar del celular SMS personales ni datos que no sirven para la función.

### Sin duplicados entre caminos

El mismo cobro puede llegar por la notificación, por el historial o por
"Compartir":

- **Con fecha en el texto** (Bancolombia): la huella usa la fecha del mensaje,
  así que coincide por cualquier camino.
- **Sin fecha en el texto** (Nequi): la notificación usa `postTime` y el
  historial la fecha del SMS; difieren unos segundos y la huella cambia. Se
  unifica con una **tolerancia de 5 minutos** para el mismo banco, comercio,
  monto y moneda:
  - en el celular, `AnalizadorPagos.mismoCobro` (no se guarda dos veces ni se
    envía dos veces);
  - en el backend, el pago llega con `fecha_del_mensaje: false` (columna
    `fecha_aproximada`) y se responde `repetido` si ya hay uno igual a ±5
    minutos.
- Repetir "Buscar suscripciones en mis SMS" no reenvía lo ya enviado.

### Compartir un SMS con SubTrack

`MainActivity` declara un intent-filter `ACTION_SEND` / `text/plain` (en las
dos versiones). `CanalCompartir.kt` entrega el texto a Flutter
(`receptor_compartir.dart`), que abre `compartir_page.dart`:

- Si el parser reconoce un cobro, muestra comercio, monto, banco y fecha
  (si el texto no trae fecha, se puede elegir el día). **Usar este cobro**
  envía solo los campos extraídos con `compartido: true`:
  - si ya es una suscripción del usuario, se registra el pago en ella y se
    abre su detalle;
  - si no, el backend lo propone como candidato (aunque sea un comercio
    desconocido con un solo cobro: el usuario dice que es una suscripción) y
    se abre la pantalla 05 para confirmarlo.
- Si no es un cobro, explica por qué y ofrece agregarla a mano. No se envía
  nada.
- El texto vive solo en memoria; no se guarda en la cola.

### Versiones completa y sinSms

Todo lo de READ_SMS se puede incluir o excluir al compilar con *product
flavors* (`android/app/build.gradle.kts`):

| | completa | sinSms |
|---|---|---|
| Lector de notificaciones, registro manual, "Compartir" | Sí | Sí |
| "Buscar suscripciones en mis SMS" | Sí | No (Flutter oculta la opción) |
| `READ_SMS` en el manifest | Sí (`src/completa/AndroidManifest.xml`) | **No** |
| `LectorHistorialSms.kt` | Lee el proveedor de SMS (`src/completa`) | Vacío (`src/sinSms`) |

Las dos usan el mismo `applicationId` (se instala una u otra). Flutter
pregunta por el canal `subtrack/historial_sms` si la opción existe, así que el
código Dart es el mismo en las dos. `pubspec.yaml` tiene
`default-flavor: completa`: `flutter run` y `flutter build` sin `--flavor`
compilan la completa.

```powershell
# Debug en el celular (completa)
flutter run
# Debug sin el módulo de SMS
flutter run --flavor sinSms

# APK release (cambia la URL por la de Render)
flutter build apk --release --flavor completa --dart-define=API_URL=https://TU-SERVICIO.onrender.com
flutter build apk --release --flavor sinSms --dart-define=API_URL=https://TU-SERVICIO.onrender.com
```

Los APK quedan en `build\app\outputs\flutter-apk\`: `app-completa-release.apk`
y `app-sinsms-release.apk` (en debug, `app-completa-debug.apk` y
`app-sinsms-debug.apk`). Para comprobar que la sinSms no pide SMS:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\build-tools\<versión>\aapt.exe" dump permissions build\app\outputs\flutter-apk\app-sinsms-release.apk
```

(no debe aparecer `android.permission.READ_SMS`). Para Google Play, ver
[google-play.md](google-play.md).

### Archivos

| Archivo | Qué hace |
|---|---|
| `src/completa/AndroidManifest.xml` | Declara READ_SMS (solo en la completa) |
| `src/completa/.../LectorHistorialSms.kt` | Lee los SMS recibidos de 6 meses y aplica el filtro de cobro |
| `src/sinSms/.../LectorHistorialSms.kt` | Versión vacía: no lee nada |
| `deteccion/CanalHistorialSms.kt` | Canal `subtrack/historial_sms`: disponible, permiso, leer (en otro hilo), abrir permisos (MIUI) |
| `deteccion/CanalCompartir.kt` | Canal `subtrack/compartir`: texto compartido al abrir o con la app abierta |
| `lib/deteccion/historial_sms.dart` | Puente Dart del historial |
| `lib/deteccion/historial_sms_page.dart` | Divulgación destacada y pedido del permiso |
| `lib/deteccion/analizador_pagos.dart` | Qué sale del celular y `mismoCobro` (tolerancia de 5 min) |
| `lib/deteccion/almacen_pagos_locales.dart` | Pagos interpretados en el celular (400 días, cifrados) |
| `lib/deteccion/compartir_page.dart`, `receptor_compartir.dart` | "Compartir" |
| `backend/db/migraciones/007_retencion_detecciones.sql` | `fecha_aproximada` y limpieza de compras normales |

### Tests

- `test/deteccion_historial_test.dart` (29): reglas del análisis (servicio
  conocido, compra puntual, ±10 %, semanal, mensual, anual, irregular),
  `mismoCobro` de Nequi por notificación e historial, almacén local
  (retención, cierre de sesión), búsqueda en el historial (qué se envía, sin
  texto, repetir sin duplicar, no repetir lo que llegó por notificación,
  sospecha de Xiaomi), divulgación (Ahora no, permiso concedido, rechazado,
  bloqueado), pantalla 03 y Perfil en las dos versiones, pantalla 04 con
  historial y "Compartir".
- `backend/test/detecciones.test.js`: tolerancia de 5 minutos, cobro
  compartido, validación de los campos nuevos y retención (compras puntuales,
  alias del catálogo, descartar, tarea diaria).

### Cómo probarlo en el Xiaomi

Ver el resumen al final de "Cómo probar (hito 5)".

## Procesadores, servicios ambiguos y descartes (hito 6)

Tickets en [docs/tickets/](tickets/README.md), implementados con TDD.

### Hallazgos de los probadores

- **EBANX.** La búsqueda en el historial le propuso a Santiago una suscripción
  llamada "Servicios Web Ebanx Co". EBANX es un **procesador de pagos**: cobra
  en nombre de servicios internacionales (era Crunchyroll, $19.900, según su
  correo). La detección del patrón funcionó; el problema era el nombre.
- **SMS reales de Nequi** (septiembre de 2026), ahora fixtures en
  `test/fixtures/sms_reales_nequi_2026_09.json`:
  - "NEQUI: Pagaste 19.900,00 en SERVICIOS WEB EBANX CO": procesador EBANX.
  - "NEQUI: Pagaste 39.381,00 en STEAMGAMES.COM 4259522985": el número es un
    teléfono pegado al comercio, no un monto ni parte del nombre.
  - "NEQUI: Pagaste 64.925,65 en ANTHROPIC* CLAUDE SUB" y el de octubre
    (68.139,27): dos cobros mensuales de Claude con 4,95 % de diferencia solo
    por la tasa del dólar.
  - "NEQUI: Pagaste 18.900,00 en DLO*DiDi Food CO Payin" (y otro de 16.140 dos
    minutos después): `DLO*` es el prefijo de **dLocal**; el comercio real es
    DiDi Food. Compras normales.
  - En Truecaller el remitente aparece como "Robocall · Potential fraud", pero
    los SMS llegan: el filtro no usa el título.
- **`GOOGLE *YouTubePremium`** no se reconocía: las palabras pegadas no
  coincidían con "YouTube Premium" del catálogo.
- **Falsos positivos posibles:** un pedido de Rappi se reconocía como "Rappi
  Pro" y un juego de PlayStation como "PlayStation Plus", desde el primer pago.

### Limpieza del comercio (parser)

- **Palabras pegadas:** se compara de dos formas, tal cual ("YOUTUBE
  PREMIUM") y separando las palabras pegadas por mayúsculas en los dos lados
  ("YouTubePremium" ↔ "YouTube Premium"). Igual en Dart
  (`CatalogoServicios.buscar`) y en JS (`buscarGuia`).
- **Teléfono al final:** un número de 7 o más dígitos al final del comercio se
  quita.
- **dLocal:** `DLO*` es prefijo de pasarela (como `GOOGLE *` o `PAYPAL *`) y se
  quitan "CO Payin" al final.
- Las palabras con mayúsculas y minúsculas mezcladas se conservan ("DiDi").
- **Señal de suscripción**, como palabra completa: SUB, SUBS, SUBSCRIPTION,
  SUSCRIPCION (se quitan del nombre) y MEMBRESIA, PRIME, PRO, PLUS, PREMIUM
  (no se quitan: son parte de nombres como "YouTube Premium"). "PRO" no
  coincide con "PRODUCTOS". La lista está en `parser_pagos.dart` y en
  `services/detecciones.js`.

### Servicios ambiguos

Algunos comercios venden cosas sueltas además de la suscripción. En
`backend/db/guias.json` tienen `"es_ambigua": true`: Rappi Pro, Apple,
PlayStation Plus, Xbox Game Pass, YouTube Premium, Google One, Adobe, Prime
Video y Microsoft 365 (migración 008).

- Un servicio ambiguo **solo se propone con patrón** (2 o más cobros con
  montos ±10 % y periodicidad semanal, mensual o anual), salvo que el comercio
  traiga **señal de suscripción** ("RAPPI PRO", "YouTubePremium"): entonces
  desde el primer pago.
- La regla está en los dos lados: en el celular, un cobro suelto de un
  servicio ambiguo sin señal no sale (queda como compra puntual local); en el
  backend no se propone.

### Procesadores de pago

`backend/db/procesadores.json` (EBANX, PayU, dLocal —con alias "dlo"—,
Mercado Pago, PayPal, Stripe, 2Checkout/Verifone, Paddle, FastSpring, ePayco,
Wompi, PlacetoPay/Evertec, Kushki y Bold). El backend lo lee al arrancar y lo
entrega en `GET /api/guias` como `procesadores`: una sola lista para los dos
lados.

- Un comercio es de un procesador si contiene un alias como palabra completa
  **y no es un servicio del catálogo** ("PAYPAL *NETFLIX" sigue siendo
  Netflix; con `DLO*` el SMS trae el comercio real).
- Se propone **solo con patrón**, como un comercio desconocido.
- Los cobros del mismo procesador se **separan por monto** (±10 %): cada
  grupo es un candidato distinto, con `comercio_normalizado` = `procesador` =
  "EBANX" (migración 009: columna `procesador` e índice único parcial
  `WHERE procesador IS NULL`).
- En la pantalla 05 se ve **"Pago procesado por EBANX"** con **"¿Qué servicio
  es?"**. Antes de confirmarlo, el usuario escribe el nombre real (con
  sugerencias del catálogo). El lápiz permite editar nombre, monto y
  frecuencia de **cualquier** candidato.
- **Sugerencia por monto:** si el monto está a ±5 % del precio de referencia
  de un servicio (`precio_referencia_cop`, migración 008), aparece el chip
  "¿Es Crunchyroll?". Nunca se elige solo. Por ahora solo Crunchyroll tiene
  precio (19.900 COP, de un SMS y un correo reales); los demás quedan vacíos
  hasta conocerlos con seguridad.
- Al confirmar, la suscripción queda con el nombre elegido y se le enlazan
  solo los pagos del procesador con monto similar. Los **cobros siguientes**
  del mismo procesador con monto ±10 % se registran en esa suscripción.
- **Limitación:** si el servicio sube más del 10 %, el cobro cae fuera del
  grupo y aparece como un candidato nuevo "Pago procesado por EBANX", en vez
  de registrarse como cambio de precio.

### Descartes: deshacer, lista y reapertura

- En la pantalla 05, **"No es mía" descarta al instante**; una barra de 5 s
  ofrece **"Deshacer"** (restaura). El botón de confirmar está en la barra
  inferior del Scaffold, así la barra de Deshacer flota encima sin taparlo.
- **Perfil → "Detecciones descartadas"**: la lista con "Volver a proponer".
- **Reapertura (migración 010):** si un comercio descartado acumula **3 o más
  cobros periódicos con montos similares**, el candidato vuelve a pendiente
  **una sola vez** (`reabierto`), con el motivo ("Vimos 3 cobros mensuales de
  $99.900") en la tarjeta y en el aviso del flujo B. Si se descarta otra vez,
  no se reabre solo.
- Para poder contarlos, los pagos de un comercio descartado se conservan
  **hasta 400 días** (ver Privacidad).

### Aviso de pago registrado y cobros convertidos

- En el **flujo en vivo** (al abrir o volver a la app), cuando un pago se
  registra en una suscripción existente: "Registramos un pago de $44.900 en
  Netflix"; si cambió el precio, "Netflix subió de $44.900 a $49.900" (o
  "bajó"). Con 3 o más en la misma revisión, un solo aviso de resumen. Nada si
  fue repetido, compra normal o comercio descartado. No se avisa en la
  búsqueda del historial (serían meses de pagos viejos) ni en "Compartir".
- **Cobros convertidos de USD** (montos en COP con centavos distintos de ,00):
  la tolerancia de cambio de precio sube del 5 % al **15 %**, para que la tasa
  del dólar no produzca avisos falsos (Claude varió 4,95 %).
- El aviso del flujo B de un procesador se titula "Pago procesado por EBANX".

### Migraciones

| Migración | Qué agrega |
|---|---|
| 008 | `guias_cancelacion.es_ambigua` y `precio_referencia_cop` (después, `npm run db:guias`) |
| 009 | `candidatos_suscripcion.procesador` e índice único parcial |
| 010 | `candidatos_suscripcion.reabierto` y `motivo` |

Aplicarlas en local y en Neon **antes** de subir a `develop`, y volver a
cargar el catálogo:

```powershell
cd backend
npm run db:migrate; npm run db:guias
npm run db:migrate:nube; npm run db:guias:nube
```

### Tests

- Flutter: `deteccion_parser_test` (palabras pegadas, Steam, dLocal,
  procesadores, fixtures reales), `deteccion_historial_test` (ambiguos,
  procesadores y almacén), `deteccion_resultados_test` (pantalla 05,
  descartadas, sugerencia, reapertura), `deteccion_avisos_pago_test` (aviso
  de pago registrado).
- Backend: `detecciones.test.js` (ambiguos, procesadores, enlace posterior,
  restaurar con 404/409, reapertura, retención de 400 días, cobros
  convertidos) y `guias.test.js` (`es_ambigua`, `precio_referencia_cop`,
  procesadores).
- Nativo: `FiltroCobrosTest` también revisa los SMS reales de Nequi.

### Cómo probarlo en el Xiaomi

Ver "Cómo probar (hito 6)".

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
| `POST /api/detecciones/candidatos/:id/descartar` | El comercio no se vuelve a proponer (salvo reapertura, hito 6). `{candidato}` |
| `GET /api/detecciones/descartadas` | Candidatos descartados del usuario (hito 6). `{candidatos}` |
| `POST /api/detecciones/candidatos/:id/restaurar` | Deshace un descarte: vuelve a pendiente (hito 6). 404 si no existe o es de otro usuario; 409 si no está descartado |

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

## Pantallas y flujo B (hito 4)

### Flujo

```
Registro ─► 03 Permisos ─► (Acceso a notificaciones) ─► 04 Escaneo ─► 05 Resultados ─► 06 Preferencia ─► Dashboard
                │                                                         ▲
                └─► "Prefiero agregarlas a mano" ─► 13 Formulario ─► 06  │
Perfil: interruptor "Permiso de notificaciones" ─► 03 ─► 04 ─► 05 ─► Dashboard
Flujo B: abrir/volver a la app ─► procesar cola ─► candidato nuevo ─► notificación ─► 05
```

- **03 Permisos** (`/permisos`): textos del diseño. "Dar permiso y detectar"
  abre el ajuste de SubTrack en "Acceso a notificaciones"; al volver, si el
  permiso quedó concedido pasa a la 04. Si volvió sin el permiso, explica
  **"Ajuste restringido"** (Android 13+ con apps instaladas desde un APK) con
  un botón a la información de la app.
- **04 Escaneo** (`/escaneo`): reconecta el lector, recupera las
  notificaciones activas (espera hasta 3 s si el lector recién se conecta), lee
  la cola, interpreta cada una, envía los cobros y borra lo procesado. Se
  muestra al menos 1,9 s. Si falla (sin backend), "Reintentar" o "Seguir sin
  detectar"; la cola no se borra.
- **05 Resultados** (`/deteccion`): "Encontramos {n} suscripciones" con los
  candidatos **pendientes reales** (sin la etiqueta de datos de ejemplo). Cada
  fila: "{monto} · {frecuencia} · {n} cobros detectados", botones **Es mía** /
  **No es mía** y un lápiz para corregir monto y frecuencia. "Confirmar {n}
  suscripciones" confirma las marcadas (con las correcciones) y descarta las
  demás.
- **Perfil**: el interruptor "Permiso de notificaciones" muestra el estado real
  ("Activo · detección automática encendida" / "Desactivado · solo registro
  manual"). Encenderlo abre la 03; apagarlo abre los ajustes de Android.
- **Origen**: las suscripciones confirmadas dicen **"Detectada por
  notificación"** en las tarjetas del dashboard y la lista, y en el detalle.

### Flujo B

Al abrir la app y cada vez que vuelve a primer plano (`main.dart`), si hay
sesión y permiso, se procesa la cola igual que en la 04. Por cada candidato
**nuevo** que devuelve el backend llega una notificación local **"¿Tienes una
suscripción a {servicio}?"** ("Detectamos un cobro de $68.139 en Nequi…"), en
el canal "Suscripciones detectadas". Al tocarla se abre la 05. No se procesa
en segundo plano mientras están abiertas la 03, la 04, la 05 o la pantalla de
depuración (ellas mismas lo hacen, o se está revisando la cola).

### Huella

`huellaDePago` = SHA-256 de `banco|comercio normalizado|monto|moneda|fecha`.
La fecha es la del mensaje ("el 23/10/2026 a las 07:20") o, si no la trae
(Nequi), la hora en que **Android publicó** la notificación (`postTime`), no la
hora en que la app la procesó. Así la misma notificación leída en vivo y
recuperada después desde la barra da la misma huella, y el backend la marca
`repetido`.

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
| Llamadas y llamadas perdidas (por ejemplo, de Truecaller) | Solo su categoría | Se ignoran sin leer el texto |
| Con "llamada", "spam" o "estafa" (avisos de Truecaller) | El texto, en memoria | Se descarta siempre, aunque tenga monto |

**Pagos de comercios descartados (hito 6).** Cuando el usuario marca un
candidato "No es mía", sus pagos detectados (banco, comercio, monto, fecha;
nunca el texto) se conservan en el servidor **hasta 400 días**. Son solo de
servicios conocidos o de cobros recurrentes (las compras sueltas nunca llegan
al servidor). Sirven para notar si ese comercio sigue cobrando cada mes y
proponerlo de nuevo una sola vez. Se borran a los 400 días (tarea diaria), al
eliminar la cuenta (en cascada), y dejan de tener retención especial si el
usuario lo vuelve a proponer o lo confirma.

Apps permitidas hoy: la **app de SMS predeterminada** del usuario, más la lista
fija de respaldo (Mensajes de Google, Truecaller, Mensajes de Samsung y
Mensajes de Xiaomi/MIUI, con paquetes verificados). Ninguna app de correo ni
de chat. Los bancos y billeteras se agregarán cuando se identifiquen sus
paquetes (no se inventan nombres de paquete).

### 3. Qué se guarda en el celular

| Dónde | Qué | Límites |
|---|---|---|
| Almacén seguro (`pagos_locales_v1`, cifrado por Android) | Los pagos interpretados: banco, comercio, monto, moneda, fecha y si ya se enviaron. **Sin texto** | 400 días, máximo 1000, se borran al cerrar sesión. Aquí se quedan las compras puntuales (hito 5) |
| Cola: `filesDir/deteccion/cola.json` (almacenamiento interno, solo SubTrack puede leerlo) | Solo las notificaciones que parecen cobros: huella, paquete, nombre de la app, título (el remitente, p. ej. "Bancolombia"), texto y hora de llegada | Máximo 200, se borran solas a los 30 días y al desinstalar. Desde el hito 4, también al enviarlas al backend |
| SharedPreferences `subtrack_deteccion` | Hora de la última conexión, desconexión y notificación, y una palabra de resultado ("guardada", "descartada"…) | Sin paquete, título ni texto |

El parser (hito 2) lee la cola en el mismo celular; no la copia a otro lado.

### 4. Qué va al backend (hitos 3, 4 y 5)

Solo los **campos extraídos** por el parser: banco, comercio normalizado,
monto, moneda, fecha y una huella para no repetir pagos, con la sesión del
usuario, y **solo de servicios conocidos o de comercios con patrón
recurrente** (desde el hito 5; las compras puntuales se quedan en el
celular). Lo mismo para el historial de SMS: de cientos de SMS leídos, solo
salen los campos de las suscripciones encontradas. **Nunca** el texto crudo, el título, los dígitos de la tarjeta ni los
teléfonos que traen los mensajes. La huella también se calcula solo con esos
campos (no con el texto). Después de enviarlas, las notificaciones se borran
de la cola del celular, también las que el parser descartó.

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

## Cómo probar (hito 4): el flujo completo en el Xiaomi

La forma más limpia es empezar **sin la app instalada**: así no queda permiso,
sesión ni cola de pruebas anteriores, y se ve el onboarding completo
(registro → 03 → 04 → 05 → 06 → dashboard).

### 1. Preparación (PowerShell)

```powershell
# Backend (la migración 006 ya está aplicada)
cd backend
npm run dev
```

En otra terminal:

```powershell
adb reverse tcp:3000 tcp:3000
adb uninstall com.example.flutter_suscripciones
```

Lanza la app en debug con la configuración "Celular USB (localhost)". Al
reinstalar, MIUI olvida **Inicio automático** y **Ahorro de batería → Sin
restricciones**: vuelve a activarlos (guía en Perfil).

### 2. Registro y pantalla 03

Crea una cuenta de prueba (por ejemplo `deteccion2@prueba.com`). Después del
registro aparece **"Permiso para leer notificaciones de pago"**. **No toques
nada todavía.**

### 3. Simula los cobros (con la pantalla 03 abierta)

El lector aún no tiene permiso: las notificaciones solo quedan en la barra.
Al dar el permiso se recuperan desde ahí (`getActiveNotifications`).

```powershell
adb shell "cmd notification post -S bigtext -t 'Bancolombia' real1 'Bancolombia: Compraste `$19.900,00 en GOOGLE *Crunchyroll con tu T.Deb *0000, el 23/10/2026 a las 07:20. Si tienes dudas, encuentranos aqui: 6045109095 o 018000931987. Estamos cerca.'"
adb shell "cmd notification post -S bigtext -t 'Nequi' real2 'NEQUI: Pagaste 68.139,27 en ANTHROPIC* CLAUDE SUB'"
adb shell "cmd notification post -S bigtext -t 'Bancolombia' real3 'Bancolombia: Compraste `$18.900,00 en DIDI FOOD con tu T.Deb *0000, el 30/10/2026 a las 13:10.'"
```

### 4. Permiso → escaneo → resultados

1. Toca **Dar permiso y detectar** y activa SubTrack en "Acceso a
   notificaciones". Si Android muestra **"Ajuste restringido"**, al volver la
   pantalla explica cómo habilitarlo (Información de la app → ⋮ → Permitir
   ajustes restringidos).
2. Al volver con el permiso pasa sola a **"Revisando tus notificaciones de
   pago…"** (04) y después a la 05.
3. Debe decir **"Encontramos 2 suscripciones"**: Crunchyroll ($19.900 ·
   Mensual · 1 cobro detectado) y Claude ($68.139 · Mensual · 1 cobro
   detectado). DiDi Food **no** aparece: es una compra normal.

### 5. Confirmar una y descartar otra

1. Deja **Es mía** en Crunchyroll. Opcional: el lápiz permite corregir el monto
   y la frecuencia antes de confirmar.
2. Toca **No es mía** en Claude.
3. Toca **Confirmar 1 suscripción**: sale el toast "Agregamos 1 suscripción" y
   sigue la preferencia de recordatorio (06). Toca **Ir a mi dashboard** (y
   acepta el permiso de notificaciones, lo necesita el flujo B).

### 6. Verla en el dashboard

La tarjeta de Crunchyroll dice **"Mensual · Detectada por notificación"**. En
su detalle: origen **Detectada por notificación**, próximo cobro 23 nov y el
pago del 23 oct en el historial.

### 7. Flujo B (opcional)

Con la app en **segundo plano** (botón de inicio):

```powershell
adb shell "cmd notification post -S bigtext -t 'Bancolombia' real4 'Bancolombia: Compraste `$26.900,00 en NETFLIX.COM con tu T.Deb *0000, el 01/11/2026 a las 09:00.'"
```

Vuelve a la app: llega la notificación **"¿Tienes una suscripción a
Netflix?"**. Al tocarla se abren los resultados para confirmarla o
descartarla. Un nuevo cobro de Claude (descartado) no genera aviso.

### Qué debe pasar

| Paso | Resultado |
|---|---|
| Salir y volver a la app con los cobros aún en la barra | Se recuperan y se envían otra vez, pero no se duplican: la misma notificación da la misma huella (`repetido`) y no hay avisos nuevos |
| Backend apagado durante el escaneo | "No pudimos revisar tus cobros" con **Reintentar**; la cola queda intacta |
| Perfil → "Permiso de notificaciones" | "Activo · detección automática encendida". Al apagarlo abre los ajustes de Android (el permiso solo se quita ahí) |
| Pantalla de depuración abierta | No se procesa la cola en segundo plano, para poder revisarla |

### Probar la pantalla 05 sin el celular (presentación)

`npm run db:demo` deja al usuario demo (`demo@subtrack.co` / `Demo1234`) con
dos candidatos pendientes: Claude (2 cobros por Nequi) y Bodytech (3 cobros
mensuales). En la app: Perfil → interruptor (o la notificación del flujo B) →
resultados.

## Cómo probar (hito 5): historial de SMS, rechazo y "Compartir"

### Preparación

1. Aplica la migración 007 en la base que use la app (local: `npm run
   db:migrate` en `backend/`; nube: `npm run db:migrate:nube`). **Borra las
   compras normales ya guardadas** (pagos sin suscripción ni candidato).
2. Instala la versión completa y deja los logs corriendo:

   ```powershell
   flutter build apk --debug
   adb install -r build\app\outputs\flutter-apk\app-completa-debug.apk
   adb logcat -c
   adb logcat -v time -s SubTrackDeteccion:V
   ```

### 1. Búsqueda en el historial

1. Perfil → **Buscar suscripciones en mis SMS** (o, en una cuenta nueva,
   después de la pantalla 03).
2. Lee la divulgación y toca **Buscar en mis SMS** → Android pregunta por los
   SMS → **Permitir**.
3. Pantalla 04: "Revisando tus mensajes del banco…". En logcat:
   `Historial de SMS: N leídos (M de empresas), K parecen cobro`.
4. Pantalla 05 con las suscripciones encontradas (servicios conocidos y
   comercios con cobros periódicos). Una compra puntual no debe aparecer ni
   llegar al backend.
5. Repite la búsqueda desde Perfil: no deben aparecer candidatos nuevos ni
   duplicados.
6. Si sale "No vimos SMS de bancos": toca **Abrir los permisos de SubTrack**,
   revisa SMS y, en "Otros permisos", cualquier opción de SMS de servicio o de
   notificación; vuelve y toca **Buscar de nuevo**. Anota cómo se llama el
   permiso en tu HyperOS para documentarlo.

### 2. Rechazo del permiso

1. Quita el permiso y sus marcas para que Android vuelva a preguntar:

   ```powershell
   adb shell pm revoke com.example.flutter_suscripciones android.permission.READ_SMS
   adb shell pm clear-permission-flags com.example.flutter_suscripciones android.permission.READ_SMS user-set user-fixed
   ```

2. Perfil → Buscar suscripciones en mis SMS → Buscar en mis SMS → **No
   permitir**. Debe salir "Sin problema: seguimos detectando los cobros
   nuevos" y la app sigue normal (la detección por notificaciones intacta).
3. Recházalo otra vez (o marca "No volver a preguntar"). La tercera vez la
   pantalla dice "Android ya no muestra la pregunta" con **Abrir los permisos
   de SubTrack**; si lo permites ahí y vuelves, la búsqueda arranca sola.
4. **Ahora no** nunca muestra el diálogo de Android.

### 3. Compartir un SMS desde Mensajes de Google

1. En Mensajes de Google, abre un SMS del banco, **mantén presionado** el
   mensaje → menú **⋮** (o el ícono de compartir) → **Compartir** → **SubTrack**.
2. SubTrack abre "Encontramos un cobro" con comercio, monto, banco y fecha.
   **Usar este cobro** → pantalla 05 con la suscripción para confirmar (o, si
   ya la tenías, el detalle de esa suscripción con "Registramos el cobro…").
3. Comparte un SMS personal: debe decir "No reconocimos un cobro" y no enviar
   nada.
4. Compártelo con la app abierta y con la app cerrada: en los dos casos abre
   la misma pantalla.
5. Con la versión **sinSms** (`flutter run --flavor sinSms`) "Compartir"
   funciona igual, y Perfil no muestra "Buscar suscripciones en mis SMS".

### 4. Sin duplicados

Con un cobro de Nequi (sin fecha) que ya llegó por la notificación, busca en
el historial: el backend responde `repetido` y no aparece un segundo pago
(la notificación y el SMS difieren unos segundos; tolerancia de 5 minutos).

## Cómo probar (hito 6): procesadores, ambiguos y descartes

### Preparación

```powershell
cd backend
npm run db:migrate; npm run db:guias
cd ..
flutter build apk --debug
adb install -r build\app\outputs\flutter-apk\app-completa-debug.apk
adb logcat -v time -s SubTrackDeteccion:V
```

(Con el backend de Render: `db:migrate:nube` y `db:guias:nube`, y subir a
`develop`.)

### 1. EBANX con nombre real

Un procesador necesita patrón (2 cobros mensuales), y con adb solo se
simulan cobros de hoy. Por eso hay dos formas:

- **Recomendada:** la búsqueda en el historial de SMS en un celular que tenga
  cobros reales de EBANX (el de Santiago).
- Simular un cobro de hoy y comprobar que **no** aparece todavía (es compra
  puntual hasta que se repita):

```powershell
adb shell "cmd notification post -S bigtext -t 'NEQUI' ebanx1 'NEQUI: Pagaste 19.900,00 en SERVICIOS WEB EBANX CO'"
```

Con dos cobros mensuales, en la pantalla 05 debe aparecer **"Pago procesado por EBANX"** con "¿Qué
servicio es?". Al tocar "Es mía" se abre la hoja con el chip **"¿Es
Crunchyroll?"**; tócalo y confirma. La suscripción queda como Crunchyroll.

### 2. Ambiguos

```powershell
adb shell "cmd notification post -S bigtext -t 'Bancolombia' rappi1 'Bancolombia: Compraste `$32.500,00 en RAPPI con tu T.Deb *0000, el 03/11/2026 a las 20:10.'"
adb shell "cmd notification post -S bigtext -t 'Bancolombia' yt1 'Bancolombia: Compraste `$26.900,00 en GOOGLE *YouTubePremium con tu T.Deb *0000, el 03/11/2026 a las 08:00.'"
```

Rappi suelto: no aparece en la pantalla 05. YouTube Premium: sí, desde el
primer cobro.

### 3. Deshacer y descartadas

En la pantalla 05 toca "No es mía": la tarjeta se va y aparece "Descartamos X
· Deshacer" durante 5 s. Toca "Deshacer": vuelve. Descarta otra y ve a
**Perfil → Detecciones descartadas → Volver a proponer**.

### 4. Aviso de pago registrado

Con una suscripción "Netflix" de $44.900 creada, simula un cobro de Netflix y
vuelve a la app: llega "Registramos un pago de $44.900 en Netflix". Con
$49.900: "Netflix subió de $44.900 a $49.900".

## Limitaciones conocidas

- **La cola se procesa cuando la app se abre o vuelve a primer plano.** El
  lector guarda los cobros aunque la app esté cerrada, pero el envío al backend
  y la notificación del flujo B ocurren al abrir la app (no hay trabajo en
  segundo plano de Flutter).
- **Después de reinstalar o actualizar la app, HyperOS puede no reconectar el
  lector.** La app lo intenta sola (`requestRebind` y reinicio del
  componente). Si no lo logra, avisa "La detección está pausada" y el usuario
  debe apagar y encender el acceso de SubTrack en los ajustes. Mientras tanto
  no se detectan cobros nuevos.
- **Solo se leen los SMS de la app de SMS predeterminada y de la lista fija.**
  Si el usuario recibe los SMS en otra app que no es la predeterminada ni está
  en la lista, no se detectan.
- **Los avisos de Truecaller que no son SMS se probaron con textos de
  ejemplo**, no con capturas de un celular real: si Truecaller usa una
  redacción nueva, con una palabra de cobro y un monto, podría guardarse. El
  parser igual la rechaza si no es "compraste/pagaste MONTO en COMERCIO" de
  un banco conocido.
- La app de SMS predeterminada también puede mostrar chats (RCS en Mensajes de
  Google, por ejemplo). Se les aplica el mismo filtro de cobro: solo se
  guardan si parecen un cobro.
- **El historial de SMS solo existe en la versión completa** y requiere que el
  usuario dé READ_SMS. Para publicarla en Google Play hace falta la
  declaración de permisos y la revisión de Google ([google-play.md](google-play.md)).
- **Xiaomi puede ocultar los SMS de servicio** (números cortos) a las apps. La
  app lo sospecha si no ve ningún SMS de empresa y guía a los permisos de
  MIUI, pero el nombre exacto del permiso no se pudo confirmar sin el celular.
- **Un SMS de Nequi compartido otro día** que el de su llegada no se reconoce
  como repetido (no trae fecha: la elige el usuario); la tolerancia es de 5
  minutos.
- **Un comercio desconocido con un solo cobro** no llega al backend hasta que
  se repite. Si el usuario ya creó esa suscripción a mano, el primer pago no
  se enlaza; lo puede registrar con "Compartir".
- **Procesadores:** si el servicio sube más del 10 %, su cobro aparece como un
  candidato nuevo del procesador, no como cambio de precio. Solo Crunchyroll
  tiene precio de referencia para la sugerencia "¿Es X?".
- **Servicios ambiguos sin señal** (Rappi, Apple, PlayStation…) tardan al
  menos dos cobros en proponerse.
- Los cobros publicados mientras el lector estaba detenido solo se recuperan
  si siguen en la barra de notificaciones.
- Solo se reconocen los formatos de Bancolombia y Nequi probados con mensajes
  reales; los demás bancos de la lista usan la forma general
  "compraste/pagaste MONTO en COMERCIO".
- Dos compras idénticas (mismo banco, comercio, monto y minuto del mensaje)
  dan la misma huella y se cuentan como una.
