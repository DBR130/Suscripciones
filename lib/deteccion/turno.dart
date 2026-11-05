import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Turno para procesar la cola de cobros (candado nativo TurnoDeteccion.kt).
///
/// La app y la tarea de fondo de WorkManager corren en motores de Flutter
/// distintos del mismo proceso: el candado nativo es común a los dos, así
/// nunca procesan la misma cola a la vez.
///
/// - Procesamiento automático (la tarea de fondo, la app al abrirse o volver):
///   un solo intento; si está ocupado, no procesa.
/// - Acción del usuario ("Buscar en mis SMS", "Compartir"): espera el turno
///   hasta [esperar] y, si no lo consigue, la pantalla lo dice.
class Turno {
  Turno(this.quien, {bool? disponible, this.intervalo = const Duration(seconds: 1)})
      : _disponible = disponible ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  /// "app" o "fondo".
  final String quien;
  final bool _disponible;

  /// Cada cuánto se vuelve a preguntar mientras se espera.
  final Duration intervalo;

  /// Lo que espera una acción del usuario antes de rendirse.
  static const esperaUsuario = Duration(seconds: 90);

  static const _canal = MethodChannel('subtrack/deteccion');

  /// true si consiguió el turno, intentando hasta [esperar] (por defecto, una
  /// sola vez).
  Future<bool> tomar({Duration esperar = Duration.zero}) async {
    if (!_disponible) return true;
    final limite = DateTime.now().add(esperar);
    while (true) {
      if (await _canal.invokeMethod<bool>('tomarTurno', {'quien': quien}) == true) return true;
      if (!DateTime.now().add(intervalo).isBefore(limite)) return false;
      await Future<void>.delayed(intervalo);
    }
  }

  Future<void> soltar() async {
    if (!_disponible) return;
    await _canal.invokeMethod<void>('soltarTurno', {'quien': quien});
  }
}
