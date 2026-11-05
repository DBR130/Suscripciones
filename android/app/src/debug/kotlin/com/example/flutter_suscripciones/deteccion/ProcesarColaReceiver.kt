package com.example.flutter_suscripciones.deteccion

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Solo en debug (src/debug): fuerza la tarea de fondo desde el PC, con la app
 * cerrada:
 *   adb shell am broadcast -a com.example.flutter_suscripciones.PROCESAR_COLA -p com.example.flutter_suscripciones
 */
class ProcesarColaReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        ProcesarColaWorker.programar(context, "forzada por adb")
    }
}
