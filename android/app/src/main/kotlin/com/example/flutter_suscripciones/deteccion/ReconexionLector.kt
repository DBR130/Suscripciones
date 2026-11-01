package com.example.flutter_suscripciones.deteccion

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.service.notification.NotificationListenerService

/**
 * Reconexión del lector cuando el permiso está concedido pero Android no lo
 * tiene conectado.
 *
 * Problema visto en el Xiaomi (HyperOS, Android 16): después de reinstalar o
 * actualizar la app, el sistema no vuelve a enlazar el lector y
 * requestRebind() no basta. Lo que sí lo reconecta es apagar y encender el
 * acceso en los ajustes; aquí se hace el equivalente desde la app: deshabilitar
 * y volver a habilitar el componente del servicio, que Android trata como un
 * cambio del paquete y vuelve a enlazar el lector.
 *
 * Pasos (cada uno queda en los logs, solo en debug):
 *  1. requestRebind().
 *  2. Si a los 2,5 s sigue desconectado: reiniciar el componente y otro requestRebind().
 *  3. A los 3 s: anotar si funcionó (RegistroDeteccion, se ve en la pantalla de depuración).
 */
object ReconexionLector {
    private const val ESPERA_ANTES_DE_REINICIAR_MS = 2_500L
    private const val ESPERA_COMPROBACION_MS = 3_000L

    /** No reiniciar el componente más de una vez cada 15 s (abrir y volver a la app seguido). */
    private const val MINIMO_ENTRE_REINICIOS_MS = 15_000L

    @Volatile
    private var ultimoReinicio = 0L
    private val principal = Handler(Looper.getMainLooper())

    fun componente(context: Context) = ComponentName(context, LectorNotificacionesService::class.java)

    /** true si el usuario dio a SubTrack el "Acceso a notificaciones". */
    fun permisoConcedido(context: Context): Boolean {
        val habilitados = Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners")
            ?: return false
        val propio = componente(context)
        return habilitados.split(":").any { ComponentName.unflattenFromString(it) == propio }
    }

    /**
     * Intenta reconectar si hace falta. [alTerminar] se llama al final de la
     * secuencia (o enseguida si no hay nada que hacer); lo usa
     * ReconexionReceiver para mantener vivo el proceso mientras tanto.
     */
    fun reconectar(context: Context, motivo: String, alTerminar: (() -> Unit)? = null) {
        val app = context.applicationContext
        if (LectorNotificacionesService.conectado) {
            alTerminar?.invoke()
            return
        }
        if (!permisoConcedido(app)) {
            RegistroDeteccion.log(app, "Reconexión ($motivo): sin acceso a notificaciones, nada que reconectar")
            alTerminar?.invoke()
            return
        }
        pedirRebind(app, motivo)
        principal.postDelayed({
            if (LectorNotificacionesService.conectado) {
                RegistroDeteccion.log(app, "Reconexión ($motivo): funcionó con requestRebind")
                RegistroDeteccion.marcarReconexion(app, "conectado con requestRebind")
                alTerminar?.invoke()
            } else if (!permisoConcedido(app)) {
                alTerminar?.invoke()
            } else {
                reiniciarComponente(app, motivo, alTerminar)
            }
        }, ESPERA_ANTES_DE_REINICIAR_MS)
    }

    private fun pedirRebind(app: Context, motivo: String) {
        try {
            NotificationListenerService.requestRebind(componente(app))
            RegistroDeteccion.log(app, "Reconexión ($motivo): requestRebind enviado")
        } catch (e: Exception) {
            RegistroDeteccion.log(app, "Reconexión ($motivo): requestRebind falló", e)
        }
    }

    private fun reiniciarComponente(app: Context, motivo: String, alTerminar: (() -> Unit)?) {
        val ahora = SystemClock.elapsedRealtime()
        if (ahora - ultimoReinicio < MINIMO_ENTRE_REINICIOS_MS) {
            RegistroDeteccion.log(app, "Reconexión ($motivo): el componente se reinició hace poco; no se repite")
            alTerminar?.invoke()
            return
        }
        ultimoReinicio = ahora
        try {
            val pm = app.packageManager
            val c = componente(app)
            // DONT_KILL_APP: el servicio vive en el proceso de la app; sin esta
            // bandera Android cerraría la app al cambiar el componente.
            pm.setComponentEnabledSetting(c, PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
            pm.setComponentEnabledSetting(c, PackageManager.COMPONENT_ENABLED_STATE_DEFAULT, PackageManager.DONT_KILL_APP)
            RegistroDeteccion.log(app, "Reconexión ($motivo): componente del lector reiniciado (deshabilitar y habilitar)")
        } catch (e: Exception) {
            RegistroDeteccion.log(app, "Reconexión ($motivo): no se pudo reiniciar el componente", e)
        }
        pedirRebind(app, "$motivo, tras reiniciar el componente")

        principal.postDelayed({
            val resultado = when {
                LectorNotificacionesService.conectado -> "conectado tras reiniciar el componente"
                !permisoConcedido(app) -> "Android quitó el acceso al reiniciar el componente"
                else -> "sigue desconectado: hay que apagar y encender el acceso a mano"
            }
            RegistroDeteccion.log(app, "Reconexión ($motivo): $resultado")
            RegistroDeteccion.marcarReconexion(app, resultado)
            alTerminar?.invoke()
        }, ESPERA_COMPROBACION_MS)
    }
}
