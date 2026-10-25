import '../models/aviso.dart';
import '../models/resumen.dart';
import '../models/suscripcion.dart';
import 'api_client.dart';

/// Llamadas al backend para las suscripciones y el resumen del dashboard.
/// Todas lanzan [ApiException] si fallan.
class SuscripcionService {
  SuscripcionService(this._api);

  final ApiClient _api;

  static const String _ruta = '/api/suscripciones';

  /// Suscripciones del usuario ordenadas por próximo cobro.
  /// Sin [estados] devuelve todas.
  Future<List<Suscripcion>> listar({List<EstadoSuscripcion>? estados}) async {
    final json = await _api.get(
      _ruta,
      query: estados == null
          ? null
          : {'estado': estados.map((e) => e.valor).join(',')},
    );
    return (json['suscripciones'] as List)
        .map((s) => Suscripcion.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  /// La suscripción con sus 3 últimos pagos y el total pagado.
  Future<DetalleSuscripcion> obtener(int id) async =>
      DetalleSuscripcion.fromJson(await _api.get('$_ruta/$id'));

  Future<Suscripcion> crear(Suscripcion suscripcion) async =>
      _leer(await _api.post(_ruta, suscripcion.toJson()));

  Future<Suscripcion> actualizar(Suscripcion suscripcion) async =>
      _leer(await _api.put('$_ruta/${suscripcion.id}', suscripcion.toJson()));

  Future<void> eliminar(int id) => _api.delete('$_ruta/$id');

  Future<Suscripcion> cambiarEstado(int id, EstadoSuscripcion estado) async =>
      _leer(await _api.patch('$_ruta/$id/estado', {'estado': estado.valor}));

  /// Avisos de la pestaña Avisos y los días de aviso globales.
  Future<({List<Aviso> avisos, int dias})> avisos() async {
    final json = await _api.get('/api/avisos');
    return (
      avisos: (json['avisos'] as List)
          .map((a) => Aviso.fromJson(a as Map<String, dynamic>))
          .toList(),
      dias: json['dias_anticipacion_recordatorio'] as int,
    );
  }

  Future<Resumen> resumen() async =>
      Resumen.fromJson(await _api.get('/api/resumen'));

  Suscripcion _leer(Map<String, dynamic> json) =>
      Suscripcion.fromJson(json['suscripcion'] as Map<String, dynamic>);
}
