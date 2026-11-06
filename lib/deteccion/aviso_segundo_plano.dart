import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Aviso "Tu celular cerró SubTrack…" (encargo C, punto 5; ver
/// docs/deteccion.md, "Fabricantes que cierran apps").
///
/// Cuándo hay una falla: la app se abrió con el lector desconectado, lo
/// reconectó y el rescate desde la barra trajo al menos un cobro nuevo
/// (ProcesadorDetecciones lo anota). Como no hay API para saber si el
/// autoencendido está activo, esta es la única señal fiable.

/// Máximo un aviso por semana, contada desde el último que se mostró.
const semanaAvisoSegundoPlano = Duration(days: 7);

/// Regla del aviso: hay una falla sin atender y pasó una semana desde el
/// último aviso mostrado (o nunca se mostró).
bool debeMostrarAvisoSegundoPlano({
  required DateTime? fallaPendiente,
  required DateTime? ultimoAviso,
  required DateTime ahora,
}) {
  if (fallaPendiente == null) return false;
  return ultimoAviso == null || ahora.difference(ultimoAviso) >= semanaAvisoSegundoPlano;
}

/// Fechas del aviso en el almacenamiento seguro (cifrado). Lo escriben la app
/// y la tarea de fondo (las dos usan ProcesadorDetecciones). Solo fechas.
class RegistroSegundoPlano {
  RegistroSegundoPlano({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _claveFalla = 'segundo_plano_falla_pendiente';
  static const _claveAviso = 'segundo_plano_ultimo_aviso';
  static const _claveGuia = 'segundo_plano_guia_vista';

  Future<DateTime?> _leer(String clave) async {
    final texto = await _storage.read(key: clave);
    return texto == null ? null : DateTime.tryParse(texto);
  }

  Future<void> _escribir(String clave, DateTime fecha) => _storage.write(key: clave, value: fecha.toIso8601String());

  /// Cobros nuevos que llegaron con el lector desconectado.
  Future<void> anotarFalla(DateTime fecha) => _escribir(_claveFalla, fecha);
  Future<DateTime?> fallaPendiente() => _leer(_claveFalla);
  Future<void> descartarFalla() => _storage.delete(key: _claveFalla);

  Future<DateTime?> ultimoAviso() => _leer(_claveAviso);
  Future<void> marcarAvisoMostrado(DateTime fecha) => _escribir(_claveAviso, fecha);

  /// "Ya lo activé" en la guía: solo que el usuario la vio (no hay forma de
  /// comprobar el ajuste).
  Future<DateTime?> guiaVista() => _leer(_claveGuia);
  Future<void> marcarGuiaVista(DateTime fecha) => _escribir(_claveGuia, fecha);
}

/// Publica si el aviso se ve en Inicio. main.dart llama [revisar] al abrir la
/// app y al volver a ella, después de procesar la cola.
class ControlSegundoPlano {
  ControlSegundoPlano({RegistroSegundoPlano? registro, DateTime Function()? ahora})
      : registro = registro ?? RegistroSegundoPlano(),
        _ahora = ahora ?? DateTime.now;

  final RegistroSegundoPlano registro;
  final DateTime Function() _ahora;

  final ValueNotifier<bool> avisoVisible = ValueNotifier(false);

  /// Cada falla se usa una sola vez: si cae dentro de la semana, se descarta
  /// sin mostrar nada. Devuelve si el aviso quedó visible.
  Future<bool> revisar() async {
    final falla = await registro.fallaPendiente();
    if (falla == null) return avisoVisible.value;
    final ahora = _ahora();
    final mostrar = debeMostrarAvisoSegundoPlano(
      fallaPendiente: falla,
      ultimoAviso: await registro.ultimoAviso(),
      ahora: ahora,
    );
    await registro.descartarFalla();
    if (!mostrar) return avisoVisible.value;
    await registro.marcarAvisoMostrado(ahora);
    return avisoVisible.value = true;
  }

  /// La X del aviso: ya contó como mostrado al aparecer.
  void cerrar() => avisoVisible.value = false;

  /// Solo depuración: muestra el aviso ya (cuenta como mostrado).
  Future<void> forzar() async {
    await registro.marcarAvisoMostrado(_ahora());
    avisoVisible.value = true;
  }
}
