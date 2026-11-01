import 'package:flutter/foundation.dart';

import 'lector_notificaciones.dart';
import 'notificacion_capturada.dart';

/// Estado real de la detección: tener el permiso no basta, el lector además
/// debe estar conectado. HyperOS a veces no lo reconecta después de
/// reinstalar o actualizar la app (ver docs/deteccion.md).
enum EstadoDeteccion {
  /// Fuera de Android (web, escritorio, tests sin lector).
  noDisponible,

  /// El usuario no dio el "Acceso a notificaciones".
  sinPermiso,

  /// Permiso concedido y lector desconectado: se está intentando reconectar.
  comprobando,

  /// Permiso concedido y lector conectado: detecta cobros.
  activa,

  /// Permiso concedido, pero el lector no se reconectó tras los intentos.
  /// Solo se arregla apagando y encendiendo el acceso en los ajustes.
  pausada,
}

/// Regla del estado. [esperaTerminada]: ya pasaron los intentos de reconexión.
EstadoDeteccion estadoDeteccion(EstadoLector e, {required bool esperaTerminada}) {
  if (!e.permiso) return EstadoDeteccion.sinPermiso;
  if (e.conectado) return EstadoDeteccion.activa;
  return esperaTerminada ? EstadoDeteccion.pausada : EstadoDeteccion.comprobando;
}

/// Comprueba el estado real de la detección y lo publica en [estado] para
/// Perfil, el dashboard y la pantalla de permisos. Lo llama main.dart al abrir
/// la app y al volver a primer plano.
class VigilanteDeteccion {
  VigilanteDeteccion(
    this.lector, {
    this.espera = const Duration(seconds: 9),
    this.intervalo = const Duration(milliseconds: 500),
  }) : estado = ValueNotifier(lector.disponible ? EstadoDeteccion.comprobando : EstadoDeteccion.noDisponible);

  final LectorNotificaciones lector;

  /// Cuánto se espera a que la reconexión nativa funcione antes de declarar
  /// la detección pausada (la secuencia nativa dura unos 6 s).
  final Duration espera;
  final Duration intervalo;

  final ValueNotifier<EstadoDeteccion> estado;

  Future<EstadoDeteccion>? _enCurso;

  /// Si ya hay una comprobación en curso, devuelve esa misma.
  Future<EstadoDeteccion> verificar({String motivo = 'app abierta'}) =>
      _enCurso ??= _verificar(motivo).whenComplete(() => _enCurso = null);

  Future<EstadoDeteccion> _verificar(String motivo) async {
    if (!lector.disponible) return estado.value = EstadoDeteccion.noDisponible;

    final inicial = estadoDeteccion(await lector.estado(), esperaTerminada: false);
    if (inicial != EstadoDeteccion.comprobando) return estado.value = inicial;

    // Permiso sí, lector no: reconexión nativa (requestRebind y, si no basta,
    // reiniciar el componente) y esperar a ver si conecta.
    estado.value = EstadoDeteccion.comprobando;
    await lector.reconectarSiHaceFalta(motivo: motivo);
    final intentos = (espera.inMilliseconds / intervalo.inMilliseconds).ceil();
    for (var i = 0; i < intentos; i++) {
      await Future<void>.delayed(intervalo);
      final r = estadoDeteccion(await lector.estado(), esperaTerminada: false);
      if (r != EstadoDeteccion.comprobando) return estado.value = r;
    }
    return estado.value = EstadoDeteccion.pausada;
  }
}
