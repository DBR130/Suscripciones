package com.example.flutter_suscripciones

import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import com.example.flutter_suscripciones.deteccion.CanalCompartir
import com.example.flutter_suscripciones.deteccion.CanalDeteccion
import com.example.flutter_suscripciones.deteccion.CanalHistorialSms
import com.example.flutter_suscripciones.deteccion.FabricanteSegundoPlano
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Canales del lector de notificaciones (paquete deteccion/).
        CanalDeteccion.registrar(this, flutterEngine)
        // "Buscar suscripciones en mis SMS" (solo hace algo en la versión completa).
        CanalHistorialSms.registrar(this, flutterEngine)
        // Compartir un SMS con SubTrack (las dos versiones).
        CanalCompartir.registrar(flutterEngine, intent)
        // Canal "subtrack/sistema": ajustes de la app (RecordatoriosService) y
        // guía de segundo plano (lib/deteccion/guia_segundo_plano.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "subtrack/sistema")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "abrirAjustesApp" -> result.success(abrirAjustesApp())
                    // Guía de segundo plano (encargo C).
                    "segundoPlano" -> result.success(
                        mapOf(
                            "fabricante" to Build.MANUFACTURER,
                            "grupo" to FabricanteSegundoPlano.grupo(Build.MANUFACTURER),
                            "bateria_sin_restricciones" to bateriaSinRestricciones(),
                        )
                    )
                    "abrirSegundoPlano" -> result.success(abrirSegundoPlano())
                    "abrirBateria" -> result.success(abrirBateria())
                    else -> result.notImplemented()
                }
            }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // Al cerrar la app, el lector deja de enviar eventos a un Flutter que ya no existe.
        CanalDeteccion.liberar()
        CanalHistorialSms.liberar()
        CanalCompartir.liberar()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    // La app ya estaba abierta y el usuario compartió otro SMS con SubTrack.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        CanalCompartir.alRecibirIntent(intent)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (!CanalHistorialSms.alResponderPermiso(requestCode, grantResults)) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }

    // Pantalla "Información de la app": permisos, notificaciones y batería.
    private fun abrirAjustesApp(): Boolean = abrir(
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null))
    )

    // Pantalla de la marca para dejar a SubTrack en segundo plano (autoencendido
    // o inicio automático). Si no existe o no se deja abrir, los ajustes de la
    // app. Con try/catch en vez de resolveActivity: desde Android 11 las
    // actividades de otros paquetes no son visibles sin <queries>, y así es
    // como ya se probó en el Xiaomi.
    private fun abrirSegundoPlano(): Boolean {
        for ((paquete, actividad) in FabricanteSegundoPlano.pantallas(FabricanteSegundoPlano.grupo(Build.MANUFACTURER))) {
            if (abrir(Intent().setComponent(ComponentName(paquete, actividad)))) return true
        }
        return abrirAjustesApp()
    }

    // Lista de "Optimización de batería" del sistema; si no existe, los ajustes
    // de la app. Sin REQUEST_IGNORE_BATTERY_OPTIMIZATIONS (políticas de Google Play).
    private fun abrirBateria(): Boolean =
        abrir(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)) || abrirAjustesApp()

    private fun bateriaSinRestricciones(): Boolean = try {
        (getSystemService(POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(packageName)
    } catch (e: Exception) {
        false
    }

    private fun abrir(intent: Intent): Boolean = try {
        startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: Exception) {
        false
    }
}
