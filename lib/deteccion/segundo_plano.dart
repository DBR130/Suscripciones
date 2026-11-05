import 'package:flutter/widgets.dart';

import 'package:flutter/services.dart';

import '../services/api_client.dart';
import '../services/recordatorios_service.dart';
import '../services/suscripcion_service.dart';
import 'deteccion_service.dart';
import 'lector_notificaciones.dart';
import 'procesador_detecciones.dart';
import 'turno.dart';

/// Lo que ejecuta el motor sin pantalla de ProcesarColaWorker.kt (punto de
/// entrada procesarEnSegundoPlano en main.dart). Al final SIEMPRE avisa
/// "terminar" para que Kotlin destruya el motor.
Future<void> tareaDeFondo() async {
  WidgetsFlutterBinding.ensureInitialized();
  const canal = MethodChannel('subtrack/segundo_plano');
  const deteccion = MethodChannel('subtrack/deteccion');
  await canal.invokeMethod<void>('inicio');
  var resultado = ResultadoTarea.reintentar;
  try {
    final api = ApiClient();
    final recordatorios = RecordatoriosService();
    await recordatorios.inicializar();
    resultado = await ejecutarEnSegundoPlano(
      api: api,
      procesador: ProcesadorDetecciones(
        lector: LectorNotificaciones(),
        servicio: DeteccionService(api),
        cargarCatalogo: SuscripcionService(api).catalogoServicios,
        turno: Turno('fondo'),
      ),
      avisar: recordatorios.avisarEscaneo,
      registrar: (r, procesados, motivo) => deteccion.invokeMethod<void>(
        'registrarEjecucionFondo',
        {'resultado': r, 'procesados': procesados, 'motivo': motivo},
      ),
    );
    debugPrint('SubTrackDeteccion segundo plano: ${resultado.name}');
  } catch (e) {
    debugPrint('SubTrackDeteccion segundo plano: error ${e.runtimeType}');
  } finally {
    await canal.invokeMethod<void>('terminar', resultado.name);
  }
}

/// Cómo terminó una ejecución de la tarea de fondo. El worker nativo
/// (ProcesarColaWorker.kt) decide con esto: [reintentar] = Result.retry()
/// (backoff exponencial de 30 s); el resto, Result.success().
enum ResultadoTarea { ok, sinSesion, reintentar }

/// Guarda la ejecución para la pantalla de depuración: resultado ("ok",
/// "sin sesión", "reintento…"), cuántas notificaciones revisó y el motivo.
typedef RegistrarEjecucion = Future<void> Function(String resultado, int procesados, String? motivo);

/// Lo que hace la tarea de fondo de WorkManager con la app cerrada: lo mismo
/// que la app al abrirse (ProcesadorDetecciones.procesar y los mismos avisos),
/// pero:
///  - Sin sesión no procesa nada: la cola queda intacta para cuando el usuario
///    inicie sesión.
///  - Si la app está procesando (no hay turno) no espera: reintenta luego.
///  - Si el servidor no responde (también tras los 75 s de despertar), la
///    cola queda intacta y se reintenta.
Future<ResultadoTarea> ejecutarEnSegundoPlano({
  required ApiClient api,
  required ProcesadorDetecciones procesador,
  required Future<void> Function(ResultadoEscaneo resultado) avisar,
  required RegistrarEjecucion registrar,
}) async {
  if (await api.leerToken() == null) {
    await registrar('sin sesión', 0, null);
    return ResultadoTarea.sinSesion;
  }
  try {
    final resultado = await procesador.procesar();
    await avisar(resultado);
    await registrar('ok', resultado.revisadas, null);
    return ResultadoTarea.ok;
  } on TurnoOcupado {
    await registrar('reintento: la app estaba procesando', 0, null);
    return ResultadoTarea.reintentar;
  } on ApiException catch (e) {
    await registrar('reintento', 0, e.mensaje);
    return ResultadoTarea.reintentar;
  } catch (e) {
    // Solo el tipo: el mensaje de un error podría traer parte de un SMS.
    debugPrint('SubTrackDeteccion segundo plano: error ${e.runtimeType}');
    await registrar('reintento', 0, 'error ${e.runtimeType}');
    return ResultadoTarea.reintentar;
  }
}
