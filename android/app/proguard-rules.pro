# Reglas de R8 para el APK release (minify). Solo lo necesario.
#
# Las clases declaradas en AndroidManifest.xml (MainActivity,
# LectorNotificacionesService, ReconexionReceiver) ya las conserva la regla que
# genera AAPT a partir del manifest: no necesitan regla aquí.

# WorkManager crea su base de datos de Room por reflexión
# (WorkDatabase_Impl.<init>()). Sin esto el release se cierra al abrir:
# "NoSuchMethodException: androidx.work.impl.WorkDatabase_Impl.<init> []".
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }

# ProcesarColaWorker (encargo B) no está en el manifest: WorkManager guarda su
# nombre en la base y lo crea por reflexión con (Context, WorkerParameters).
-keep class com.example.flutter_suscripciones.deteccion.ProcesarColaWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}
