package com.example.flutter_suscripciones.deteccion

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Canal "subtrack/historial_sms" con lib/deteccion/historial_sms.dart:
 * "Buscar suscripciones en mis SMS". En la versión sinSms responde que no
 * está disponible (LectorHistorialSms de src/sinSms).
 */
object CanalHistorialSms {
    private const val CANAL = "subtrack/historial_sms"
    private const val CODIGO_PERMISO = 4721

    private var pendiente: MethodChannel.Result? = null
    private var actividad: Activity? = null
    private val segundoPlano = Executors.newSingleThreadExecutor()
    private val principal = Handler(Looper.getMainLooper())

    fun registrar(activity: Activity, engine: FlutterEngine) {
        actividad = activity
        val contexto = activity.applicationContext
        MethodChannel(engine.dartExecutor.binaryMessenger, CANAL).setMethodCallHandler { call, result ->
            when (call.method) {
                "disponible" -> result.success(LectorHistorialSms.DISPONIBLE)
                "estadoPermiso" -> result.success(estadoPermiso(activity))
                "pedirPermiso" -> pedirPermiso(activity, result)
                "leer" -> {
                    if (!LectorHistorialSms.permisoConcedido(contexto)) {
                        result.error("sin_permiso", "No hay permiso para leer los SMS", null)
                        return@setMethodCallHandler
                    }
                    val desde = (call.argument<Number>("desde") ?: 0).toLong()
                    // Leer cientos de SMS no debe congelar la pantalla.
                    segundoPlano.execute {
                        try {
                            val lectura = LectorHistorialSms.leer(contexto, desde)
                            principal.post { result.success(lectura) }
                        } catch (e: Exception) {
                            RegistroDeteccion.log(contexto, "No se pudo leer el historial de SMS", e)
                            principal.post { result.error("error_lectura", e.message, null) }
                        }
                    }
                }
                "abrirPermisosApp" -> result.success(abrirPermisosApp(activity))
                else -> result.notImplemented()
            }
        }
    }

    fun liberar() {
        actividad = null
        pendiente = null
    }

    private fun estadoPermiso(activity: Activity): String = when {
        !LectorHistorialSms.DISPONIBLE -> "no_disponible"
        LectorHistorialSms.permisoConcedido(activity) -> "concedido"
        else -> "no_concedido"
    }

    private fun pedirPermiso(activity: Activity, result: MethodChannel.Result) {
        val permiso = LectorHistorialSms.PERMISO
        if (permiso == null) {
            result.success("no_disponible")
            return
        }
        if (LectorHistorialSms.permisoConcedido(activity)) {
            result.success("concedido")
            return
        }
        pendiente?.success("denegado") // una petición anterior sin respuesta
        pendiente = result
        activity.requestPermissions(arrayOf(permiso), CODIGO_PERMISO)
    }

    /** Lo llama MainActivity.onRequestPermissionsResult. Devuelve true si era nuestro. */
    fun alResponderPermiso(codigo: Int, resultados: IntArray): Boolean {
        if (codigo != CODIGO_PERMISO) return false
        val result = pendiente ?: return true
        pendiente = null
        val permiso = LectorHistorialSms.PERMISO
        val respuesta = when {
            resultados.firstOrNull() == PackageManager.PERMISSION_GRANTED -> "concedido"
            // Rechazado y Android ya no volverá a preguntar ("No volver a preguntar"
            // o dos rechazos): solo se puede conceder desde los ajustes.
            permiso != null && actividad?.shouldShowRequestPermissionRationale(permiso) == false -> "bloqueado"
            else -> "denegado"
        }
        result.success(respuesta)
        return true
    }

    /**
     * Permisos de la app. En Xiaomi abre el editor de permisos de MIUI/HyperOS
     * (donde están "SMS" y los permisos propios de Xiaomi, como los SMS de
     * servicio); si no existe, la información de la app.
     */
    private fun abrirPermisosApp(activity: Activity): Boolean {
        val xiaomi = Intent("miui.intent.action.APP_PERM_EDITOR")
            .setComponent(
                ComponentName("com.miui.securitycenter", "com.miui.permcenter.permissions.PermissionsEditorActivity")
            )
            .putExtra("extra_pkgname", activity.packageName)
        val general = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", activity.packageName, null),
        )
        for (intent in listOf(xiaomi, general)) {
            try {
                activity.startActivity(intent)
                return true
            } catch (e: Exception) {
                // No existe en este celular: se prueba la siguiente.
            }
        }
        return false
    }
}
