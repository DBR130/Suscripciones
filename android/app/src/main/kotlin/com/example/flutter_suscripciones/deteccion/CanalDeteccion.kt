package com.example.flutter_suscripciones.deteccion

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
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
        val componente = ReconexionLector.componente(contexto)

        MethodChannel(engine.dartExecutor.binaryMessenger, METODOS).setMethodCallHandler { call, result ->
            when (call.method) {
                "estado" -> {
                    // Flutter pide el estado al abrir la app y al volver a ella:
                    // buen momento para notar si el usuario cambió de app de SMS.
                    val appSms = AppSmsPredeterminada.actualizar(contexto, "app abierta")
                    result.success(
                        mapOf(
                            "permiso" to ReconexionLector.permisoConcedido(contexto),
                            "conectado" to LectorNotificacionesService.conectado,
                            "es_debug" to ConfiguracionDeteccion.esDebug(contexto),
                            "modo_descubrimiento" to LectorNotificacionesService.modoDescubrimiento,
                            "app_sms_paquete" to appSms,
                            "app_sms_nombre" to appSms?.let { AppSmsPredeterminada.nombre(contexto, it) },
                        ) + RegistroDeteccion.leer(contexto)
                    )
                }
                "abrirAjustesAcceso" -> result.success(abrirAjustesAcceso(activity, componente))
                "reconectar" -> {
                    // Permiso concedido pero lector desconectado (MIUI lo detuvo, o
                    // Android no lo reenlazó tras actualizar la app): reconexión
                    // escalonada, ver ReconexionLector. Responde enseguida; Flutter
                    // consulta "estado" para saber si funcionó.
                    if (!LectorNotificacionesService.conectado) {
                        val motivo = call.argument<String>("motivo") ?: "desde la app"
                        RegistroDeteccion.log(contexto, "App con el lector desconectado ($motivo): se intenta reconectar")
                        ReconexionLector.reconectar(contexto, motivo)
                    }
                    result.success(null)
                }
                // Recupera de la barra lo que llegó con el servicio detenido.
                // -1 = el servicio no está conectado (se hará solo al conectarse).
                "recuperarActivas" -> result.success(LectorNotificacionesService.recuperarActivasSiConectado() ?: -1)
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
                // Solo existe en debug: en release responde "no implementado" y
                // el modo queda siempre apagado.
                "modoDescubrimiento" -> if (ConfiguracionDeteccion.esDebug(contexto)) {
                    LectorNotificacionesService.modoDescubrimiento = call.argument<Boolean>("activo") == true
                    result.success(LectorNotificacionesService.modoDescubrimiento)
                } else {
                    result.notImplemented()
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(engine.dartExecutor.binaryMessenger, EVENTOS).setStreamHandler(
            object : EventChannel.StreamHandler {
                private val principal = Handler(Looper.getMainLooper())

                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                    // El EventSink solo se puede usar desde el hilo principal. Si
                    // Flutter ya no está (app cerrada), el error se atrapa aquí: un
                    // evento en vivo nunca debe tumbar el proceso ni el servicio.
                    LectorNotificacionesService.oyente = { evento ->
                        principal.post {
                            try {
                                sink.success(evento)
                            } catch (e: Exception) {
                                RegistroDeteccion.log(contexto, "Flutter no está escuchando; se descarta el evento en vivo", e)
                                LectorNotificacionesService.oyente = null
                            }
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    LectorNotificacionesService.oyente = null
                }
            }
        )
    }

    /** Lo llama MainActivity cuando se destruye el motor de Flutter. */
    fun liberar() {
        LectorNotificacionesService.oyente = null
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
