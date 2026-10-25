import 'package:flutter_suscripciones/models/resumen.dart';
import 'package:flutter_suscripciones/models/suscripcion.dart';
import 'package:flutter_suscripciones/services/api_client.dart';
import 'package:flutter_suscripciones/services/suscripcion_service.dart';

/// SuscripcionService falso: guarda las suscripciones en memoria.
/// Si [error] tiene valor, crear y actualizar fallan con ese mensaje.
class FakeSuscripcionService implements SuscripcionService {
  FakeSuscripcionService({List<Suscripcion>? iniciales, this.error})
      : suscripciones = [...?iniciales];

  final List<Suscripcion> suscripciones;
  final String? error;

  /// Última suscripción recibida en crear/actualizar.
  Suscripcion? ultimaGuardada;

  int _siguienteId = 100;

  Suscripcion _conId(Suscripcion s, int id) => Suscripcion(
        id: id,
        nombreServicio: s.nombreServicio,
        monto: s.monto,
        moneda: s.moneda,
        frecuencia: s.frecuencia,
        fechaProximoCobro: s.fechaProximoCobro,
        esPruebaGratis: s.esPruebaGratis,
        fechaFinPrueba: s.fechaFinPrueba,
        diasAviso: s.diasAviso,
      );

  @override
  Future<List<Suscripcion>> listar({List<EstadoSuscripcion>? estados}) async =>
      suscripciones.where((s) => estados == null || estados.contains(s.estado)).toList();

  @override
  Future<Suscripcion> obtener(int id) async =>
      suscripciones.firstWhere((s) => s.id == id, orElse: () => throw const ApiException('Suscripción no encontrada'));

  @override
  Future<Suscripcion> crear(Suscripcion suscripcion) async {
    ultimaGuardada = suscripcion;
    if (error != null) throw ApiException(error!);
    final nueva = _conId(suscripcion, _siguienteId++);
    suscripciones.add(nueva);
    return nueva;
  }

  @override
  Future<Suscripcion> actualizar(Suscripcion suscripcion) async {
    ultimaGuardada = suscripcion;
    if (error != null) throw ApiException(error!);
    suscripciones[suscripciones.indexWhere((s) => s.id == suscripcion.id)] = suscripcion;
    return suscripcion;
  }

  @override
  Future<void> eliminar(int id) async => suscripciones.removeWhere((s) => s.id == id);

  @override
  Future<Suscripcion> cambiarEstado(int id, EstadoSuscripcion estado) async =>
      throw UnimplementedError();

  @override
  Future<Resumen> resumen() async {
    final activas = suscripciones.where((s) => s.estado != EstadoSuscripcion.cancelada).toList();
    final mensual = activas
        .where((s) => !s.esPruebaGratis)
        .fold<double>(0, (t, s) => t + s.monto * s.frecuencia.cobrosPorAnio / 12);
    return Resumen(
      totales: activas.isEmpty
          ? const []
          : [
              TotalMoneda(
                moneda: 'COP',
                gastoMensual: mensual,
                proyeccionAnual: mensual * 12,
                cantidad: activas.length,
              ),
            ],
      cantidadActivas: activas.length,
      proximosCobros: const [],
      pruebasPorTerminar: const [],
      diasAnticipacion: 3,
    );
  }
}
