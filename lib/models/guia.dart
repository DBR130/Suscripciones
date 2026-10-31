/// Guía de cancelación de un servicio (catálogo del backend, pantalla 10).
class Guia {
  const Guia({
    required this.nombreServicio,
    required this.pasos,
    this.enlaceDirecto,
    this.duracionMinutos,
    this.esGenerica = false,
  });

  final String nombreServicio;
  final List<String> pasos;

  /// Página oficial de cuenta o ayuda del proveedor, si la hay.
  final String? enlaceDirecto;
  final int? duracionMinutos;

  /// true para "Otro servicio" (no hay una guía específica).
  final bool esGenerica;

  factory Guia.fromJson(Map<String, dynamic> json) => Guia(
        nombreServicio: json['nombre_servicio'] as String,
        pasos: (json['pasos'] as List).cast<String>(),
        enlaceDirecto: json['enlace_directo'] as String?,
        duracionMinutos: json['duracion_minutos'] as int?,
        esGenerica: json['es_generica'] as bool? ?? false,
      );

  /// "4 pasos · unos 3 minutos"
  String get resumen {
    final pasosTexto = pasos.length == 1 ? '1 paso' : '${pasos.length} pasos';
    if (duracionMinutos == null) return pasosTexto;
    final minutos = duracionMinutos == 1 ? '1 minuto' : '$duracionMinutos minutos';
    return '$pasosTexto · unos $minutos';
  }
}

/// Respuesta de GET /api/suscripciones/:id/guia.
class GuiaDeSuscripcion {
  const GuiaDeSuscripcion({
    required this.suscripcionId,
    required this.nombreServicio,
    required this.guia,
    required this.esGenerica,
  });

  final int suscripcionId;

  /// Nombre de la suscripción tal como la escribió el usuario.
  final String nombreServicio;
  final Guia guia;
  final bool esGenerica;

  factory GuiaDeSuscripcion.fromJson(Map<String, dynamic> json) {
    final suscripcion = json['suscripcion'] as Map<String, dynamic>;
    return GuiaDeSuscripcion(
      suscripcionId: suscripcion['id'] as int,
      nombreServicio: suscripcion['nombre_servicio'] as String,
      guia: Guia.fromJson(json['guia'] as Map<String, dynamic>),
      esGenerica: json['es_generica'] as bool,
    );
  }
}
