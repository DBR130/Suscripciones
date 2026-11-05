import '../models/suscripcion.dart';
import '../services/api_client.dart';
import 'candidato_suscripcion.dart';

/// Qué hizo el backend con un cobro compartido: "candidato_nuevo",
/// "candidato_actualizado", "suscripcion_existente", "ya_confirmado",
/// "comercio_descartado" o "repetido".
typedef ResultadoCompartido = ({String resultado, int? suscripcionId, int? candidatoId});

/// Un pago detectado que el backend registró en una suscripción que ya
/// existía (resultado "suscripcion_existente"). Si cambió el precio,
/// [montoAnterior] es el de antes. Para el aviso "Registramos un pago…" (T8).
class PagoRegistrado {
  const PagoRegistrado({required this.servicio, required this.monto, required this.moneda, this.montoAnterior});

  final String servicio;
  final double monto;
  final String moneda;
  final double? montoAnterior;
}

/// Lo que respondió el backend a un envío de pagos.
typedef ResultadoEnvio = ({List<CandidatoSuscripcion> nuevos, List<PagoRegistrado> registrados});

/// Llamadas al backend de detecciones (/api/detecciones). Todas lanzan
/// [ApiException] si fallan.
class DeteccionService {
  DeteccionService(this._api);

  final ApiClient _api;

  static const String _ruta = '/api/detecciones';

  /// Máximo de pagos por envío que acepta el backend.
  static const int maxPorEnvio = 100;

  /// Envía los pagos extraídos (ver huella_pago.dart). Devuelve los candidatos
  /// creados en este envío (flujo B) y los pagos que se registraron en una
  /// suscripción existente (aviso "Registramos un pago…"). Los repetidos, las
  /// compras normales y los de comercios descartados no se avisan.
  Future<ResultadoEnvio> enviarPagos(List<Map<String, Object>> pagos) async {
    final nuevos = <CandidatoSuscripcion>[];
    final registrados = <PagoRegistrado>[];
    for (var i = 0; i < pagos.length; i += maxPorEnvio) {
      final lote = pagos.sublist(i, i + maxPorEnvio > pagos.length ? pagos.length : i + maxPorEnvio);
      final json = await _api.post('$_ruta/pagos', {'pagos': lote});
      nuevos.addAll((json['candidatos_nuevos'] as List)
          .map((c) => CandidatoSuscripcion.fromJson(c as Map<String, dynamic>)));
      for (final r in (json['resultados'] as List? ?? const []).cast<Map<String, dynamic>>()) {
        if (r['resultado'] != 'suscripcion_existente' || r['nombre_servicio'] == null) continue;
        registrados.add(PagoRegistrado(
          servicio: r['nombre_servicio'] as String,
          monto: (r['monto'] as num).toDouble(),
          moneda: r['moneda'] as String,
          montoAnterior: (r['monto_anterior'] as num?)?.toDouble(),
        ));
      }
    }
    return (nuevos: nuevos, registrados: registrados);
  }

  /// Un cobro que el usuario compartió con SubTrack a propósito: aunque sea de
  /// un comercio desconocido y el único, el backend lo propone como
  /// suscripción (el usuario dice que lo es). Devuelve qué pasó.
  Future<ResultadoCompartido> enviarCompartido(Map<String, Object> pago) async {
    final json = await _api.post('$_ruta/pagos', {
      'pagos': [pago],
      'compartido': true,
    });
    final r = (json['resultados'] as List).first as Map<String, dynamic>;
    return (
      resultado: r['resultado'] as String,
      suscripcionId: r['suscripcion_id'] as int?,
      candidatoId: r['candidato_id'] as int?,
    );
  }

  /// Candidatos pendientes de confirmar o descartar.
  Future<List<CandidatoSuscripcion>> candidatos() async {
    final json = await _api.get('$_ruta/candidatos');
    return (json['candidatos'] as List)
        .map((c) => CandidatoSuscripcion.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  /// Crea la suscripción (origen "notificacion"). [monto], [frecuencia] y
  /// [nombre] son las correcciones del usuario; lo que no se envía sale del
  /// candidato.
  ///
  /// "Unir" el mismo servicio detectado dos veces: [unirConCandidato] deja ese
  /// otro candidato en la misma suscripción; [unirConSuscripcion] agrega los
  /// pagos a esa suscripción sin crear otra.
  Future<Suscripcion> confirmar(
    int id, {
    double? monto,
    Frecuencia? frecuencia,
    String? nombre,
    int? unirConCandidato,
    int? unirConSuscripcion,
  }) async {
    final json = await _api.post('$_ruta/candidatos/$id/confirmar', {
      'nombre_servicio': ?nombre,
      'unir_con_candidato': ?unirConCandidato,
      'unir_con_suscripcion': ?unirConSuscripcion,
      if (monto != null) 'monto': monto.toStringAsFixed(2),
      if (frecuencia != null) 'frecuencia': frecuencia.valor,
    });
    return Suscripcion.fromJson(json['suscripcion'] as Map<String, dynamic>);
  }

  /// El comercio no se vuelve a proponer.
  Future<void> descartar(int id) => _api.post('$_ruta/candidatos/$id/descartar', const {});

  /// Comercios descartados ("Detecciones descartadas" en Perfil).
  Future<List<CandidatoSuscripcion>> descartadas() async {
    final json = await _api.get('$_ruta/descartadas');
    return (json['candidatos'] as List)
        .map((c) => CandidatoSuscripcion.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  /// Deshace un descarte: el candidato vuelve a pendiente.
  Future<void> restaurar(int id) => _api.post('$_ruta/candidatos/$id/restaurar', const {});
}
