package com.example.flutter_suscripciones.deteccion

import android.content.Context
import android.util.Log

/** Tag fijo de los logs: adb logcat -v time -s SubTrackDeteccion:V (ver docs/deteccion.md). */
const val TAG = "SubTrackDeteccion"

/**
 * Horas de la última conexión, desconexión y notificación del lector, en
 * SharedPreferences para que sobrevivan si Android mata el proceso. Las
 * muestra la pantalla de depuración. Nunca guarda el texto ni el paquete de
 * las notificaciones: solo la hora y el resultado.
 */
object RegistroDeteccion {
    private const val ARCHIVO = "subtrack_deteccion"

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(ARCHIVO, Context.MODE_PRIVATE)

    fun marcarConexion(context: Context) =
        prefs(context).edit().putLong("ultima_conexion", System.currentTimeMillis()).apply()

    fun marcarDesconexion(context: Context) =
        prefs(context).edit().putLong("ultima_desconexion", System.currentTimeMillis()).apply()

    /** resultado: "guardada", "repetida", "descartada" o "app no permitida". */
    fun marcarNotificacion(context: Context, resultado: String) =
        prefs(context).edit()
            .putLong("ultima_notificacion", System.currentTimeMillis())
            .putString("ultimo_resultado", resultado)
            .apply()

    /** Último intento de reconexión forzada y su resultado (pantalla de depuración). */
    fun marcarReconexion(context: Context, resultado: String) =
        prefs(context).edit()
            .putLong("ultima_reconexion", System.currentTimeMillis())
            .putString("resultado_reconexion", resultado)
            .apply()

    /**
     * Última ejecución de la tarea de fondo (ProcesarColaWorker): resultado
     * ("ok", "sin sesión", "reintento…"), cuántas notificaciones revisó y el
     * motivo (un error del servidor, nunca el texto de un SMS).
     */
    fun marcarEjecucionFondo(context: Context, resultado: String, procesados: Int, motivo: String?) =
        prefs(context).edit()
            .putLong("ultima_ejecucion_fondo", System.currentTimeMillis())
            .putString("resultado_fondo", resultado)
            .putInt("procesados_fondo", procesados)
            .putString("motivo_fondo", motivo)
            .apply()

    fun leer(context: Context): Map<String, Any?> {
        val p = prefs(context)
        fun hora(clave: String): Long? = p.getLong(clave, 0L).takeIf { it > 0 }
        return mapOf(
            "ultima_conexion" to hora("ultima_conexion"),
            "ultima_desconexion" to hora("ultima_desconexion"),
            "ultima_notificacion" to hora("ultima_notificacion"),
            "ultimo_resultado" to p.getString("ultimo_resultado", null),
            "ultima_reconexion" to hora("ultima_reconexion"),
            "resultado_reconexion" to p.getString("resultado_reconexion", null),
            "ultima_ejecucion_fondo" to hora("ultima_ejecucion_fondo"),
            "resultado_fondo" to p.getString("resultado_fondo", null),
            "procesados_fondo" to p.getInt("procesados_fondo", 0),
            "motivo_fondo" to p.getString("motivo_fondo", null),
        )
    }

    /**
     * Único punto de logs del lector. Solo en compilaciones debug: en release
     * no se escribe nada. Nunca recibe el texto ni el título de una
     * notificación, y de un error solo se anota el tipo (el mensaje de una
     * excepción podría traer parte del texto).
     */
    fun log(context: Context, mensaje: String, error: Throwable? = null) {
        if (!ConfiguracionDeteccion.esDebug(context)) return
        if (error == null) Log.i(TAG, mensaje) else Log.w(TAG, "$mensaje (${error.javaClass.simpleName})")
    }
}
