# SubTrack: contexto para Claude Code

App para llevar el control de suscripciones (streaming, software, gimnasio):
cuánto cuestan, cada cuánto se cobran, recordatorios y guías para cancelar.
Proyecto de clase de David. Flutter (Android) + backend Node/Express +
PostgreSQL. Responde y documenta **en español**.

## Estado

- Fases terminadas:
  1. Autenticación (login, registro, JWT).
  2. Suscripciones manuales y dashboard.
  3. Recordatorios locales, historial de pagos y cambios de precio.
  4. Cancelación con guías y ahorro.
  5. Despliegue en la nube: backend en **Render**
     (`https://subtrack-api-4150.onrender.com`, plan gratis, se duerme a los
     15 min y tarda ~1 min en despertar) y base de datos en **Neon**. Guía:
     [docs/despliegue.md](docs/despliegue.md).
- **Detección automática**, hitos 1 a 5 hechos: lector de notificaciones
  (app de SMS predeterminada + lista fija), parser en Dart, backend de pagos y
  candidatos, pantallas 03/04/05, búsqueda opcional en el historial de SMS,
  "Compartir" un SMS y análisis en el celular. Todo en
  [docs/deteccion.md](docs/deteccion.md).
- **Fase de diseño** hecha: logo "Cuenta regresiva" (ícono adaptativo, splash
  nativo, ícono de notificaciones), animación de inicio, barra de pestañas
  flotante con botón "+" y campana de avisos, pestaña **Análisis**
  (`GET /api/analisis`, fl_chart) y fluidez (transiciones, Hero, esqueletos,
  vibración). Detalle en [design/subtrack-pantallas.md](design/subtrack-pantallas.md)
  (pantalla 15 y "Movimiento").
- Dos versiones Android (*product flavors*): `completa` (con READ_SMS para el
  historial) y `sinSms` (sin READ_SMS). `default-flavor: completa`.

## Estructura

| Carpeta | Qué hay | Detalle |
|---|---|---|
| `lib/` | App Flutter. `Common/` (tema `AppTheme`/`AppColors`, rutas `Routers`), `Pages/`, `widgets/` (`app_shell` barra flotante, `animacion_inicio`, `movimiento` transiciones/esqueletos/escalonado, `presionable`, `campana_avisos`), `services/` (API, sesión, recordatorios, `avisos_nuevos`), `models/`, `deteccion/` | |
| `assets/logo/`, `assets/iconos/` | SVG del logo que usa la app; PNG del ícono y splash (salen de los SVG con `flutter test tool/generar_iconos.dart`) | `pubspec.yaml` (flutter_launcher_icons, flutter_native_splash) |
| `android/app/src/main/kotlin/.../deteccion/` | Lector de notificaciones, filtro de cobros, reconexión, canales con Flutter | [docs/deteccion.md](docs/deteccion.md) |
| `android/app/src/completa/`, `src/sinSms/` | Lo que cambia entre versiones (READ_SMS, `LectorHistorialSms.kt`) | ídem, "Versiones completa y sinSms" |
| `backend/` | API Express 5 (`src/`), migraciones SQL (`db/migraciones/`), catálogo de guías (`db/guias.json`), demo (`db/demo.js`), tests (`test/`) | [backend/README.md](backend/README.md) |
| `design/` | Diseño: `subtrack-simulacion.html` (fuente visual, manda sobre el resto), `subtrack-pantallas.md` (15 pantallas con colores y textos, componentes y movimiento), `logo/` | |
| `docs/` | `deteccion.md` (detección y privacidad), `despliegue.md` (Render + Neon), `google-play.md` (permisos de SMS y publicación), `probar-la-app.md` (guía para probadores, lenguaje simple) | |
| `test/` | Tests de Flutter (`test/fixtures/` con SMS reales y avisos de Truecaller) | |
| `postman/` | Colecciones de la API | |

`README.md` de la raíz es la plantilla de Flutter (sin contenido propio).

## Ramas y versiones

| Rama | Qué es |
|---|---|
| `main` | Versión estable. Etiqueta **`v1.0`** (antes de la búsqueda en el historial de SMS) |
| `develop` | Versión de pruebas. **Render despliega desde `develop`** |
| `David` | Donde trabaja Claude Code |

## Reglas de trabajo

- **Solo en la rama `David`.** Commits pequeños y descriptivos. **No hacer
  push ni merge** (tampoco a `develop` ni a `main`: un merge a `develop`
  despliega en Render).
- **No cambiar el `applicationId`** (`com.example.flutter_suscripciones`): se
  perderían los datos, la sesión y el acceso a notificaciones al reinstalar.
- **No tocar `backend/.env` ni `backend/.env.produccion`** (están en
  `.gitignore`). Nunca commitear secretos (cadena de Neon, `JWT_SECRET`).
- **Los tests nunca tocan la base real** (`subtrack`): usan `subtrack_test`.
  El candado (`backend/src/utils/candadoBd.js`) impide conectarse bajo
  `node:test` / `NODE_ENV=test` a una base que no termine en `_test`. En los
  tests, **no importes `src/db.js` (ni nada que lo importe) con `import`
  estático**: impórtalo dentro de `before()`, después de `prepararBdPruebas()`.
- `linux/`, `macos/` y `windows/` aparecen modificados solo por fines de
  línea (archivos generados): **no los commitees**.
- Privacidad: el texto de los SMS/notificaciones **nunca** se envía al
  backend, solo campos extraídos. No leer correos ni chats. No inventar
  nombres de paquete (verificarlos).
- Al terminar: `flutter analyze` sin avisos, `flutter test` y `npm test`
  pasando. Mantener [docs/deteccion.md](docs/deteccion.md) al día (lo usa
  Santiago para el informe y QA).
- El usuario crea las cuentas y configura los paneles de Render y Neon.

## Comandos (PowerShell, desde la raíz)

```powershell
# Backend (en backend/)
npm run dev                # API local en :3000 (usa backend/.env)
npm test                   # tests contra subtrack_test
npm run db:migrate         # migraciones en la base local
npm run db:migrate:nube    # migraciones en Neon (usa .env.produccion)
npm run db:guias / db:demo # catálogo de guías / datos de demo (también :nube)

# Flutter
flutter analyze
flutter test
flutter run                                   # versión completa
flutter run --flavor sinSms

# Logo: si cambian los SVG de assets/logo/, regenerar ícono y splash
flutter test tool/generar_iconos.dart
dart run flutter_launcher_icons
dart run flutter_native_splash:create
flutter build apk --release --flavor completa --dart-define=API_URL=https://subtrack-api-4150.onrender.com
flutter build apk --release --flavor sinSms   --dart-define=API_URL=https://subtrack-api-4150.onrender.com
# APKs: build\app\outputs\flutter-apk\app-completa-debug.apk, app-sinsms-release.apk, ...

# Tests nativos (Kotlin): necesitan el Java de Android Studio
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
cd android; .\gradlew.bat :app:testCompletaDebugUnitTest; cd ..

# Celular por USB
adb reverse tcp:3000 tcp:3000                 # el celular ve el backend local
adb install -r build\app\outputs\flutter-apk\app-completa-debug.apk
adb logcat -v time -s SubTrackDeteccion:V     # logs del lector (solo debug)
```

Sin `--dart-define=API_URL=...` la app apunta a `http://10.0.2.2:3000`. En
VS Code (`.vscode/launch.json`): "Celular USB (localhost)" y "Celular (nube)".

## Dispositivo de prueba

Xiaomi 25080RABDG, HyperOS, Android 16, por USB. Probadores: Santiago
(Xiaomi, Truecaller como app de SMS) y Cristian (Samsung).

## Decisiones ya tomadas

| Tema | Decisión | Dónde |
|---|---|---|
| Privacidad de la detección | Filtrar en el celular; al backend solo campos extraídos (banco, comercio, monto, moneda, fecha, huella) | [deteccion.md › Privacidad](docs/deteccion.md#privacidad-rnf01-habeas-data-ley-1581-de-2012) |
| Apps de SMS | Se permite la app de SMS predeterminada + lista fija verificada; avisos de llamadas/spam se descartan | [deteccion.md › Cualquier app de SMS](docs/deteccion.md#cualquier-app-de-sms-app-predeterminada) |
| Reconexión del lector | `requestRebind` y, si no basta, reiniciar el componente; si falla, "Detección pausada" | [deteccion.md › Lector desconectado](docs/deteccion.md#lector-desconectado-tras-reinstalar-o-actualizar-hyperos) |
| Historial de SMS | Opcional, con divulgación destacada y READ_SMS solo al pedirlo; sin RECEIVE_SMS | [deteccion.md › Tres caminos](docs/deteccion.md#tres-caminos-notificaciones-historial-de-sms-y-compartir-hito-5) |
| Compras normales | Se quedan en el celular (cifradas, 400 días); solo salen servicios conocidos y cobros recurrentes; el backend purga lo demás (migración 007) | ídem, "Decisión: las compras normales se quedan en el celular" |
| Duplicados | Huella con la fecha del mensaje; sin fecha (Nequi), tolerancia de 5 min | ídem, "Sin duplicados entre caminos" |
| Servidor dormido | La app espera hasta 75 s y avisa "Despertando el servidor…"; en el arranque el anillo del logo sigue girando hasta que responde | [despliegue.md](docs/despliegue.md) |
| Navegación | Barra flotante (Resumen, Suscripciones, Análisis, Perfil) + botón "+"; Avisos en la campana del encabezado (contador de no vistos guardado en el celular). Ahorro se ve en Análisis; Perfil tiene acceso directo | `widgets/app_shell.dart` |
| Análisis | Una sola petición `GET /api/analisis` (sin migraciones). No se convierten monedas: selector COP/USD en las gráficas y "más caras" con COP primero | [backend/README.md](backend/README.md) |
| Animaciones | Todas respetan `MediaQuery.disableAnimations`; sin Lottie ni videos | `widgets/movimiento.dart` |
| Firma | El release se firma con la llave de debug (sin llave de Play Store) | [despliegue.md](docs/despliegue.md) |

## Pendientes conocidos

- **Actualizar Render** con `GET /api/analisis` (llega al hacer merge a
  `develop`; no necesita migraciones). Hasta entonces, la pestaña Análisis
  con el backend de la nube muestra "Ruta no encontrada" (con "Reintentar").
- Probar en el Xiaomi la fase de diseño: ícono, splash, animación de inicio,
  barra flotante, Análisis y "Quitar animaciones".
- Probar el hito 5 en el Xiaomi (historial de SMS, rechazo del permiso,
  "Compartir").
- Aplicar la **migración 007** en la base **local** (`npm run db:migrate`;
  borra las compras normales ya guardadas). En Neon ya está aplicada.
- Confirmar el nombre del permiso de Xiaomi para los "SMS de servicio".
- Los avisos de Truecaller se probaron con textos de ejemplo, no capturas
  reales.
- Agregar los paquetes de apps de bancos a `deteccion_apps.json` cuando se
  identifiquen (modo descubrimiento).
- Para Google Play: `applicationId` propio, llave de firma, declaración de
  READ_SMS ([docs/google-play.md](docs/google-play.md)). No cambiar nada de
  esto sin que David lo pida.
- Limitaciones de la detección: ver "Limitaciones conocidas" en
  [docs/deteccion.md](docs/deteccion.md#limitaciones-conocidas).

**Para después del diseño (detección):**

- **Procesadores de pago** (EBANX, PayU, dLocal, Mercado Pago, PayPal,
  Stripe): un probador vio "Servicios Web Ebanx Co" como suscripción.
  Preguntar "¿Qué servicio es?", permitir editar el nombre en la pantalla 05,
  sugerir el servicio por el monto y separar por monto los cobros del mismo
  procesador.
- **Aviso al instante con la app cerrada** (WorkManager): hoy la cola se
  procesa al abrir la app.
- **Servicios ambiguos** (Rappi Pro, Apple, PlayStation Plus, Xbox Game Pass,
  YouTube Premium): proponerlos solo con patrón de cobros, no desde el primer
  pago.
- **Deshacer un descarte** ("Detecciones descartadas" en Perfil) y aviso
  "Registramos un pago de X en Y".
