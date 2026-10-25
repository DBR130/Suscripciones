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

/// Gasto mensual de una categoría en una moneda.
class TotalCategoria {
  const TotalCategoria({
    required this.categoria,
    required this.moneda,
    required this.gastoMensual,
    required this.cantidad,
  });

  /// null = sin categoría.
  final String? categoria;
  final String moneda;
  final double gastoMensual;
  final int cantidad;

  factory TotalCategoria.fromJson(Map<String, dynamic> json) => TotalCategoria(
        categoria: json['categoria'] as String?,
        moneda: json['moneda'] as String,
        gastoMensual: (json['gasto_mensual'] as num).toDouble(),
        cantidad: json['cantidad'] as int,
      );
}

/// Respuesta de GET /api/resumen.
class Resumen {
  const Resumen({
    required this.totales,
    this.porCategoria = const [],
    required this.cantidadActivas,
    required this.proximosCobros,
    required this.pruebasPorTerminar,
    required this.diasAnticipacion,
  });

  final List<TotalMoneda> totales;

  /// De mayor a menor gasto, por moneda; "sin categoría" al final.
  final List<TotalCategoria> porCategoria;
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
      porCategoria: (json['por_categoria'] as List? ?? const [])
          .map((c) => TotalCategoria.fromJson(c as Map<String, dynamic>))
          .toList(),
      cantidadActivas: json['cantidad_activas'] as int,
      proximosCobros: lista('proximos_cobros'),
      pruebasPorTerminar: lista('pruebas_por_terminar'),
      diasAnticipacion: json['dias_anticipacion_recordatorio'] as int,
    );
  }
}
