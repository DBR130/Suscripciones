import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_suscripciones/deteccion/almacen_pagos_locales.dart';
import 'package:flutter_suscripciones/deteccion/catalogo_servicios.dart';
import 'package:flutter_suscripciones/deteccion/deteccion_service.dart';
import 'package:flutter_suscripciones/deteccion/lector_notificaciones.dart';
import 'package:flutter_suscripciones/deteccion/procesador_detecciones.dart';
import 'package:flutter_suscripciones/deteccion/segundo_plano.dart';
import 'package:flutter_suscripciones/deteccion/turno.dart';
import 'package:flutter_suscripciones/services/api_client.dart';
import 'package:flutter_suscripciones/services/recordatorios_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'deteccion_flujo_test.dart' show FakeDeteccionService, candidato;

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

  group('ejecutarEnSegundoPlano (S10)', () {
    final catalogo = CatalogoServicios.fromJson(jsonDecode(File('backend/db/guias.json').readAsStringSync()) as Object);
    late List<String> metodos;
    late bool turnoLibre;
    late List<ResultadoEscaneo> avisados;
    late List<(String, int, String?)> registros;

    setUp(() {
      metodos = [];
      turnoLibre = true;
      avisados = [];
      registros = [];
      mensajero.setMockMethodCallHandler(canal, (call) async {
        metodos.add(call.method);
        return switch (call.method) {
          'estado' => {'permiso': true, 'conectado': true, 'es_debug': true, 'modo_descubrimiento': false},
          'recuperarActivas' => 0,
          'tomarTurno' => turnoLibre,
          'leerCola' => [
              {
                'id': 'n1',
                'paquete': 'com.google.android.apps.messaging',
                'app': 'Mensajes',
                'titulo': '',
                'texto': r'Bancolombia: Compraste $44.900,00 en NETFLIX con tu T.Deb *0000, el 05/11/2026 a las 08:00.',
                'recibida_en': DateTime(2026, 11, 5, 8, 1).millisecondsSinceEpoch,
              },
            ],
          _ => null,
        };
      });
    });

    Future<ResultadoTarea> ejecutar({String? token = 't', bool catalogoCaido = false, FakeDeteccionService? servicio}) {
      FlutterSecureStorage.setMockInitialValues({'auth_token': ?token});
      final procesador = ProcesadorDetecciones(
        lector: LectorNotificaciones(disponible: true),
        servicio: servicio ?? FakeDeteccionService(),
        cargarCatalogo: () async => catalogoCaido ? throw const ApiException('No se pudo conectar con el servidor') : catalogo,
        almacen: AlmacenPagosLocales(),
        turno: Turno('fondo', disponible: true),
        esperaConexion: Duration.zero,
      );
      return ejecutarEnSegundoPlano(
        api: ApiClient(),
        procesador: procesador,
        avisar: (r) async => avisados.add(r),
        registrar: (resultado, procesados, motivo) async => registros.add((resultado, procesados, motivo)),
      );
    }

    test('sin sesión no procesa y deja la cola intacta', () async {
      expect(await ejecutar(token: null), ResultadoTarea.sinSesion);
      expect(metodos, isNot(contains('leerCola')));
      expect(metodos, isNot(contains('borrarDeCola')));
      expect(registros.single.$1, 'sin sesión');
    });

    test('con el turno ocupado (la app está procesando) no procesa y reintenta', () async {
      turnoLibre = false;
      expect(await ejecutar(), ResultadoTarea.reintentar);
      expect(metodos, isNot(contains('leerCola')));
      expect(registros.single.$1, 'reintento: la app estaba procesando');
    });

    test('si el servidor no responde, la cola queda intacta, reintenta y suelta el turno', () async {
      expect(await ejecutar(catalogoCaido: true), ResultadoTarea.reintentar);
      expect(metodos, isNot(contains('borrarDeCola')));
      expect(metodos.last, 'soltarTurno');
      expect(registros.single, ('reintento', 0, 'No se pudo conectar con el servidor'));
      expect(avisados, isEmpty);
    });

    test('procesa, avisa con las mismas reglas y registra la ejecución', () async {
      final servicio = FakeDeteccionService()
        ..registradosRespuesta = [const PagoRegistrado(servicio: 'Netflix', monto: 44900, moneda: 'COP')];
      expect(await ejecutar(servicio: servicio), ResultadoTarea.ok);
      expect(avisados.single.registrados.single.servicio, 'Netflix');
      expect(registros.single, ('ok', 1, null));
      expect(metodos, containsAllInOrder(['tomarTurno', 'leerCola', 'borrarDeCola', 'soltarTurno']));
    });
  });

  group('avisos del escaneo (S11)', () {
    test('flujo B y pagos registrados, con las mismas reglas de siempre', () {
      final avisos = avisosDelEscaneo(ResultadoEscaneo(
        revisadas: 3,
        cobros: 3,
        candidatosNuevos: [
          candidato(7, 'EBANX', 19900, procesador: 'EBANX'),
          candidato(1, 'Crunchyroll', 19900),
        ],
        registrados: const [PagoRegistrado(servicio: 'Netflix', monto: 49900, moneda: 'COP', montoAnterior: 44900)],
      ));
      expect([for (final a in avisos) (a.titulo, a.payload)], [
        ('Pago procesado por EBANX', 'candidato:7'),
        ('¿Tienes una suscripción a Crunchyroll?', 'candidato:1'),
        ('Cambio de precio', null),
      ]);
      expect(avisos.last.cuerpo, r'Netflix subió de $44.900 a $49.900');
      // Ids distintos: un aviso no reemplaza a otro.
      expect(avisos.map((a) => a.id).toSet(), hasLength(3));
    });

    test('nada que avisar si no hubo candidatos ni pagos registrados', () {
      expect(avisosDelEscaneo(ResultadoEscaneo.vacio), isEmpty);
    });
  });

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
