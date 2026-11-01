package com.example.flutter_suscripciones.deteccion

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.service.notification.NotificationListenerService

/**
 * Al reiniciar el celular (o al actualizar la app), le pide a Android que
 * vuelva a conectar el lector. Android suele hacerlo solo, pero algunos
 * fabricantes (Xiaomi) no siempre lo hacen.
 */
class ReconexionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        RegistroDeteccion.log(context, "Evento del sistema (${intent.action}): se pide reconectar el lector")
        try {
            NotificationListenerService.requestRebind(
                ComponentName(context, LectorNotificacionesService::class.java)
            )
        } catch (e: Exception) {
            // Sin "Acceso a notificaciones" no hay nada que reconectar.
            RegistroDeteccion.log(context, "No se pudo pedir la reconexión", e)
        }
    }
}
