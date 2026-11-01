package com.example.flutter_suscripciones.deteccion

import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * "Compartir" un SMS con SubTrack, sin permisos: desde la app de mensajes, el
 * usuario elige SubTrack en la hoja de compartir (ACTION_SEND, text/plain).
 * Funciona en las dos versiones (completa y sinSms).
 *
 * Canal "subtrack/compartir" con lib/deteccion/compartir_page.dart:
 *  - Flutter pide "textoPendiente" al arrancar (la app se abrió compartiendo).
 *  - Si la app ya estaba abierta, se le avisa con "textoCompartido".
 * El texto solo vive en memoria: no se guarda ni se envía al backend.
 */
object CanalCompartir {
    private const val CANAL = "subtrack/compartir"
    private const val MAXIMO = 2000

    private var canal: MethodChannel? = null
    private var textoPendiente: String? = null

    fun registrar(engine: FlutterEngine, intentInicial: Intent?) {
        textoPendiente = textoDe(intentInicial)
        canal = MethodChannel(engine.dartExecutor.binaryMessenger, CANAL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "textoPendiente" -> {
                        result.success(textoPendiente)
                        textoPendiente = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /** La app ya estaba abierta (launchMode singleTop) y se compartió otro texto. */
    fun alRecibirIntent(intent: Intent?) {
        val texto = textoDe(intent) ?: return
        val c = canal
        if (c == null) {
            textoPendiente = texto
        } else {
            c.invokeMethod("textoCompartido", texto)
        }
    }

    fun liberar() {
        canal = null
    }

    private fun textoDe(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_SEND || intent.type?.startsWith("text/") != true) return null
        return intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.trim()
            ?.takeIf { it.isNotEmpty() }?.take(MAXIMO)
    }
}
