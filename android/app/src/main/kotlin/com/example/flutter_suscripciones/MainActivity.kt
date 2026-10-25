package com.example.flutter_suscripciones

import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Canal que usa RecordatoriosService (lib/services/recordatorios_service.dart)
        // para saber el fabricante y abrir ajustes del sistema.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "subtrack/sistema")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "fabricante" -> result.success(Build.MANUFACTURER)
                    "abrirAjustesApp" -> result.success(abrirAjustesApp())
                    "abrirInicioAutomatico" -> result.success(abrirInicioAutomatico())
                    else -> result.notImplemented()
                }
            }
    }

    // Pantalla "Información de la app": permisos, notificaciones y batería.
    private fun abrirAjustesApp(): Boolean = abrir(
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null))
    )

    // "Inicio automático" de MIUI/HyperOS. Si el celular no la tiene, se
    // abren los ajustes de la app.
    private fun abrirInicioAutomatico(): Boolean {
        val xiaomi = Intent().setComponent(
            ComponentName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity"
            )
        )
        return abrir(xiaomi) || abrirAjustesApp()
    }

    private fun abrir(intent: Intent): Boolean = try {
        startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: Exception) {
        false
    }
}
