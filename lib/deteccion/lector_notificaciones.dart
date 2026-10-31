import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'notificacion_capturada.dart';

/// Puente con el lector nativo de notificaciones (paquete deteccion/ de
/// Android, ver docs/deteccion.md). Fuera de Android (web, tests) no hace
/// nada: [disponible] es false.
class LectorNotificaciones {
  LectorNotificaciones({
    this.metodos = const MethodChannel('subtrack/deteccion'),
    this.eventosCanal = const EventChannel('subtrack/deteccion/eventos'),
    bool? disponible,
  }) : disponible = disponible ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  /// Canales con la parte nativa (se pueden reemplazar en los tests).
  final MethodChannel metodos;
  final EventChannel eventosCanal;

  /// Solo Android tiene el lector.
  final bool disponible;

  Future<EstadoLector> estado() async {
    if (!disponible) return EstadoLector.noDisponible;
    final mapa = await metodos.invokeMapMethod<Object?, Object?>('estado');
    return mapa == null ? EstadoLector.noDisponible : EstadoLector.fromMap(mapa);
  }

  /// Abre los ajustes de "Acceso a notificaciones" del sistema.
  Future<void> abrirAjustesAcceso() async {
    if (disponible) await metodos.invokeMethod<bool>('abrirAjustesAcceso');
  }

  /// Si hay permiso pero Android/MIUI detuvo el servicio, le pide reconectarse.
  Future<void> reconectarSiHaceFalta() async {
    if (!disponible) return;
    try {
      await metodos.invokeMethod<void>('reconectar');
    } on PlatformException catch (e) {
      debugPrint('No se pudo reconectar el lector: $e');
    }
  }

  /// Revisa las notificaciones activas de la barra y guarda en la cola las de
  /// apps permitidas que falten (sin duplicar). Recupera lo que llegó mientras
  /// el servicio estaba detenido. Devuelve cuántas se guardaron, o null si el
  /// servicio no está conectado (en ese caso lo hace solo al conectarse).
  Future<int?> recuperarActivas() async {
    if (!disponible) return null;
    try {
      final n = await metodos.invokeMethod<int>('recuperarActivas');
      return n == null || n < 0 ? null : n;
    } on PlatformException catch (e) {
      debugPrint('No se pudieron recuperar las notificaciones activas: $e');
      return null;
    }
  }

  /// Al abrir la app y al volver a primer plano: reconecta el servicio si
  /// hace falta y recupera lo que haya en la barra.
  Future<void> sincronizar() async {
    await reconectarSiHaceFalta();
    await recuperarActivas();
  }

  /// Notificaciones guardadas mientras la app estaba cerrada (más viejas primero).
  Future<List<NotificacionCapturada>> leerCola() async {
    if (!disponible) return const [];
    final lista = await metodos.invokeListMethod<Map<Object?, Object?>>('leerCola') ?? const [];
    return lista.map(NotificacionCapturada.fromMap).toList();
  }

  /// Quita de la cola las que ya se procesaron.
  Future<void> borrarDeCola(List<String> ids) async {
    if (disponible) await metodos.invokeMethod<void>('borrarDeCola', {'ids': ids});
  }

  Future<void> vaciarCola() async {
    if (disponible) await metodos.invokeMethod<void>('vaciarCola');
  }

  Future<ConfiguracionLector?> configuracion() async {
    if (!disponible) return null;
    final mapa = await metodos.invokeMapMethod<Object?, Object?>('configuracion');
    return mapa == null ? null : ConfiguracionLector.fromMap(mapa);
  }

  /// Solo en debug: informa paquete y título de apps no permitidas (sin texto).
  Future<bool> cambiarModoDescubrimiento(bool activo) async {
    if (!disponible) return false;
    return await metodos.invokeMethod<bool>('modoDescubrimiento', {'activo': activo}) ?? false;
  }

  /// Notificaciones en vivo mientras la app está abierta.
  Stream<EventoDeteccion> eventos() {
    if (!disponible) return const Stream.empty();
    return eventosCanal
        .receiveBroadcastStream()
        .map((e) => EventoDeteccion.fromMap(e as Map<Object?, Object?>));
  }
}
