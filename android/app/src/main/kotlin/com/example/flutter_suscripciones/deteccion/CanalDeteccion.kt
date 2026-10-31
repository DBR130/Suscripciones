package com.example.flutter_suscripciones.deteccion

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.service.notification.NotificationListenerService
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Canales entre Flutter (lib/deteccion/lector_notificaciones.dart) y el lector:
 *  - MethodChannel "subtrack/deteccion": estado, permiso, cola y configuración.
 *  - EventChannel "subtrack/deteccion/eventos": notificaciones en vivo.
 */
object CanalDeteccion {
    private const val METODOS = "subtrack/deteccion"
    private const val EVENTOS = "subtrack/deteccion/eventos"

    fun registrar(activity: Activity, engine: FlutterEngine) {
        val contexto = activity.applicationContext
        val componente = ComponentName(contexto, LectorNotificacionesService::class.java)

        MethodChannel(engine.dartExecutor.binaryMessenger, METODOS).setMethodCallHandler { call, result ->
            when (call.method) {
                "estado" -> result.success(
                    mapOf(
                        "permiso" to permisoConcedido(activity, componente),
                        "conectado" to LectorNotificacionesService.conectado,
                        "es_debug" to ConfiguracionDeteccion.esDebug(contexto),
                        "modo_descubrimiento" to LectorNotificacionesService.modoDescubrimiento,
                    )
                )
                "abrirAjustesAcceso" -> result.success(abrirAjustesAcceso(activity, componente))
                "reconectar" -> {
                    // Si Android (o MIUI) detuvo el servicio, le pide volver a conectarlo.
                    if (permisoConcedido(activity, componente) && !LectorNotificacionesService.conectado) {
                        NotificationListenerService.requestRebind(componente)
                    }
                    result.success(null)
                }
                "leerCola" -> result.success(ColaNotificaciones.leer(contexto).map { aMapa(it) })
                "borrarDeCola" -> {
                    ColaNotificaciones.borrar(contexto, call.argument<List<String>>("ids").orEmpty())
                    result.success(null)
                }
                "vaciarCola" -> {
                    ColaNotificaciones.vaciar(contexto)
                    result.success(null)
                }
                "configuracion" -> {
                    val config = ConfiguracionDeteccion.de(contexto)
                    result.success(
                        mapOf(
                            "apps_permitidas" to config.appsPermitidas.map { (paquete, nombre) ->
                                mapOf("paquete" to paquete, "nombre" to nombre)
                            },
                            "palabras_cobro" to config.palabrasCobro,
                            "palabras_excluidas" to config.palabrasExcluidas,
                        )
                    )
                }
                "modoDescubrimiento" -> {
                    // Solo en debug; en release siempre queda apagado.
                    LectorNotificacionesService.modoDescubrimiento =
                        ConfiguracionDeteccion.esDebug(contexto) && call.argument<Boolean>("activo") == true
                    result.success(LectorNotificacionesService.modoDescubrimiento)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(engine.dartExecutor.binaryMessenger, EVENTOS).setStreamHandler(
            object : EventChannel.StreamHandler {
                private val principal = Handler(Looper.getMainLooper())

                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                    // El EventSink solo se puede usar desde el hilo principal.
                    LectorNotificacionesService.oyente = { evento -> principal.post { sink.success(evento) } }
                }

                override fun onCancel(arguments: Any?) {
                    LectorNotificacionesService.oyente = null
                }
            }
        )
    }

    /** true si el usuario dio a SubTrack el "Acceso a notificaciones". */
    private fun permisoConcedido(activity: Activity, componente: ComponentName): Boolean {
        val habilitados = Settings.Secure.getString(activity.contentResolver, "enabled_notification_listeners")
            ?: return false
        return habilitados.split(":").any { ComponentName.unflattenFromString(it) == componente }
    }

    private fun abrirAjustesAcceso(activity: Activity, componente: ComponentName): Boolean {
        // Android 11+: abre directamente el ajuste de SubTrack; si no, la lista general.
        val intents = buildList {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                add(
                    Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS)
                        .putExtra(Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME, componente.flattenToString())
                )
            }
            add(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
        }
        for (intent in intents) {
            try {
                activity.startActivity(intent)
                return true
            } catch (e: Exception) {
                // Este celular no tiene esa pantalla: se prueba la siguiente.
            }
        }
        return false
    }
}
