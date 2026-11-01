package com.example.flutter_suscripciones.deteccion

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Al reiniciar el celular o al actualizar/reinstalar la app
 * (MY_PACKAGE_REPLACED), intenta reconectar el lector. Después de una
 * actualización, HyperOS a veces no lo vuelve a enlazar solo
 * (ver ReconexionLector y docs/deteccion.md).
 */
class ReconexionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val motivo = when (intent.action) {
            Intent.ACTION_MY_PACKAGE_REPLACED -> "app actualizada"
            Intent.ACTION_BOOT_COMPLETED -> "celular reiniciado"
            else -> intent.action ?: "evento del sistema"
        }
        RegistroDeteccion.log(context, "Evento del sistema ($motivo): se intenta reconectar el lector")
        // goAsync: mantiene vivo el proceso mientras dura la secuencia (unos 6 s).
        val pendiente = goAsync()
        ReconexionLector.reconectar(context, motivo) { pendiente.finish() }
    }
}
