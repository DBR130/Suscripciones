/// Una notificación que el lector nativo guardó porque parece un cobro.
/// El texto crudo solo vive en el celular: al backend se envían los campos
/// que extraiga el parser (hito 2), nunca este texto.
class NotificacionCapturada {
  const NotificacionCapturada({
    required this.id,
    required this.paquete,
    required this.app,
    required this.titulo,
    required this.texto,
    required this.recibidaEn,
  });

  /// Huella SHA-256 (paquete, título, texto, hora): identifica la notificación.
  final String id;

  /// Paquete de la app que la publicó (por ejemplo, la app de SMS).
  final String paquete;

  /// Nombre legible según res/raw/deteccion_apps.json.
  final String app;
  final String titulo;
  final String texto;
  final DateTime recibidaEn;

  factory NotificacionCapturada.fromMap(Map<Object?, Object?> mapa) => NotificacionCapturada(
        id: mapa['id'] as String,
        paquete: mapa['paquete'] as String,
        app: mapa['app'] as String? ?? mapa['paquete'] as String,
        titulo: mapa['titulo'] as String? ?? '',
        texto: mapa['texto'] as String? ?? '',
        recibidaEn: DateTime.fromMillisecondsSinceEpoch((mapa['recibida_en'] as num).toInt()),
      );
}

enum TipoEvento {
  /// Parecía un cobro y quedó en la cola.
  guardada,

  /// App permitida, pero el texto no parecía un cobro (no se guardó).
  descartada,

  /// App no permitida (solo en modo descubrimiento): solo el paquete, sin
  /// título ni texto.
  descubierta,
}

/// Evento en vivo del lector (EventChannel), mientras la app está abierta.
class EventoDeteccion {
  const EventoDeteccion({
    required this.tipo,
    required this.paquete,
    required this.recibidaEn,
    this.notificacion,
    this.motivo,
  });

  final TipoEvento tipo;
  final String paquete;
  final DateTime recibidaEn;

  /// Solo en [TipoEvento.guardada].
  final NotificacionCapturada? notificacion;

  /// Solo en [TipoEvento.descartada]: por qué no se guardó.
  final String? motivo;

  factory EventoDeteccion.fromMap(Map<Object?, Object?> mapa) {
    final tipo = TipoEvento.values.byName(mapa['tipo'] as String);
    if (tipo == TipoEvento.guardada) {
      final n = NotificacionCapturada.fromMap(mapa['notificacion'] as Map<Object?, Object?>);
      return EventoDeteccion(
        tipo: tipo,
        paquete: n.paquete,
        recibidaEn: n.recibidaEn,
        notificacion: n,
      );
    }
    return EventoDeteccion(
      tipo: tipo,
      paquete: mapa['paquete'] as String,
      recibidaEn: DateTime.fromMillisecondsSinceEpoch((mapa['recibida_en'] as num).toInt()),
      motivo: mapa['motivo'] as String?,
    );
  }
}

/// Estado del lector en el celular.
class EstadoLector {
  const EstadoLector({
    required this.permiso,
    required this.conectado,
    required this.esDebug,
    required this.modoDescubrimiento,
    this.ultimaConexion,
    this.ultimaDesconexion,
    this.ultimaNotificacion,
    this.ultimoResultado,
  });

  /// El usuario dio el "Acceso a notificaciones".
  final bool permiso;

  /// Android mantiene el servicio conectado (puede ser false si MIUI lo detuvo).
  final bool conectado;
  final bool esDebug;
  final bool modoDescubrimiento;

  /// Horas guardadas por el servicio (sobreviven si Android mata el proceso).
  final DateTime? ultimaConexion;
  final DateTime? ultimaDesconexion;

  /// Última notificación que recibió el servicio, de cualquier app.
  final DateTime? ultimaNotificacion;

  /// "guardada", "repetida", "descartada" o "app no permitida".
  final String? ultimoResultado;

  EstadoLector conDescubrimiento(bool activo) => EstadoLector(
        permiso: permiso,
        conectado: conectado,
        esDebug: esDebug,
        modoDescubrimiento: activo,
        ultimaConexion: ultimaConexion,
        ultimaDesconexion: ultimaDesconexion,
        ultimaNotificacion: ultimaNotificacion,
        ultimoResultado: ultimoResultado,
      );

  static const noDisponible =
      EstadoLector(permiso: false, conectado: false, esDebug: false, modoDescubrimiento: false);

  factory EstadoLector.fromMap(Map<Object?, Object?> mapa) => EstadoLector(
        permiso: mapa['permiso'] as bool? ?? false,
        conectado: mapa['conectado'] as bool? ?? false,
        esDebug: mapa['es_debug'] as bool? ?? false,
        modoDescubrimiento: mapa['modo_descubrimiento'] as bool? ?? false,
        ultimaConexion: _fecha(mapa['ultima_conexion']),
        ultimaDesconexion: _fecha(mapa['ultima_desconexion']),
        ultimaNotificacion: _fecha(mapa['ultima_notificacion']),
        ultimoResultado: mapa['ultimo_resultado'] as String?,
      );

  static DateTime? _fecha(Object? milisegundos) =>
      milisegundos == null ? null : DateTime.fromMillisecondsSinceEpoch((milisegundos as num).toInt());
}

/// Apps permitidas y palabras de cobro (res/raw/deteccion_apps.json).
class ConfiguracionLector {
  const ConfiguracionLector({
    required this.apps,
    required this.palabrasCobro,
    required this.palabrasExcluidas,
  });

  /// Pares (paquete, nombre).
  final List<({String paquete, String nombre})> apps;
  final List<String> palabrasCobro;
  final List<String> palabrasExcluidas;

  factory ConfiguracionLector.fromMap(Map<Object?, Object?> mapa) => ConfiguracionLector(
        apps: (mapa['apps_permitidas'] as List? ?? const [])
            .cast<Map<Object?, Object?>>()
            .map((a) => (paquete: a['paquete'] as String, nombre: a['nombre'] as String))
            .toList(),
        palabrasCobro: (mapa['palabras_cobro'] as List? ?? const []).cast<String>(),
        palabrasExcluidas: (mapa['palabras_excluidas'] as List? ?? const []).cast<String>(),
      );
}
