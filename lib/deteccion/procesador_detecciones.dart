import 'package:flutter/foundation.dart';

import '../utils/formato.dart';
import 'almacen_pagos_locales.dart';
import 'analizador_pagos.dart';
import 'candidato_suscripcion.dart';
import 'catalogo_servicios.dart';
import 'deteccion_service.dart';
import 'historial_sms.dart';
import 'huella_pago.dart';
import 'lector_notificaciones.dart';
import 'notificacion_capturada.dart';
import 'parser_pagos.dart';

/// Resultado de procesar la cola de notificaciones.
class ResultadoEscaneo {
  const ResultadoEscaneo({
    required this.revisadas,
    required this.cobros,
    required this.candidatosNuevos,
    this.enviados = 0,
    this.registrados = const [],
  });

  static const vacio = ResultadoEscaneo(revisadas: 0, cobros: 0, candidatosNuevos: []);

  /// Notificaciones (o SMS) que se revisaron.
  final int revisadas;

  /// Cuántas eran cobros (se interpretaron y quedaron en el celular).
  final int cobros;

  /// Cuántos pagos salieron hacia el backend: solo servicios conocidos y
  /// comercios con patrón recurrente (ver AnalizadorPagos).
  final int enviados;

  /// Candidatos que el backend creó con este envío.
  final List<CandidatoSuscripcion> candidatosNuevos;

  /// Pagos registrados en suscripciones existentes (aviso T8).
  final List<PagoRegistrado> registrados;
}

/// Resultado de la búsqueda en el historial de SMS.
class ResultadoHistorial extends ResultadoEscaneo {
  const ResultadoHistorial({
    required super.revisadas,
    required super.cobros,
    required super.candidatosNuevos,
    super.enviados,
    required this.deEmpresas,
  });

  /// SMS de remitentes de empresa entre los revisados (ver LecturaHistorial).
  final int deEmpresas;

  /// Se leyeron SMS pero ninguno de un banco o empresa: en Xiaomi puede ser
  /// que los SMS de servicio estén ocultos para la app.
  bool get sospechaSmsOcultos => revisadas > 0 && deEmpresas == 0;
}

/// Etapas de la búsqueda en el historial, para la pantalla 04.
enum EtapaHistorial { leyendo, analizando, enviando }

/// Une las piezas de la detección: interpreta cada cobro con el parser, lo
/// guarda en el celular (solo campos extraídos), decide qué puede salir
/// (AnalizadorPagos) y envía eso al backend.
///
/// Dos entradas, el mismo camino:
///  - [procesar]: la cola del lector de notificaciones (y las activas de la
///    barra). La usan la pantalla 04 y main.dart al abrir o volver a la app.
///  - [buscarEnHistorial]: el historial de SMS (versión "completa", con
///    permiso).
class ProcesadorDetecciones {
  ProcesadorDetecciones({
    required this.lector,
    required this.servicio,
    required this.cargarCatalogo,
    AlmacenPagosLocales? almacen,
    HistorialSms? historial,
    this.esperaConexion = const Duration(milliseconds: 500),
    DateTime Function()? ahora,
  })  : almacen = almacen ?? AlmacenPagosLocales(),
        historial = historial ?? HistorialSms(),
        _ahora = ahora ?? DateTime.now;

  final LectorNotificaciones lector;
  final DeteccionService servicio;
  final Future<CatalogoServicios> Function() cargarCatalogo;
  final AlmacenPagosLocales almacen;
  final HistorialSms historial;
  final DateTime Function() _ahora;

  /// Recién dado el permiso, Android tarda un momento en conectar el lector.
  final Duration esperaConexion;

  /// Diagnóstico del último escaneo (pantalla de depuración, solo debug): cada
  /// comercio con su decisión. Solo campos extraídos, nunca el texto.
  final ValueNotifier<List<DiagnosticoComercio>> ultimoDiagnostico = ValueNotifier(const []);

  /// Analiza los pagos del celular (lo mismo que decide qué sale), guarda el
  /// diagnóstico y, en debug, lo escribe en los logs.
  Future<void> _diagnosticar() async {
    final diagnostico = AnalizadorPagos.diagnosticar([for (final l in await almacen.leer()) l.pago]);
    ultimoDiagnostico.value = diagnostico;
    if (!kDebugMode) return;
    for (final c in diagnostico) {
      debugPrint('SubTrackDeteccion escaneo: ${c.nombre} · ${c.bancos.join(', ')} · ${c.cobros} cobros '
          '(${c.montos.map((m) => Formato.moneda(m, c.moneda)).join(', ')}) · '
          '${c.salen > 0 ? 'sale' : 'no sale'}: ${c.motivo}');
    }
  }
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
    if (cola.isEmpty) {
      // Puede haber pendientes de un envío anterior que falló.
      final r = await _enviarPendientes();
      return ResultadoEscaneo(
        revisadas: 0,
        cobros: 0,
        enviados: r.enviados,
        candidatosNuevos: r.nuevos,
        registrados: r.registrados,
      );
    }

    // Sin catálogo (backend no disponible) no se procesa nada: la cola queda
    // intacta para la próxima vez.
    final pagos = _interpretar(cola, ParserPagos(await cargarCatalogo()));
    await almacen.agregar(pagos);
    // Minimización: el texto crudo no se queda en la cola. Lo interpretado ya
    // está en el almacén local (solo campos extraídos).
    await lector.borrarDeCola(cola.map((n) => n.id).toList());
    await _diagnosticar();
    final r = await _enviarPendientes();
    return ResultadoEscaneo(
      revisadas: cola.length,
      cobros: pagos.length,
      enviados: r.enviados,
      candidatosNuevos: r.nuevos,
      registrados: r.registrados,
    );
  }

  /// "Buscar suscripciones en mis SMS": lee los SMS de los últimos
  /// [HistorialSms.meses] meses (solo los que parecen cobros llegan aquí),
  /// los interpreta en el celular y envía solo lo que forma una suscripción.
  /// Repetirla no duplica nada (ver AnalizadorPagos.mismoCobro y la huella).
  Future<ResultadoHistorial> buscarEnHistorial({void Function(EtapaHistorial etapa)? alAvanzar}) async {
    alAvanzar?.call(EtapaHistorial.leyendo);
    final ahora = _ahora();
    final desde = DateTime(ahora.year, ahora.month - HistorialSms.meses, ahora.day);
    final lectura = await historial.leer(desde);

    alAvanzar?.call(EtapaHistorial.analizando);
    final pagos = _interpretar(lectura.mensajes, ParserPagos(await cargarCatalogo()));
    await almacen.agregar(pagos);
    await _diagnosticar();

    alAvanzar?.call(EtapaHistorial.enviando);
    final r = await _enviarPendientes();
    return ResultadoHistorial(
      revisadas: lectura.leidos,
      cobros: pagos.length,
      enviados: r.enviados,
      candidatosNuevos: r.nuevos,
      deEmpresas: lectura.deEmpresas,
    );
  }

  List<PagoExtraido> _interpretar(List<NotificacionCapturada> mensajes, ParserPagos parser) => [
        for (final n in mensajes) ?parser.interpretarNotificacion(n).pago,
      ];

  /// Envía (en lotes de 100) lo que puede salir y aún no ha salido.
  Future<({int enviados, List<CandidatoSuscripcion> nuevos, List<PagoRegistrado> registrados})>
      _enviarPendientes() async {
    final pendientes = await almacen.pendientesDeEnviar();
    if (pendientes.isEmpty) return (enviados: 0, nuevos: <CandidatoSuscripcion>[], registrados: <PagoRegistrado>[]);
    final r = await servicio.enviarPagos([for (final p in pendientes) pagoParaEnviar(p)]);
    await almacen.marcarEnviados(pendientes);
    return (enviados: pendientes.length, nuevos: r.nuevos, registrados: r.registrados);
  }
}
