/// Ahorro de una moneda (no se convierten USD a COP).
class TotalAhorro {
  const TotalAhorro({
    required this.moneda,
    required this.anual,
    required this.mensual,
    required this.cantidad,
  });

  final String moneda;
  final double anual;
  final double mensual;
  final int cantidad;

  factory TotalAhorro.fromJson(Map<String, dynamic> json) => TotalAhorro(
        moneda: json['moneda'] as String,
        anual: (json['ahorro_anual'] as num).toDouble(),
        mensual: (json['ahorro_mensual'] as num).toDouble(),
        cantidad: json['cantidad'] as int,
      );
}

/// Una suscripción cancelada con su ahorro proyectado.
class Cancelada {
  const Cancelada({
    required this.id,
    required this.nombreServicio,
    required this.moneda,
    required this.fecha,
    required this.ahorroAnual,
    this.categoria,
  });

  final int id;
  final String nombreServicio;
  final String? categoria;
  final String moneda;
  final DateTime fecha;
  final double ahorroAnual;

  factory Cancelada.fromJson(Map<String, dynamic> json) {
    final partes = (json['fecha_cancelacion'] as String).split('-').map(int.parse).toList();
    return Cancelada(
      id: json['id'] as int,
      nombreServicio: json['nombre_servicio'] as String,
      categoria: json['categoria'] as String?,
      moneda: json['moneda'] as String,
      fecha: DateTime(partes[0], partes[1], partes[2]),
      ahorroAnual: (json['ahorro_proyectado_anual'] as num).toDouble(),
    );
  }
}

/// Gasto de un mes (para la gráfica de evolución).
class GastoMes {
  const GastoMes({required this.mes, required this.total});

  /// Primer día del mes.
  final DateTime mes;
  final double total;
}

/// Serie de 6 meses de una moneda.
class EvolucionMoneda {
  const EvolucionMoneda({required this.moneda, required this.meses});

  final String moneda;
  final List<GastoMes> meses;

  bool get tieneDatos => meses.any((m) => m.total > 0);

  factory EvolucionMoneda.fromJson(Map<String, dynamic> json) => EvolucionMoneda(
        moneda: json['moneda'] as String,
        meses: (json['meses'] as List).map((m) {
          final mapa = m as Map<String, dynamic>;
          final partes = (mapa['mes'] as String).split('-').map(int.parse).toList();
          return GastoMes(
            mes: DateTime(partes[0], partes[1]),
            total: (mapa['total'] as num).toDouble(),
          );
        }).toList(),
      );
}

/// Respuesta de GET /api/ahorro (pantalla 12).
class Ahorro {
  const Ahorro({
    required this.totales,
    required this.canceladas,
    required this.evolucion,
  });

  /// COP primero.
  final List<TotalAhorro> totales;

  /// De la más reciente a la más antigua.
  final List<Cancelada> canceladas;

  /// Una serie por moneda; COP siempre está.
  final List<EvolucionMoneda> evolucion;

  factory Ahorro.fromJson(Map<String, dynamic> json) => Ahorro(
        totales: (json['totales'] as List)
            .map((t) => TotalAhorro.fromJson(t as Map<String, dynamic>))
            .toList(),
        canceladas: (json['canceladas'] as List)
            .map((c) => Cancelada.fromJson(c as Map<String, dynamic>))
            .toList(),
        evolucion: (json['evolucion'] as List)
            .map((e) => EvolucionMoneda.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
