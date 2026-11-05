package com.example.flutter_suscripciones.deteccion

import android.content.Context
import android.os.Build
import android.os.SystemClock
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.util.concurrent.TimeUnit

/**
 * Procesa la cola de cobros con la app cerrada (aviso al instante).
 *
 * El lector programa esta tarea al guardar un cobro. La tarea arranca un motor
 * de Flutter sin pantalla y ejecuta procesarEnSegundoPlano() (lib/main.dart):
 * la misma lógica de Dart que la app (parser, almacén cifrado, análisis,
 * envío y avisos). El motor se destruye SIEMPRE al terminar: éxito, error,
 * tiempo máximo ([TIEMPO_MAXIMO_MS]) o cancelación de Android.
 *
 * Detalle y pruebas en docs/deteccion.md ("Aviso al instante con la app cerrada").
 */
class ProcesarColaWorker(contexto: Context, parametros: WorkerParameters) :
    CoroutineWorker(contexto, parametros) {

    companion object {
        private const val NOMBRE = "subtrack_procesar_cola"
        private const val CANAL = "subtrack/segundo_plano"
        private const val PUNTO_DE_ENTRADA = "procesarEnSegundoPlano"
        const val QUIEN = "fondo"

        /** Tiempo máximo total por ejecución (incluye despertar el servidor, 75 s). */
        const val TIEMPO_MAXIMO_MS = 150_000L

        /** Después de estos intentos se deja para cuando se abra la app. */
        const val MAX_INTENTOS = 10

        /**
         * Trabajo único con APPEND_OR_REPLACE: si ya hay una ejecución en curso,
         * la nueva va detrás (nunca dos a la vez); si la anterior falló, la
         * reemplaza. Expedita en Android 12+ (si no hay cupo, normal); en
         * Android 7–11, normal. Siempre con red.
         */
        fun programar(context: Context, motivo: String) {
            try {
                val solicitud = OneTimeWorkRequestBuilder<ProcesarColaWorker>()
                    .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                    .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                    .apply {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                        }
                    }
                    .build()
                WorkManager.getInstance(context.applicationContext)
                    .enqueueUniqueWork(NOMBRE, ExistingWorkPolicy.APPEND_OR_REPLACE, solicitud)
                RegistroDeteccion.log(context, "Tarea de fondo programada ($motivo)")
            } catch (e: Exception) {
                // Nunca tumbar el lector: la app procesará la cola al abrirse.
                RegistroDeteccion.log(context, "No se pudo programar la tarea de fondo", e)
            }
        }
    }

    override suspend fun doWork(): Result {
        val contexto = applicationContext
        val intento = runAttemptCount + 1
        RegistroDeteccion.log(contexto, "Tarea de fondo: intento $intento de $MAX_INTENTOS")
        val resultado = try {
            withTimeoutOrNull(TIEMPO_MAXIMO_MS) { ejecutarMotor(contexto) }
        } catch (e: Exception) {
            RegistroDeteccion.log(contexto, "Tarea de fondo: error del motor", e)
            RegistroDeteccion.marcarEjecucionFondo(contexto, "reintento", 0, "error del motor (${e.javaClass.simpleName})")
            "reintentar"
        }
        if (resultado == null) {
            RegistroDeteccion.log(contexto, "Tarea de fondo: tiempo máximo (${TIEMPO_MAXIMO_MS / 1000} s)")
            RegistroDeteccion.marcarEjecucionFondo(contexto, "reintento", 0, "tiempo máximo (${TIEMPO_MAXIMO_MS / 1000} s)")
        }
        return when (resultado) {
            "ok", "sinSesion" -> Result.success()
            else -> if (intento >= MAX_INTENTOS) {
                // Nunca Result.failure(): fallaría también lo que espera detrás
                // (APPEND). La cola sigue guardada y la procesa la app al abrirse.
                RegistroDeteccion.marcarEjecucionFondo(contexto, "sin más reintentos", 0, "la app lo procesará al abrirse")
                RegistroDeteccion.log(contexto, "Tarea de fondo: sin más reintentos")
                Result.success()
            } else {
                Result.retry()
            }
        }
    }

    /**
     * Arranca el motor sin pantalla, espera a que Dart diga "terminar" y lo
     * destruye en el finally (también si la corrutina se cancela por el tiempo
     * máximo o porque Android detuvo la tarea).
     */
    private suspend fun ejecutarMotor(contexto: Context): String = withContext(Dispatchers.Main) {
        val inicio = SystemClock.elapsedRealtime()
        var motor: FlutterEngine? = null
        try {
            val cargador = FlutterInjector.instance().flutterLoader()
            cargador.startInitialization(contexto)
            cargador.ensureInitializationComplete(contexto, null)
            val terminado = CompletableDeferred<String>()
            val nuevo = FlutterEngine(contexto)
            motor = nuevo
            CanalDeteccion.registrarDatos(contexto, nuevo)
            MethodChannel(nuevo.dartExecutor.binaryMessenger, CANAL).setMethodCallHandler { call, result ->
                when (call.method) {
                    // Primera línea de Dart: cuánto tardó en arrancar el motor.
                    "inicio" -> {
                        RegistroDeteccion.log(contexto, "Motor de fondo listo en ${SystemClock.elapsedRealtime() - inicio} ms")
                        result.success(null)
                    }
                    "terminar" -> {
                        terminado.complete(call.arguments as? String ?: "reintentar")
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
            nuevo.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(cargador.findAppBundlePath(), PUNTO_DE_ENTRADA)
            )
            terminado.await()
        } finally {
            motor?.destroy()
            // Si Dart no alcanzó a soltar el turno (tiempo máximo, cancelación),
            // se suelta aquí para no bloquear a la app 3 minutos.
            TurnoDeteccion.soltar(QUIEN)
            RegistroDeteccion.log(contexto, "Motor de fondo destruido tras ${SystemClock.elapsedRealtime() - inicio} ms")
        }
    }
}
