import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'notificacion_capturada.dart';

/// Respuesta al pedir el permiso de leer SMS.
enum PermisoSms {
  concedido,

  /// Rechazado: se puede volver a pedir.
  denegado,

  /// Rechazado y Android ya no vuelve a preguntar: solo desde los ajustes.
  bloqueado,

  /// Versión sinSms, o fuera de Android.
  noDisponible,
}

/// Lo que devolvió la lectura del historial: solo los SMS que parecen
/// cobros (el resto se descartó en la parte nativa) y dos conteos.
class LecturaHistorial {
  const LecturaHistorial({required this.mensajes, required this.leidos, required this.deEmpresas});

  /// Como notificaciones, para pasarlas por el mismo parser.
  final List<NotificacionCapturada> mensajes;

  /// SMS recibidos que se revisaron.
  final int leidos;

  /// De ellos, cuántos vienen de remitentes de empresa (números cortos o
  /// nombres). 0 con SMS leídos hace sospechar que Xiaomi oculta los SMS de
  /// servicio.
  final int deEmpresas;
}

/// Puente con la búsqueda en el historial de SMS (canal "subtrack/historial_sms",
/// deteccion/CanalHistorialSms.kt). Solo existe en la versión "completa" de
/// Android: en la versión "sinSms", en web y en los tests sin simulación,
/// [disponible] responde false y la opción no se muestra.
class HistorialSms {
  HistorialSms({bool? plataforma})
      : _plataforma = plataforma ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  final bool _plataforma;

  static const _canal = MethodChannel('subtrack/historial_sms');

  /// Una sola revisión de los últimos 6 meses.
  static const meses = 6;

  bool? _disponible;

  Future<bool> disponible() async {
    if (!_plataforma) return false;
    try {
      return _disponible ??= await _canal.invokeMethod<bool>('disponible') ?? false;
    } on MissingPluginException {
      return _disponible = false;
    }
  }

  Future<bool> permisoConcedido() async {
    if (!await disponible()) return false;
    return await _canal.invokeMethod<String>('estadoPermiso') == 'concedido';
  }

  /// Muestra el diálogo de Android (si hace falta).
  Future<PermisoSms> pedirPermiso() async {
    if (!await disponible()) return PermisoSms.noDisponible;
    return switch (await _canal.invokeMethod<String>('pedirPermiso')) {
      'concedido' => PermisoSms.concedido,
      'bloqueado' => PermisoSms.bloqueado,
      'no_disponible' => PermisoSms.noDisponible,
      _ => PermisoSms.denegado,
    };
  }

  /// SMS recibidos desde [desde] que parecen cobros.
  Future<LecturaHistorial> leer(DateTime desde) async {
    final r = await _canal.invokeMapMethod<String, Object?>('leer', {'desde': desde.millisecondsSinceEpoch});
    final mensajes = [
      for (final m in (r?['mensajes'] as List? ?? const []).cast<Map<Object?, Object?>>())
        NotificacionCapturada(
          id: m['id'] as String,
          paquete: 'sms',
          app: 'Historial de SMS',
          titulo: '',
          texto: m['texto'] as String,
          // La fecha del SMS: se usa cuando el texto no trae la suya (Nequi).
          recibidaEn: DateTime.fromMillisecondsSinceEpoch((m['fecha'] as num).toInt()),
        ),
    ];
    return LecturaHistorial(
      mensajes: mensajes,
      leidos: (r?['leidos'] as num? ?? 0).toInt(),
      deEmpresas: (r?['de_empresas'] as num? ?? 0).toInt(),
    );
  }

  /// Permisos de la app (en Xiaomi, el editor de permisos de MIUI/HyperOS).
  Future<void> abrirPermisosApp() => _canal.invokeMethod('abrirPermisosApp');
}
