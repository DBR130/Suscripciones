# Publicar SubTrack en Google Play: permisos de SMS y notificaciones

Este documento prepara la publicación de la **versión completa** (con "Buscar
suscripciones en mis SMS", que usa `READ_SMS`). La versión **sinSms** no
declara `READ_SMS` y no necesita la declaración de permisos de SMS. Ver
"Versiones completa y sinSms" en [deteccion.md](deteccion.md).

> Los textos de abajo son una propuesta para revisar antes de enviarlos. La
> política se tomó del artículo de Google Play "Use of SMS or Call Log
> permission groups" (consultado el 1 de noviembre de 2026). Revísalo de nuevo
> antes de enviar: Google lo cambia.

## Qué dice la política (resumen)

- `READ_SMS` es un permiso **restringido**. Lo pueden usar la app de SMS
  predeterminada o las apps que califican para una **excepción**, siempre que
  sea para su **función principal** y no haya alternativa.
- SubTrack califica para la excepción **"SMS-based money management"** (el
  ejemplo de Google son las apps que registran y administran presupuestos).
  Permite `READ_SMS` (también `RECEIVE_SMS`, que SubTrack **no** usa).
- Hay que llenar el **formulario de declaración de permisos** en Play Console
  y Google lo revisa. Si cambia el uso del permiso, hay que enviarlo de nuevo.
- Exige **divulgación destacada y consentimiento** (política de datos del
  usuario) antes de pedir el permiso.
- Prohíbe **sacar del celular o compartir SMS personales o no financieros**, y
  vender o transferir los datos de SMS (también mediante SDK). Los datos solo
  se pueden usar para el propósito declarado.

## Cómo cumple SubTrack

| Requisito | Cómo se cumple | Dónde |
|---|---|---|
| Función principal | Detectar las suscripciones del usuario a partir de los cobros de su banco es la función central de la app (RF02, RF03) | Toda la app |
| No hay alternativa para el historial | El lector de notificaciones solo ve las notificaciones **nuevas**: no puede leer los SMS que llegaron antes de instalar la app, y las notificaciones viejas se borran de la barra | `docs/deteccion.md`, "Tres caminos" |
| Divulgación destacada | Pantalla "¿Buscamos suscripciones que ya pagas?" antes del diálogo de Android, con "Buscar en mis SMS" y "Ahora no" | `lib/deteccion/historial_sms_page.dart` |
| Consentimiento | El permiso se pide solo al tocar "Buscar en mis SMS". Si lo rechaza, la app funciona igual | Ídem |
| No sacar SMS personales ni no financieros | Los SMS que no parecen cobros se descartan en la parte nativa; nunca sale el texto de ningún SMS; solo salen monto, comercio, banco y fecha de los cobros de suscripciones (servicios conocidos o patrón recurrente); las compras puntuales se quedan en el celular | `LectorHistorialSms.kt`, `analizador_pagos.dart` |
| Uso limitado | Una revisión de los últimos 6 meses cuando el usuario la pide; no hay lectura en segundo plano ni `RECEIVE_SMS` | `procesador_detecciones.dart` |
| Sin venta ni SDK de terceros | SubTrack no tiene SDK de publicidad ni de analítica; los datos van solo a su propio backend | `pubspec.yaml` |

## Texto propuesto para el formulario de declaración de permisos

**Permiso:** `android.permission.READ_SMS`

**Excepción / caso de uso:** SMS-based money management

**Función principal de la app (descripción):**

> SubTrack ayuda a las personas a llevar el control de sus suscripciones
> (streaming, música, software, gimnasio): cuánto pagan, cada cuánto y cuándo
> es el próximo cobro, con recordatorios para cancelar a tiempo. Para no tener
> que registrarlas a mano, SubTrack detecta las suscripciones a partir de los
> SMS de cobro que envían los bancos ("Bancolombia: Compraste $44.900 en
> NETFLIX…").

**Por qué la app necesita READ_SMS:**

> Los cobros nuevos se detectan con el acceso a notificaciones, sin leer SMS.
> Pero ese acceso solo ve las notificaciones que llegan desde que se instala la
> app: no puede encontrar las suscripciones que el usuario ya paga. Una
> suscripción mensual se cobra una vez al mes; sin el historial, el usuario
> tendría que esperar semanas para que aparezca o registrarla a mano, que es
> justo lo que la app busca evitar. Con READ_SMS, y solo cuando el usuario lo
> pide en la opción "Buscar suscripciones en mis SMS", SubTrack revisa una vez
> los SMS recibidos de los últimos 6 meses para encontrar los cobros
> recurrentes.

**Cómo se usa y se protege el dato:**

> - El permiso se pide solo después de una pantalla de divulgación que explica
>   qué se lee, para qué, qué sale del celular y cómo revocarlo; el usuario
>   puede elegir "Ahora no" y la app funciona igual.
> - El análisis se hace en el celular. Los SMS que no parecen cobros de bancos
>   se descartan en el dispositivo sin guardarse.
> - El texto de los SMS nunca sale del celular. Al servidor de SubTrack solo
>   llegan el monto, el comercio, el banco y la fecha de los cobros de
>   suscripciones (servicios conocidos o cobros que se repiten); las compras
>   puntuales y los SMS personales no salen del dispositivo.
> - No se usa RECEIVE_SMS ni se leen SMS en segundo plano.
> - Los datos no se venden ni se comparten con terceros, y se usan solo para
>   detectar suscripciones.

**Video de demostración (si Play Console lo pide):** grabar en el celular:
Perfil → "Buscar suscripciones en mis SMS" → la divulgación completa →
"Buscar en mis SMS" → diálogo de Android → resultados (pantalla 05). Mostrar
también "Ahora no" y que la app sigue funcionando.

## Política de privacidad: qué debe decir sobre SMS y notificaciones

La política debe estar publicada en una URL pública (se pone en Play Console y
en la app). Además de lo general (cuenta, suscripciones, Ley 1581 de 2012,
derechos del titular, eliminar la cuenta), debe incluir:

1. **Acceso a notificaciones.** SubTrack recibe las notificaciones del
   celular para detectar cobros de suscripciones. Solo procesa las de la app
   de SMS y de una lista de apps de mensajes; de esas, solo usa las que
   parecen cobros de un banco. No lee chats, correos ni otras apps. Se puede
   quitar en Ajustes → Acceso a notificaciones.
2. **SMS (opcional).** Solo si el usuario lo activa en "Buscar suscripciones
   en mis SMS", SubTrack lee una vez los SMS recibidos de los últimos 6 meses.
   Los que no parecen cobros se descartan en el celular. El permiso se puede
   quitar en Ajustes → Aplicaciones → SubTrack → Permisos → SMS.
3. **Qué sale del celular.** Nunca el texto de un SMS o notificación. Solo
   banco, comercio, monto, moneda y fecha de los cobros de suscripciones
   (servicios conocidos o cobros que se repiten), para mostrarlos en la cuenta
   del usuario. Las compras puntuales se guardan solo en el celular, cifradas,
   por máximo 400 días, y se borran al cerrar sesión.
4. **Compartir.** Si el usuario comparte un mensaje con SubTrack, se analiza
   en el celular y, solo si él lo confirma, se envían los mismos campos.
5. **Conservación en el servidor.** Los pagos que no terminan en una
   suscripción o propuesta pendiente se borran; al eliminar la cuenta se
   borran todos los datos.
6. **No se venden ni se comparten** los datos con terceros; no hay SDK de
   publicidad ni de analítica.
7. Finalidad, responsable del tratamiento, canal de contacto y derechos
   (conocer, actualizar, rectificar, suprimir, revocar la autorización).

## Lista de verificación para publicar

**Antes de compilar**

- [ ] `applicationId` propio (hoy es `com.example.flutter_suscripciones`;
      Google Play no acepta `com.example`). Cambiarlo implica reinstalar la app.
- [ ] Llave de firma propia (upload key) y Play App Signing; hoy el release se
      firma con la llave de debug.
- [ ] `versionCode` / `versionName` en `pubspec.yaml`.
- [ ] Ícono y nombre "SubTrack" (ya está el nombre).
- [ ] Backend en producción con HTTPS (Render) y migraciones aplicadas
      (incluida la 007).

**Compilar** (Play pide App Bundle):

```powershell
flutter build appbundle --release --flavor completa --dart-define=API_URL=https://TU-SERVICIO.onrender.com
```

(sale en `build\app\outputs\bundle\completaRelease\app-completa-release.aab`).
Si la declaración de SMS no se aprueba, publicar la versión **sinSms**
(`--flavor sinSms`): no necesita la declaración y conserva el lector de
notificaciones, el registro manual y "Compartir".

**En Play Console**

- [ ] Política de privacidad publicada (URL) con los puntos de arriba.
- [ ] **Seguridad de los datos** (Data safety): declarar que se recogen datos
      financieros (historial de compras: comercio, monto, fecha), mensajes
      (SMS, procesados en el dispositivo; solo se transfieren los campos de
      cobros de suscripciones), correo y nombre de la cuenta; cifrado en
      tránsito (HTTPS); el usuario puede pedir que se borren (eliminar la
      cuenta).
- [ ] **Declaración de permisos** de SMS (`READ_SMS`, "SMS-based money
      management") con los textos de arriba y, si lo piden, el video.
- [ ] Acceso a notificaciones: no tiene formulario propio, pero se describe en
      la política y en la ficha.
- [ ] Ficha de la tienda que mencione la detección automática con SMS y
      notificaciones.
- [ ] Clasificación de contenido y público objetivo (adultos).
- [ ] Prueba interna o cerrada con los probadores antes de producción.

**Después**

- [ ] Si cambia el uso de SMS (por ejemplo, otro rango de meses o lectura en
      segundo plano), enviar de nuevo la declaración.
