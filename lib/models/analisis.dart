import '../utils/formato.dart';
import 'ahorro.dart';
import 'resumen.dart';
import 'suscripcion.dart';

/// Un cobro de los próximos 30 días (una semanal aparece varias veces).
class CobroProximo {
  const CobroProximo({
    required this.suscripcionId,
    required this.nombreServicio,
    required this.monto,
    required this.moneda,
    required this.fecha,
    required this.diasRestantes,
    this.finDePrueba = false,
  });

  final int suscripcionId;
  final String nombreServicio;
  final double monto;
  final String moneda;
  final DateTime fecha;
  final int diasRestantes;

  /// Es el día en que una prueba gratis pasa a pago.
  final bool finDePrueba;

  factory CobroProximo.fromJson(Map<String, dynamic> json) => CobroProximo(
        suscripcionId: json['suscripcion_id'] as int,
        nombreServicio: json['nombre_servicio'] as String,
        monto: (json['monto'] as num).toDouble(),
        moneda: json['moneda'] as String,
        fecha: Formato.leerFechaApi(json['fecha'] as String),
        diasRestantes: json['dias_restantes'] as int,
        finDePrueba: json['fin_de_prueba'] as bool? ?? false,
      );
}

/// Una de las suscripciones más caras (por gasto mensual equivalente).
class SuscripcionCara {
  const SuscripcionCara({
    required this.id,
    required this.nombreServicio,
    required this.moneda,
    required this.monto,
    required this.frecuencia,
    required this.gastoMensual,
    this.categoria,
  });

  final int id;
  final String nombreServicio;
  final String? categoria;
  final String moneda;
  final double monto;
  final Frecuencia frecuencia;
  final double gastoMensual;

  factory SuscripcionCara.fromJson(Map<String, dynamic> json) => SuscripcionCara(
        id: json['id'] as int,
        nombreServicio: json['nombre_servicio'] as String,
        categoria: json['categoria'] as String?,
        moneda: json['moneda'] as String,
        monto: (json['monto'] as num).toDouble(),
        frecuencia: Frecuencia.desde(json['frecuencia'] as String),
        gastoMensual: (json['gasto_mensual'] as num).toDouble(),
      );
}

/// Respuesta de GET /api/analisis (pestaña Análisis).
class Analisis {
  const Analisis({
    required this.totales,
    required this.cantidadActivas,
    required this.gastoMensual,
    required this.porCategoria,
    required this.proximosCobros,
    required this.masCaras,
    required this.ahorroTotales,
    required this.canceladas,
  });

  /// Gasto mensual y proyección anual por moneda (COP primero).
  final List<TotalMoneda> totales;
  final int cantidadActivas;

  /// Lo pagado en los últimos 6 meses, una serie por moneda.
  final List<EvolucionMoneda> gastoMensual;
  final List<TotalCategoria> porCategoria;
  final List<CobroProximo> proximosCobros;
  final List<SuscripcionCara> masCaras;
  final List<TotalAhorro> ahorroTotales;
  final List<Cancelada> canceladas;

  /// Sin suscripciones, pagos ni cancelaciones: estado vacío.
  bool get vacio =>
      cantidadActivas == 0 && canceladas.isEmpty && !gastoMensual.any((s) => s.tieneDatos);

  /// Monedas que aparecen en las gráficas, COP primero.
  List<String> get monedas {
    final todas = {
      ...totales.map((t) => t.moneda),
      ...gastoMensual.where((s) => s.tieneDatos).map((s) => s.moneda),
    };
    if (todas.isEmpty) return const ['COP'];
    return [if (todas.contains('COP')) 'COP', ...todas.where((m) => m != 'COP').toList()..sort()];
  }

  factory Analisis.fromJson(Map<String, dynamic> json) {
    List<T> lista<T>(Object? valor, T Function(Map<String, dynamic>) leer) =>
        (valor as List? ?? const []).map((e) => leer(e as Map<String, dynamic>)).toList();
    final ahorro = json['ahorro'] as Map<String, dynamic>? ?? const {};
    return Analisis(
      totales: lista(json['totales'], TotalMoneda.fromJson),
      cantidadActivas: json['cantidad_activas'] as int? ?? 0,
      gastoMensual: lista(json['gasto_mensual'], EvolucionMoneda.fromJson),
      porCategoria: lista(json['por_categoria'], TotalCategoria.fromJson),
      proximosCobros: lista(json['proximos_cobros'], CobroProximo.fromJson),
      masCaras: lista(json['mas_caras'], SuscripcionCara.fromJson),
      ahorroTotales: lista(ahorro['totales'], TotalAhorro.fromJson),
      canceladas: lista(ahorro['canceladas'], Cancelada.fromJson),
    );
  }
}
