import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_suscripciones/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storage = FlutterSecureStorage();
  const usuarioJson = {'id': 1, 'nombre': 'Ana', 'correo': 'ana@correo.com'};

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  http.Response json(Object body, int status) => http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json'},
      );

  test('login envía el correo sin espacios y guarda el token', () async {
    late http.Request enviada;
    final service = AuthService(
      storage: storage,
      client: MockClient((req) async {
        enviada = req;
        return json({'token': 'abc', 'usuario': usuarioJson}, 200);
      }),
    );

    final usuario = await service.login('  ana@correo.com ', '123456');

    expect(enviada.url.path, '/api/auth/login');
    expect(jsonDecode(enviada.body), {
      'correo': 'ana@correo.com',
      'password': '123456',
    });
    expect(usuario.nombre, 'Ana');
    expect(await storage.read(key: 'auth_token'), 'abc');
  });

  test('muestra el mensaje de error que envía el servidor', () async {
    final service = AuthService(
      storage: storage,
      client: MockClient(
        (_) async => json({'error': 'Correo o contraseña incorrectos'}, 401),
      ),
    );

    expect(
      () => service.login('ana@correo.com', 'malo00'),
      throwsA(isA<AuthException>().having(
        (e) => e.mensaje,
        'mensaje',
        'Correo o contraseña incorrectos',
      )),
    );
  });

  test('sin conexión lanza "No se pudo conectar con el servidor"', () async {
    final service = AuthService(
      storage: storage,
      client: MockClient((_) async => throw http.ClientException('sin red')),
    );

    expect(
      () => service.registro('Ana', 'ana@correo.com', '123456'),
      throwsA(isA<AuthException>().having(
        (e) => e.mensaje,
        'mensaje',
        AuthService.errorConexion,
      )),
    );
  });

  test('me envía el token y borra la sesión si el servidor la rechaza',
      () async {
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'vencido'});
    String? header;
    final service = AuthService(
      storage: storage,
      client: MockClient((req) async {
        header = req.headers['Authorization'];
        return json({'error': 'Token inválido o expirado'}, 401);
      }),
    );

    expect(await service.haySesionActiva(), isFalse);
    expect(header, 'Bearer vencido');
    expect(await storage.read(key: 'auth_token'), isNull);
  });

  test('sin token guardado no llama al servidor', () async {
    var llamadas = 0;
    final service = AuthService(
      storage: storage,
      client: MockClient((_) async {
        llamadas++;
        return json({}, 200);
      }),
    );

    expect(await service.me(), isNull);
    expect(llamadas, 0);
  });
}
