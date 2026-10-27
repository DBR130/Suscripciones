import '../utils/formato.dart';
import 'suscripcion.dart';

enum TipoAviso {
  proximoCobro('proximo_cobro', 'Próximo cobro'),
  finPrueba('fin_prueba_gratis', 'Fin de prueba gratis'),
  cambioPrecio('cambio_precio', 'Cambio de precio');

  const TipoAviso(this.valor, this.etiqueta);

  final String valor;
  final String etiqueta;

  static TipoAviso desde(String valor) => values.firstWhere((t) => t.valor == valor);
}

/// Un aviso de GET /api/avisos (pestaña Avisos, pantalla 11).
class Aviso {
  const Aviso({
    required this.tipo,
    required this.suscripcionId,
    required this.nombreServicio,
    required this.monto,
    required this.moneda,
    required this.frecuencia,
    required this.fecha,
    required this.fechaAviso,
    this.diasRestantes,
    this.montoAnterior,
  });

  final TipoAviso tipo;
  final int suscripcionId;
  final String nombreServicio;
  final double monto;
  final String moneda;
  final Frecuencia frecuencia;

  /// Día del cobro, del fin de la prueba o del cambio de precio.
  final DateTime fecha;

  /// Día en que salió el recordatorio.
  final DateTime fechaAviso;
  final int? diasRestantes;
  final double? montoAnterior;

  factory Aviso.fromJson(Map<String, dynamic> json) => Aviso(
        tipo: TipoAviso.desde(json['tipo'] as String),
        suscripcionId: json['suscripcion_id'] as int,
        nombreServicio: json['nombre_servicio'] as String,
        monto: (json['monto'] as num).toDouble(),
        moneda: json['moneda'] as String,
        frecuencia: Frecuencia.desde(json['frecuencia'] as String),
        fecha: Formato.leerFechaApi(json['fecha'] as String),
        fechaAviso: Formato.leerFechaApi(json['fecha_aviso'] as String),
        diasRestantes: json['dias_restantes'] as int?,
        montoAnterior: (json['monto_anterior'] as num?)?.toDouble(),
      );

  String get _monto => Formato.moneda(monto, moneda);

  /// "Netflix se cobra en 3 días"
  String get titulo => switch (tipo) {
        TipoAviso.proximoCobro => '$nombreServicio se cobra ${Formato.enDias(diasRestantes ?? 0)}',
        TipoAviso.finPrueba => 'Tu prueba de $nombreServicio termina ${Formato.enDias(diasRestantes ?? 0)}',
        TipoAviso.cambioPrecio => (montoAnterior ?? 0) <= monto
            ? '$nombreServicio subió de precio'
            : '$nombreServicio bajó de precio',
      };

  /// "$38.900 el 20 de septiembre."
  String get cuerpo => switch (tipo) {
        TipoAviso.proximoCobro => '$_monto el ${Formato.fechaLarga(fecha)}.',
        TipoAviso.finPrueba => 'El ${Formato.fechaLarga(fecha)} pasa a $_monto${frecuencia.sufijo}.',
        TipoAviso.cambioPrecio =>
          'De ${Formato.moneda(montoAnterior ?? 0, moneda)} a $_monto${frecuencia.sufijo}.',
      };
}
