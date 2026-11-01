import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Recibe los textos que el usuario comparte con SubTrack desde otra app
/// (canal "subtrack/compartir", deteccion/CanalCompartir.kt). Fuera de
/// Android no hace nada.
class ReceptorCompartir {
  ReceptorCompartir({bool? plataforma})
      : _plataforma = plataforma ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  final bool _plataforma;

  static const _canal = MethodChannel('subtrack/compartir');

  /// La app ya estaba abierta y llegó un texto nuevo.
  void escuchar(void Function(String texto) alRecibir) {
    if (!_plataforma) return;
    _canal.setMethodCallHandler((call) async {
      if (call.method == 'textoCompartido' && call.arguments is String) alRecibir(call.arguments as String);
    });
  }

  /// El texto con el que se abrió la app, si se abrió compartiendo (una vez).
  Future<String?> textoPendiente() async {
    if (!_plataforma) return null;
    try {
      return await _canal.invokeMethod<String>('textoPendiente');
    } on MissingPluginException {
      return null;
    }
  }
}
