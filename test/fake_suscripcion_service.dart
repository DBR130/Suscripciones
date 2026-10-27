import 'package:flutter_suscripciones/models/aviso.dart';
import 'package:flutter_suscripciones/models/resumen.dart';
import 'package:flutter_suscripciones/models/suscripcion.dart';
import 'package:flutter_suscripciones/services/api_client.dart';
import 'package:flutter_suscripciones/services/suscripcion_service.dart';

/// SuscripcionService falso: guarda las suscripciones en memoria.
/// Si [error] tiene valor, crear y actualizar fallan con ese mensaje.
class FakeSuscripcionService implements SuscripcionService {
  FakeSuscripcionService({
    List<Suscripcion>? iniciales,
    this.error,
    this.pagos = const [],
    this.cambioPrecio,
    this.listaAvisos = const [],
  }) : suscripciones = [...?iniciales];

  final List<Suscripcion> suscripciones;
  final String? error;

  /// Pagos y cambio de precio que devuelve [obtener] para cualquier suscripción.
  final List<Pago> pagos;
  final CambioPrecio? cambioPrecio;

  /// Lo que devuelve [avisos].
  final List<Aviso> listaAvisos;

  /// Última suscripción recibida en crear/actualizar.
  Suscripcion? ultimaGuardada;

  /// Ids eliminados.
  final List<int> eliminadas = [];

  int _siguienteId = 100;

  Suscripcion _copia(Suscripcion s, {int? id, EstadoSuscripcion? estado}) => Suscripcion(
        id: id ?? s.id,
        nombreServicio: s.nombreServicio,
        categoria: s.categoria,
        monto: s.monto,
        moneda: s.moneda,
        frecuencia: s.frecuencia,
        fechaProximoCobro: s.fechaProximoCobro,
        esPruebaGratis: s.esPruebaGratis,
        fechaFinPrueba: s.fechaFinPrueba,
        diasAviso: s.diasAviso,
        estado: estado ?? s.estado,
      );

  Suscripcion _buscar(int id) => suscripciones.firstWhere(
        (s) => s.id == id,
        orElse: () => throw const ApiException('Suscripción no encontrada'),
      );

  @override
  Future<List<Suscripcion>> listar({List<EstadoSuscripcion>? estados}) async =>
      suscripciones.where((s) => estados == null || estados.contains(s.estado)).toList();

  @override
  Future<DetalleSuscripcion> obtener(int id) async => DetalleSuscripcion(
        suscripcion: _buscar(id),
        pagos: pagos,
        pagadoTotal: pagos.fold(0, (t, p) => t + p.monto),
        cambioPrecio: cambioPrecio,
      );

  @override
  Future<({List<Aviso> avisos, int dias})> avisos() async => (avisos: listaAvisos, dias: 3);

  @override
  Future<Suscripcion> crear(Suscripcion suscripcion) async {
    ultimaGuardada = suscripcion;
    if (error != null) throw ApiException(error!);
    final nueva = _copia(suscripcion, id: _siguienteId++);
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
  Future<void> eliminar(int id) async {
    eliminadas.add(id);
    suscripciones.removeWhere((s) => s.id == id);
  }

  @override
  Future<Suscripcion> cambiarEstado(int id, EstadoSuscripcion estado) async {
    final nueva = _copia(_buscar(id), estado: estado);
    suscripciones[suscripciones.indexWhere((s) => s.id == id)] = nueva;
    return nueva;
  }

  @override
  Future<Resumen> resumen() async {
    final activas = suscripciones.where((s) => s.estado != EstadoSuscripcion.cancelada).toList();
    double mensual(Suscripcion s) =>
        s.esPruebaGratis ? 0 : s.monto * s.frecuencia.cobrosPorAnio / 12;

    final porCategoria = <String?, TotalCategoria>{};
    for (final s in activas) {
      final previo = porCategoria[s.categoria];
      porCategoria[s.categoria] = TotalCategoria(
        categoria: s.categoria,
        moneda: 'COP',
        gastoMensual: (previo?.gastoMensual ?? 0) + mensual(s),
        cantidad: (previo?.cantidad ?? 0) + 1,
      );
    }
    final total = activas.fold<double>(0, (t, s) => t + mensual(s));
    return Resumen(
      totales: activas.isEmpty
          ? const []
          : [
              TotalMoneda(
                moneda: 'COP',
                gastoMensual: total,
                proyeccionAnual: total * 12,
                cantidad: activas.length,
              ),
            ],
      porCategoria: porCategoria.values.toList()
        ..sort((a, b) => b.gastoMensual.compareTo(a.gastoMensual)),
      cantidadActivas: activas.length,
      proximosCobros: const [],
      pruebasPorTerminar: const [],
      diasAnticipacion: 3,
    );
  }
}
