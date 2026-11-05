import '../models/suscripcion.dart';
import '../services/api_client.dart';
import 'candidato_suscripcion.dart';

/// Qué hizo el backend con un cobro compartido: "candidato_nuevo",
/// "candidato_actualizado", "suscripcion_existente", "ya_confirmado",
/// "comercio_descartado" o "repetido".
typedef ResultadoCompartido = ({String resultado, int? suscripcionId, int? candidatoId});

/// Llamadas al backend de detecciones (/api/detecciones). Todas lanzan
/// [ApiException] si fallan.
class DeteccionService {
  DeteccionService(this._api);

  final ApiClient _api;

  static const String _ruta = '/api/detecciones';

  /// Máximo de pagos por envío que acepta el backend.
  static const int maxPorEnvio = 100;

  /// Envía los pagos extraídos (ver huella_pago.dart). Devuelve los candidatos
  /// creados en este envío, para avisar al usuario (flujo B).
  Future<List<CandidatoSuscripcion>> enviarPagos(List<Map<String, Object>> pagos) async {
    final nuevos = <CandidatoSuscripcion>[];
    for (var i = 0; i < pagos.length; i += maxPorEnvio) {
      final lote = pagos.sublist(i, i + maxPorEnvio > pagos.length ? pagos.length : i + maxPorEnvio);
      final json = await _api.post('$_ruta/pagos', {'pagos': lote});
      nuevos.addAll((json['candidatos_nuevos'] as List)
          .map((c) => CandidatoSuscripcion.fromJson(c as Map<String, dynamic>)));
    }
    return nuevos;
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
  Future<Suscripcion> confirmar(int id, {double? monto, Frecuencia? frecuencia, String? nombre}) async {
    final json = await _api.post('$_ruta/candidatos/$id/confirmar', {
      'nombre_servicio': ?nombre,
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
