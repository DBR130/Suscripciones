import '../models/suscripcion.dart';

/// Posible suscripción detectada en las notificaciones de pago
/// (GET /api/detecciones/candidatos). El usuario la confirma o la descarta.
class CandidatoSuscripcion {
  const CandidatoSuscripcion({
    required this.id,
    required this.nombre,
    required this.monto,
    required this.moneda,
    required this.frecuencia,
    required this.fechaUltimoPago,
    this.banco = '',
    this.esServicioConocido = false,
    this.numPagos = 1,
  });

  final int id;

  /// Comercio normalizado ("Crunchyroll", "Claude").
  final String nombre;
  final double monto;
  final String moneda;
  final Frecuencia frecuencia;
  final DateTime fechaUltimoPago;
  final String banco;

  /// Está en el catálogo de guías (si no, se detectó por pagos periódicos).
  final bool esServicioConocido;

  /// Cuántos cobros de este comercio se han detectado.
  final int numPagos;

  factory CandidatoSuscripcion.fromJson(Map<String, dynamic> json) => CandidatoSuscripcion(
        id: json['id'] as int,
        nombre: json['comercio_normalizado'] as String,
        monto: (json['monto'] as num).toDouble(),
        moneda: json['moneda'] as String,
        frecuencia: Frecuencia.desde(json['frecuencia_estimada'] as String),
        fechaUltimoPago: DateTime.parse(json['fecha_ultimo_pago'] as String),
        banco: json['banco'] as String? ?? '',
        esServicioConocido: json['es_servicio_conocido'] as bool? ?? false,
        // candidatos_nuevos (al enviar pagos) no trae el conteo.
        numPagos: json['num_pagos'] as int? ?? 1,
      );

  /// "3 cobros detectados" / "1 cobro detectado".
  String get textoCobros => numPagos == 1 ? '1 cobro detectado' : '$numPagos cobros detectados';
}
