import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/aviso.dart';
import 'api_client.dart';
import 'suscripcion_service.dart';

/// Cuántos avisos nuevos hay (el número de la campana del encabezado).
///
/// "Nuevo" = un aviso de GET /api/avisos que el usuario no ha visto en la
/// pantalla de Avisos. Los vistos se guardan solo en el celular.
class AvisosNuevos extends ValueNotifier<int> {
  AvisosNuevos(this._servicio, {FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage(),
        super(0);

  final SuscripcionService _servicio;
  final FlutterSecureStorage _storage;

  static const _claveVistos = 'avisos_vistos';

  /// Identifica un aviso aunque cambien sus días restantes.
  static String clave(Aviso a) =>
      '${a.tipo.valor}:${a.suscripcionId}:${a.fecha.toIso8601String().substring(0, 10)}';

  Future<Set<String>> _leerVistos() async {
    try {
      final texto = await _storage.read(key: _claveVistos);
      if (texto == null) return {};
      return (jsonDecode(texto) as List).cast<String>().toSet();
    } catch (e) {
      debugPrint('Avisos vistos: $e');
      return {};
    }
  }

  /// Vuelve a contar con los avisos del backend. Sin conexión deja el número.
  Future<void> actualizar() async {
    try {
      final r = await _servicio.avisos();
      contar(r.avisos, await _leerVistos());
    } on ApiException catch (e) {
      debugPrint('Avisos nuevos: ${e.mensaje}');
    }
  }

  @visibleForTesting
  void contar(List<Aviso> avisos, Set<String> vistos) {
    value = avisos.where((a) => !vistos.contains(clave(a))).length;
  }

  /// Al abrir la pantalla de Avisos: todos los actuales quedan vistos. Solo
  /// se guardan los actuales, así la lista no crece sin fin.
  Future<void> marcarVistos(List<Aviso> avisos) async {
    value = 0;
    try {
      await _storage.write(key: _claveVistos, value: jsonEncode([for (final a in avisos) clave(a)]));
    } catch (e) {
      debugPrint('Avisos vistos: $e');
    }
  }

  /// El [AvisosNuevos] que pone la barra de pestañas, o null fuera de ella.
  static AvisosNuevos? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AvisosNuevosScope>()?.notifier;
}

/// Comparte el contador con las pantallas de las pestañas (y sus campanas).
class AvisosNuevosScope extends InheritedNotifier<AvisosNuevos> {
  const AvisosNuevosScope({super.key, required AvisosNuevos super.notifier, required super.child});
}
