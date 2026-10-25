import '../utils/formato.dart';

enum Frecuencia {
  semanal('semanal', 'Semanal', '/semana', 52),
  mensual('mensual', 'Mensual', '/mes', 12),
  anual('anual', 'Anual', '/año', 1);

  const Frecuencia(this.valor, this.etiqueta, this.sufijo, this.cobrosPorAnio);

  /// Texto que usa el backend.
  final String valor;
  final String etiqueta;

  /// Se muestra junto al monto: "$ 38.900 /mes".
  final String sufijo;
  final int cobrosPorAnio;

  static Frecuencia desde(String valor) =>
      values.firstWhere((f) => f.valor == valor);
}

enum EstadoSuscripcion {
  activa('activa', 'Activa'),
  marcadaParaCancelar('marcada_para_cancelar', 'Marcada para cancelar'),
  cancelada('cancelada', 'Cancelada');

  const EstadoSuscripcion(this.valor, this.etiqueta);

  final String valor;
  final String etiqueta;

  static EstadoSuscripcion desde(String valor) =>
      values.firstWhere((e) => e.valor == valor);
}

/// Una suscripción del usuario, tal como la maneja el backend.
class Suscripcion {
  const Suscripcion({
    this.id,
    required this.nombreServicio,
    this.categoria,
    required this.monto,
    this.moneda = 'COP',
    required this.frecuencia,
    required this.fechaProximoCobro,
    this.esPruebaGratis = false,
    this.fechaFinPrueba,
    this.diasAviso,
    this.origen = 'manual',
    this.estado = EstadoSuscripcion.activa,
    this.fechaDeteccion,
    this.creadoEn,
  });

  /// Categorías permitidas (mismo CHECK que la migración 003 del backend).
  static const List<String> categorias = [
    'Streaming',
    'Música',
    'Cloud gaming',
    'Almacenamiento',
    'Gimnasio',
    'Software',
    'Diseño',
  ];

  /// null mientras no se ha guardado en el servidor.
  final int? id;
  final String nombreServicio;

  /// Una de [categorias], o null si no tiene.
  final String? categoria;
  final double monto;
  final String moneda;
  final Frecuencia frecuencia;
  final DateTime fechaProximoCobro;
  final bool esPruebaGratis;
  final DateTime? fechaFinPrueba;

  /// null = usar la preferencia global del usuario.
  final int? diasAviso;
  final String origen;
  final EstadoSuscripcion estado;
  final DateTime? fechaDeteccion;
  final DateTime? creadoEn;

  factory Suscripcion.fromJson(Map<String, dynamic> json) {
    final finPrueba = json['fecha_fin_prueba'] as String?;
    final deteccion = json['fecha_deteccion'] as String?;
    final creadoEn = json['creado_en'] as String?;
    return Suscripcion(
      id: json['id'] as int,
      nombreServicio: json['nombre_servicio'] as String,
      categoria: json['categoria'] as String?,
      monto: (json['monto'] as num).toDouble(),
      moneda: json['moneda'] as String,
      frecuencia: Frecuencia.desde(json['frecuencia'] as String),
      fechaProximoCobro:
          Formato.leerFechaApi(json['fecha_proximo_cobro'] as String),
      esPruebaGratis: json['es_prueba_gratis'] as bool,
      fechaFinPrueba: finPrueba == null ? null : Formato.leerFechaApi(finPrueba),
      diasAviso: json['dias_aviso'] as int?,
      origen: json['origen'] as String,
      estado: EstadoSuscripcion.desde(json['estado'] as String),
      fechaDeteccion: deteccion == null ? null : DateTime.parse(deteccion).toLocal(),
      creadoEn: creadoEn == null ? null : DateTime.parse(creadoEn).toLocal(),
    );
  }

  /// Campos que se envían al crear o editar (el estado se cambia aparte).
  Map<String, dynamic> toJson() => {
        'nombre_servicio': nombreServicio,
        'categoria': categoria,
        'monto': monto,
        'moneda': moneda,
        'frecuencia': frecuencia.valor,
        'fecha_proximo_cobro': Formato.fechaApi(fechaProximoCobro),
        'es_prueba_gratis': esPruebaGratis,
        'fecha_fin_prueba':
            fechaFinPrueba == null ? null : Formato.fechaApi(fechaFinPrueba!),
        'dias_aviso': diasAviso,
      };

  /// Copia con otros días de aviso (el selector del detalle).
  Suscripcion conDiasAviso(int? dias) => Suscripcion(
        id: id,
        nombreServicio: nombreServicio,
        categoria: categoria,
        monto: monto,
        moneda: moneda,
        frecuencia: frecuencia,
        fechaProximoCobro: fechaProximoCobro,
        esPruebaGratis: esPruebaGratis,
        fechaFinPrueba: fechaFinPrueba,
        diasAviso: dias,
        origen: origen,
        estado: estado,
        fechaDeteccion: fechaDeteccion,
        creadoEn: creadoEn,
      );

  /// Fecha que importa en el dashboard: fin de la prueba o próximo cobro.
  DateTime get fechaClave =>
      esPruebaGratis && fechaFinPrueba != null ? fechaFinPrueba! : fechaProximoCobro;

  /// Días desde [hoy] hasta [fechaClave] (negativo si ya pasó).
  int diasHasta(DateTime hoy) {
    final desde = DateTime.utc(hoy.year, hoy.month, hoy.day);
    final hasta = DateTime.utc(fechaClave.year, fechaClave.month, fechaClave.day);
    return hasta.difference(desde).inDays;
  }

  /// Días de aviso efectivos: los propios o la preferencia global.
  int diasAvisoEfectivos(int diasGlobales) => diasAviso ?? diasGlobales;

  /// "Desde" del detalle: cuándo se detectó o, si fue manual, cuándo se creó.
  DateTime? get desde => fechaDeteccion ?? creadoEn;

  String get montoTexto => Formato.moneda(monto, moneda);
}

/// Un pago del historial (tabla historial_pagos).
class Pago {
  const Pago({required this.fecha, required this.monto});

  final DateTime fecha;
  final double monto;

  factory Pago.fromJson(Map<String, dynamic> json) => Pago(
        fecha: Formato.leerFechaApi(json['fecha_pago'] as String),
        monto: (json['monto'] as num).toDouble(),
      );
}

/// Respuesta de GET /api/suscripciones/:id: la suscripción, sus 3 últimos
/// pagos y el total pagado.
class DetalleSuscripcion {
  const DetalleSuscripcion({
    required this.suscripcion,
    this.pagos = const [],
    this.pagadoTotal = 0,
  });

  final Suscripcion suscripcion;
  final List<Pago> pagos;
  final double pagadoTotal;

  factory DetalleSuscripcion.fromJson(Map<String, dynamic> json) =>
      DetalleSuscripcion(
        suscripcion: Suscripcion.fromJson(json['suscripcion'] as Map<String, dynamic>),
        pagos: (json['pagos'] as List? ?? const [])
            .map((p) => Pago.fromJson(p as Map<String, dynamic>))
            .toList(),
        pagadoTotal: (json['pagado_total'] as num? ?? 0).toDouble(),
      );
}
