import 'package:flutter/services.dart';
import 'package:flutter_suscripciones/deteccion/turno.dart';
import 'package:flutter_test/flutter_test.dart';

/// Procesar la cola en segundo plano (encargo B): turno compartido entre la
/// app y la tarea de fondo, avisos y la función que llama el worker.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const canal = MethodChannel('subtrack/deteccion');
  final mensajero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Candado nativo simulado: ocupado las primeras [ocupadoVeces] veces.
  late int ocupadoVeces;
  late List<String> llamadas;

  setUp(() {
    ocupadoVeces = 0;
    llamadas = [];
    mensajero.setMockMethodCallHandler(canal, (call) async {
      llamadas.add('${call.method}:${(call.arguments as Map)['quien']}');
      if (call.method == 'tomarTurno') {
        if (ocupadoVeces > 0) {
          ocupadoVeces--;
          return false;
        }
        return true;
      }
      return null;
    });
  });

  tearDown(() => mensajero.setMockMethodCallHandler(canal, null));

  group('Turno (S12)', () {
    Turno turno() => Turno('app', disponible: true, intervalo: const Duration(milliseconds: 5));

    test('el procesamiento automático intenta una sola vez', () async {
      ocupadoVeces = 1;
      expect(await turno().tomar(), isFalse);
      expect(llamadas, ['tomarTurno:app']);
    });

    test('una acción del usuario espera hasta conseguirlo', () async {
      ocupadoVeces = 3;
      expect(await turno().tomar(esperar: const Duration(seconds: 1)), isTrue);
      expect(llamadas.where((l) => l == 'tomarTurno:app'), hasLength(4));
    });

    test('si no lo consigue en el plazo, se rinde', () async {
      ocupadoVeces = 1000;
      expect(await turno().tomar(esperar: const Duration(milliseconds: 40)), isFalse);
    });

    test('soltar avisa quién lo suelta', () async {
      await turno().soltar();
      expect(llamadas, ['soltarTurno:app']);
    });

    test('fuera de Android siempre hay turno', () async {
      expect(await Turno('app', disponible: false).tomar(), isTrue);
      expect(llamadas, isEmpty);
    });
  });
}
