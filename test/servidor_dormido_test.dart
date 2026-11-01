import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_suscripciones/Common/AppTheme.dart';
import 'package:flutter_suscripciones/services/api_client.dart';
import 'package:flutter_suscripciones/widgets/aviso_despertando.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Servidor que se duerme (Render gratuito): con tiempos cortos para el test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  late int llamadas;
  late List<bool> avisos;

  /// [demoras]: cuánto tarda en responder cada llamada, en orden.
  ApiClient cliente(List<Duration> demoras) {
    llamadas = 0;
    avisos = [];
    final api = ApiClient(
      client: MockClient((request) async {
        final demora = demoras[llamadas++];
        await Future<void>.delayed(demora);
        return http.Response(jsonEncode({'ok': true}), 200);
      }),
      timeoutNormal: const Duration(milliseconds: 150),
      timeoutDespertar: const Duration(milliseconds: 900),
      avisoDespertarTras: const Duration(milliseconds: 40),
    );
    api.despertando.addListener(() => avisos.add(api.despertando.value));
    return api;
  }

  test('la primera petición espera más y avisa que el servidor está despertando', () async {
    final api = cliente([const Duration(milliseconds: 400)]);
    expect(await api.get('/api/health', autenticado: false), {'ok': true});
    expect(avisos, [true, false]); // apareció el aviso y se quitó al responder
    expect(api.despertando.value, isFalse);
  });

  test('con el servidor despierto, una petición lenta usa el límite normal y no avisa', () async {
    final api = cliente([Duration.zero, const Duration(milliseconds: 400)]);
    await api.get('/api/health', autenticado: false);
    await expectLater(
      api.get('/api/health', autenticado: false),
      throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', ApiClient.errorConexion)),
    );
    expect(avisos, isEmpty);
  });

  test('si no despierta a tiempo, lo dice (y no reintenta la petición)', () async {
    final api = cliente([const Duration(seconds: 2)]);
    await expectLater(
      api.post('/api/auth/registro', {'nombre': 'Ana'}, autenticado: false),
      throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', ApiClient.errorDespertar)),
    );
    // Un reintento podría crear la cuenta dos veces cuando el servidor despierte.
    expect(llamadas, 1);
    expect(api.despertando.value, isFalse);
  });

  test('una respuesta rápida no muestra el aviso', () async {
    final api = cliente([Duration.zero]);
    await api.get('/api/health', autenticado: false);
    expect(avisos, isEmpty);
  });

  test('sin red (conexión rechazada) sigue siendo "No se pudo conectar"', () async {
    final api = ApiClient(
      client: MockClient((_) async => throw http.ClientException('Connection refused')),
      avisoDespertarTras: const Duration(seconds: 5),
    );
    await expectLater(
      api.get('/api/health', autenticado: false),
      throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', ApiClient.errorConexion)),
    );
  });

  testWidgets('el aviso aparece sobre la pantalla mientras despierta', (tester) async {
    final despertando = ValueNotifier(false);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: AvisoDespertando(despertando: despertando, child: const Scaffold(body: Text('LOGIN'))),
    ));
    expect(find.text(ApiClient.mensajeDespertando), findsNothing);
    despertando.value = true;
    await tester.pump();
    expect(find.text(ApiClient.mensajeDespertando), findsOneWidget);
    expect(find.text('LOGIN'), findsOneWidget);
    despertando.value = false;
    await tester.pump();
    expect(find.text(ApiClient.mensajeDespertando), findsNothing);
  });
}
