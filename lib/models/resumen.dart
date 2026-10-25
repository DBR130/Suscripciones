import 'suscripcion.dart';

/// Totales de una moneda (no se convierten USD a COP).
class TotalMoneda {
  const TotalMoneda({
    required this.moneda,
    required this.gastoMensual,
    required this.proyeccionAnual,
    required this.cantidad,
  });

  final String moneda;
  final double gastoMensual;
  final double proyeccionAnual;
  final int cantidad;

  factory TotalMoneda.fromJson(Map<String, dynamic> json) => TotalMoneda(
        moneda: json['moneda'] as String,
        gastoMensual: (json['gasto_mensual'] as num).toDouble(),
        proyeccionAnual: (json['proyeccion_anual'] as num).toDouble(),
        cantidad: json['cantidad'] as int,
      );
}

/// Respuesta de GET /api/resumen.
class Resumen {
  const Resumen({
    required this.totales,
    required this.cantidadActivas,
    required this.proximosCobros,
    required this.pruebasPorTerminar,
    required this.diasAnticipacion,
  });

  final List<TotalMoneda> totales;
  final int cantidadActivas;
  final List<Suscripcion> proximosCobros;
  final List<Suscripcion> pruebasPorTerminar;
  final int diasAnticipacion;

  factory Resumen.fromJson(Map<String, dynamic> json) {
    List<Suscripcion> lista(String clave) => (json[clave] as List)
        .map((s) => Suscripcion.fromJson(s as Map<String, dynamic>))
        .toList();
    return Resumen(
      totales: (json['totales'] as List)
          .map((t) => TotalMoneda.fromJson(t as Map<String, dynamic>))
          .toList(),
      cantidadActivas: json['cantidad_activas'] as int,
      proximosCobros: lista('proximos_cobros'),
      pruebasPorTerminar: lista('pruebas_por_terminar'),
      diasAnticipacion: json['dias_anticipacion_recordatorio'] as int,
    );
  }
}
