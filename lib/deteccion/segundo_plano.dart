import 'package:flutter/foundation.dart';

import '../services/api_client.dart';
import 'procesador_detecciones.dart';

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
    debugPrint('SubTrackDeteccion segundo plano: $e');
    await registrar('reintento', 0, e.toString());
    return ResultadoTarea.reintentar;
  }
}
