import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_suscripciones/models/suscripcion.dart';
import 'package:flutter_suscripciones/services/api_client.dart';
import 'package:flutter_suscripciones/services/suscripcion_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'}));

  const netflixJson = {
    'id': 7,
    'nombre_servicio': 'Netflix',
    'monto': 38900,
    'moneda': 'COP',
    'frecuencia': 'mensual',
    'fecha_proximo_cobro': '2026-11-20',
    'es_prueba_gratis': false,
    'fecha_fin_prueba': null,
    'dias_aviso': null,
    'origen': 'manual',
    'estado': 'activa',
    'fecha_deteccion': null,
    'creado_en': '2026-10-24T22:10:00.000Z',
  };

  http.Response json(Object body, [int status = 200]) => http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json'},
      );

  late List<http.Request> peticiones;

  SuscripcionService servicio(Future<http.Response> Function(http.Request) handler) {
    peticiones = [];
    final api = ApiClient(
      client: MockClient((req) {
        peticiones.add(req);
        return handler(req);
      }),
      storage: const FlutterSecureStorage(),
    );
    return SuscripcionService(api);
  }

  test('listar envía el token y el filtro de estados', () async {
    final service = servicio((_) async => json({'suscripciones': [netflixJson]}));

    final lista = await service.listar(estados: const [
      EstadoSuscripcion.activa,
      EstadoSuscripcion.marcadaParaCancelar,
    ]);

    final req = peticiones.single;
    expect(req.url.path, '/api/suscripciones');
    expect(req.url.queryParameters['estado'], 'activa,marcada_para_cancelar');
    expect(req.headers['Authorization'], 'Bearer tok');

    final s = lista.single;
    expect(s.id, 7);
    expect(s.monto, 38900);
    expect(s.frecuencia, Frecuencia.mensual);
    expect(s.fechaProximoCobro, DateTime(2026, 11, 20));
    expect(s.diasAviso, isNull);
    expect(s.estado, EstadoSuscripcion.activa);
  });

  test('crear envía los campos en el formato del backend', () async {
    final service = servicio((_) async => json({'suscripcion': netflixJson}, 201));

    await service.crear(Suscripcion(
      nombreServicio: 'GeForce NOW',
      monto: 12.5,
      moneda: 'USD',
      frecuencia: Frecuencia.semanal,
      fechaProximoCobro: DateTime(2026, 12, 1),
      esPruebaGratis: true,
      fechaFinPrueba: DateTime(2026, 11, 30),
      diasAviso: 7,
    ));

    final req = peticiones.single;
    expect(req.method, 'POST');
    expect(jsonDecode(req.body), {
      'nombre_servicio': 'GeForce NOW',
      'monto': 12.5,
      'moneda': 'USD',
      'frecuencia': 'semanal',
      'fecha_proximo_cobro': '2026-12-01',
      'es_prueba_gratis': true,
      'fecha_fin_prueba': '2026-11-30',
      'dias_aviso': 7,
    });
  });

  test('actualizar, cambiar estado y eliminar usan la ruta con id', () async {
    final service = servicio((req) async {
      if (req.method == 'DELETE') return http.Response('', 204);
      return json({'suscripcion': {...netflixJson, 'estado': 'marcada_para_cancelar'}});
    });
    final netflix = Suscripcion.fromJson(netflixJson);

    await service.actualizar(netflix);
    final marcada = await service.cambiarEstado(7, EstadoSuscripcion.marcadaParaCancelar);
    await service.eliminar(7);

    expect(peticiones.map((r) => '${r.method} ${r.url.path}'), [
      'PUT /api/suscripciones/7',
      'PATCH /api/suscripciones/7/estado',
      'DELETE /api/suscripciones/7',
    ]);
    expect(jsonDecode(peticiones[1].body), {'estado': 'marcada_para_cancelar'});
    expect(marcada.estado, EstadoSuscripcion.marcadaParaCancelar);
  });

  test('resumen lee totales por moneda y listas', () async {
    final service = servicio((_) async => json({
          'totales': [
            {'moneda': 'COP', 'gasto_mensual': 58900, 'proyeccion_anual': 706800, 'cantidad': 2},
            {'moneda': 'USD', 'gasto_mensual': 43.33, 'proyeccion_anual': 520, 'cantidad': 1},
          ],
          'cantidad_activas': 3,
          'proximos_cobros': [{...netflixJson, 'dias_restantes': 2}],
          'pruebas_por_terminar': [],
          'dias_anticipacion_recordatorio': 7,
        }));

    final r = await service.resumen();

    expect(r.totales.map((t) => t.moneda), ['COP', 'USD']);
    expect(r.totales[1].gastoMensual, 43.33);
    expect(r.cantidadActivas, 3);
    expect(r.proximosCobros.single.nombreServicio, 'Netflix');
    expect(r.diasAnticipacion, 7);
  });

  test('404 de otra cuenta llega como mensaje sin cerrar sesión', () async {
    final service = servicio((_) async => json({'error': 'Suscripción no encontrada'}, 404));

    await expectLater(
      service.obtener(99),
      throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', 'Suscripción no encontrada')),
    );
    expect(await const FlutterSecureStorage().read(key: 'auth_token'), 'tok');
  });

  test('token vencido: borra el token y avisa para volver al login', () async {
    var avisos = 0;
    final api = ApiClient(
      client: MockClient((_) async => json({'error': 'Token inválido o expirado'}, 401)),
      storage: const FlutterSecureStorage(),
    )..onSesionExpirada = () => avisos++;

    await expectLater(
      SuscripcionService(api).listar(),
      throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', ApiClient.errorSesionExpirada)),
    );
    expect(avisos, 1);
    expect(await const FlutterSecureStorage().read(key: 'auth_token'), isNull);
  });
}
