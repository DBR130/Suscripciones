import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'analizador_pagos.dart';
import 'huella_pago.dart';
import 'parser_pagos.dart';

/// Pagos interpretados que se quedan en el celular: solo los campos
/// extraídos (banco, comercio, monto, moneda, fecha), nunca el texto.
///
/// Aquí viven las compras puntuales, que no salen hacia el backend (ver
/// [AnalizadorPagos]). Se guardan para poder notar después un patrón
/// recurrente: si el mes siguiente llega otro cobro igual del mismo comercio,
/// los dos se envían. Se borran solos a los [retencion] días (cubre una
/// suscripción anual) y al cerrar sesión.
///
/// Van cifrados en el almacenamiento seguro de Android (el mismo del token).
class AlmacenPagosLocales {
  AlmacenPagosLocales({FlutterSecureStorage? storage, DateTime Function()? ahora})
      : _storage = storage ?? const FlutterSecureStorage(),
        _ahora = ahora ?? DateTime.now;

  final FlutterSecureStorage _storage;
  final DateTime Function() _ahora;

  static const _clave = 'pagos_locales_v1';

  /// Un año y un mes: lo justo para ver dos cobros de una suscripción anual.
  static const retencion = Duration(days: 400);

  /// Tope de pagos guardados (los más recientes).
  static const maximo = 1000;

  /// Las modificaciones se hacen una detrás de otra.
  Future<void> _cola = Future.value();

  Future<List<PagoLocal>> leer() async {
    final texto = await _storage.read(key: _clave);
    if (texto == null || texto.isEmpty) return [];
    try {
      final limite = _ahora().subtract(retencion);
      return (jsonDecode(texto) as List)
          .map((j) => PagoLocal.fromJson(j as Map<String, dynamic>))
          .where((p) => p.pago.fecha.isAfter(limite))
          .toList();
    } on FormatException {
      return []; // dañado: se empieza de nuevo
    }
  }

  /// Agrega los pagos que no estén ya (mismo cobro por otro camino: ver
  /// [AnalizadorPagos.mismoCobro]). [enviados] = ya salieron por otro medio
  /// (por ejemplo, "Compartir"). Devuelve cuántos eran nuevos.
  Future<int> agregar(Iterable<PagoExtraido> pagos, {bool enviados = false}) =>
      _modificar((lista) {
        var nuevos = 0;
        for (final p in pagos) {
          final existente = lista.where((l) => AnalizadorPagos.mismoCobro(l.pago, p)).firstOrNull;
          if (existente == null) {
            lista.add(PagoLocal(p, enviado: enviados));
            nuevos++;
          } else if (enviados) {
            existente.enviado = true;
          }
        }
        return nuevos;
      });

  /// Los que pueden salir del celular ([AnalizadorPagos.seleccionarParaEnviar])
  /// y todavía no se han enviado.
  Future<List<PagoExtraido>> pendientesDeEnviar() async {
    final lista = await leer();
    final enviados = lista.where((l) => l.enviado).map((l) => l.pago).toList();
    return AnalizadorPagos.seleccionarParaEnviar(lista.map((l) => l.pago))
        .where((p) => !enviados.any((e) => AnalizadorPagos.mismoCobro(e, p)))
        .toList();
  }

  Future<void> marcarEnviados(Iterable<PagoExtraido> pagos) => _modificar((lista) {
        for (final l in lista) {
          if (pagos.any((p) => AnalizadorPagos.mismoCobro(l.pago, p))) l.enviado = true;
        }
      });

  /// Al cerrar sesión o eliminar la cuenta: los pagos son de ese usuario.
  Future<void> borrarTodo() => _storage.delete(key: _clave);

  /// Lee, modifica y guarda, uno a la vez (el escaneo y main.dart pueden
  /// coincidir).
  Future<T> _modificar<T>(T Function(List<PagoLocal> lista) cambio) async {
    final anterior = _cola;
    final turno = Completer<void>();
    _cola = turno.future;
    await anterior;
    try {
      final lista = await leer();
      final r = cambio(lista);
      lista.sort((a, b) => b.pago.fecha.compareTo(a.pago.fecha));
      final recortada = lista.take(maximo).toList();
      await _storage.write(key: _clave, value: jsonEncode([for (final l in recortada) l.toJson()]));
      return r;
    } finally {
      turno.complete();
    }
  }
}

/// Un pago guardado en el celular y si ya se envió al backend.
class PagoLocal {
  PagoLocal(this.pago, {this.enviado = false});

  final PagoExtraido pago;
  bool enviado;

  Map<String, Object?> toJson() => {
        'banco': pago.banco,
        'monto': pago.monto,
        'moneda': pago.moneda,
        'comercio_original': pago.comercioOriginal,
        'comercio': pago.comercio,
        'fecha': fechaParaApi(pago.fecha),
        'fecha_del_mensaje': pago.fechaDelMensaje,
        'medio': pago.medio,
        'servicio': pago.servicio,
        'servicio_ambiguo': pago.servicioAmbiguo,
        'procesador': pago.procesador,
        'coincide_precio_referencia': pago.coincidePrecioReferencia,
        'indica_suscripcion': pago.indicaSuscripcion,
        'enviado': enviado,
      };

  factory PagoLocal.fromJson(Map<String, dynamic> j) => PagoLocal(
        PagoExtraido(
          banco: j['banco'] as String,
          monto: (j['monto'] as num).toDouble(),
          moneda: j['moneda'] as String,
          comercioOriginal: j['comercio_original'] as String,
          comercio: j['comercio'] as String,
          fecha: DateTime.parse(j['fecha'] as String),
          fechaDelMensaje: j['fecha_del_mensaje'] as bool? ?? true,
          medio: j['medio'] as String?,
          servicio: j['servicio'] as String?,
          servicioAmbiguo: j['servicio_ambiguo'] as bool? ?? false,
          procesador: j['procesador'] as String?,
          coincidePrecioReferencia: j['coincide_precio_referencia'] as bool? ?? false,
          indicaSuscripcion: j['indica_suscripcion'] as bool? ?? false,
        ),
        enviado: j['enviado'] as bool? ?? false,
      );
}
