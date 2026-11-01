import 'candidato_suscripcion.dart';
import 'catalogo_servicios.dart';
import 'deteccion_service.dart';
import 'huella_pago.dart';
import 'lector_notificaciones.dart';
import 'parser_pagos.dart';

/// Resultado de procesar la cola de notificaciones.
class ResultadoEscaneo {
  const ResultadoEscaneo({required this.revisadas, required this.cobros, required this.candidatosNuevos});

  static const vacio = ResultadoEscaneo(revisadas: 0, cobros: 0, candidatosNuevos: []);

  /// Notificaciones de la cola que se revisaron.
  final int revisadas;

  /// Cuántas eran cobros y se enviaron al backend.
  final int cobros;

  /// Candidatos que el backend creó con este envío.
  final List<CandidatoSuscripcion> candidatosNuevos;
}

/// Une las piezas de la detección: lee la cola nativa (y las notificaciones
/// activas de la barra), interpreta cada una con el parser, envía al backend
/// solo los campos extraídos y borra de la cola lo procesado.
///
/// Lo usan la pantalla de escaneo (04) y main.dart al abrir o volver a la
/// app (flujo B).
class ProcesadorDetecciones {
  ProcesadorDetecciones({
    required this.lector,
    required this.servicio,
    required this.cargarCatalogo,
    this.esperaConexion = const Duration(milliseconds: 500),
  });

  final LectorNotificaciones lector;
  final DeteccionService servicio;
  final Future<CatalogoServicios> Function() cargarCatalogo;

  /// Recién dado el permiso, Android tarda un momento en conectar el lector.
  final Duration esperaConexion;
  static const _intentosConexion = 6;

  Future<ResultadoEscaneo>? _enCurso;

  /// Si ya hay un procesamiento en curso (la pantalla y main.dart a la vez),
  /// devuelve ese mismo: nunca se envía la cola dos veces en paralelo.
  Future<ResultadoEscaneo> procesar() => _enCurso ??= _procesar().whenComplete(() => _enCurso = null);

  Future<ResultadoEscaneo> _procesar() async {
    await lector.reconectarSiHaceFalta();
    // Recupera de la barra lo que llegó con el lector detenido. Si el permiso
    // está pero el lector aún no se conecta, espera un poco.
    for (var i = 0; i < _intentosConexion; i++) {
      if (await lector.recuperarActivas() != null) break;
      if (!(await lector.estado()).permiso) break;
      await Future<void>.delayed(esperaConexion);
    }

    final cola = await lector.leerCola();
    if (cola.isEmpty) return ResultadoEscaneo.vacio;

    // Sin catálogo (backend no disponible) no se envía nada: la cola queda
    // intacta para la próxima vez.
    final parser = ParserPagos(await cargarCatalogo());
    final pagos = <Map<String, Object>>[];
    for (final n in cola) {
      final pago = parser.interpretarNotificacion(n).pago;
      if (pago != null) pagos.add(pagoParaEnviar(pago));
    }
    final nuevos = pagos.isEmpty ? <CandidatoSuscripcion>[] : await servicio.enviarPagos(pagos);

    // Minimización: lo que no era un cobro tampoco se queda en el celular.
    await lector.borrarDeCola(cola.map((n) => n.id).toList());
    return ResultadoEscaneo(revisadas: cola.length, cobros: pagos.length, candidatosNuevos: nuevos);
  }
}
