import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_suscripciones/deteccion/almacen_pagos_locales.dart';
import 'package:flutter_suscripciones/deteccion/aviso_segundo_plano.dart';
import 'package:flutter_suscripciones/deteccion/catalogo_servicios.dart';
import 'package:flutter_suscripciones/deteccion/lector_notificaciones.dart';
import 'package:flutter_suscripciones/deteccion/notificacion_capturada.dart';
import 'package:flutter_suscripciones/deteccion/procesador_detecciones.dart';
import 'package:flutter_suscripciones/deteccion/turno.dart';
import 'package:flutter_test/flutter_test.dart';

import 'deteccion_flujo_test.dart' show FakeDeteccionService;

/// Encargo C, punto 5: el aviso "Tu celular cerró SubTrack…" sale solo si el
/// lector estaba desconectado al abrir la app y el rescate desde la barra trajo
/// al menos un cobro NUEVO, como máximo una vez por semana.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final lunes = DateTime(2026, 11, 2, 9);

  group('regla de la semana', () {
    test('sin falla pendiente no se muestra', () {
      expect(debeMostrarAvisoSegundoPlano(fallaPendiente: null, ultimoAviso: null, ahora: lunes), isFalse);
    });

    test('falla pendiente y nunca se mostró: se muestra', () {
      expect(debeMostrarAvisoSegundoPlano(fallaPendiente: lunes, ultimoAviso: null, ahora: lunes), isTrue);
    });

    test('la semana cuenta desde el último aviso mostrado', () {
      final aviso = lunes.subtract(const Duration(days: 6, hours: 23));
      expect(debeMostrarAvisoSegundoPlano(fallaPendiente: lunes, ultimoAviso: aviso, ahora: lunes), isFalse);
      final haceSiete = lunes.subtract(const Duration(days: 7));
      expect(debeMostrarAvisoSegundoPlano(fallaPendiente: lunes, ultimoAviso: haceSiete, ahora: lunes), isTrue);
    });
  });

  group('ControlSegundoPlano', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    ControlSegundoPlano control(DateTime ahora) => ControlSegundoPlano(ahora: () => ahora);

    test('con una falla pendiente muestra el aviso, anota la fecha y consume la falla', () async {
      await RegistroSegundoPlano().anotarFalla(lunes);
      final c = control(lunes);
      expect(await c.revisar(), isTrue);
      expect(c.avisoVisible.value, isTrue);
      expect(await RegistroSegundoPlano().ultimoAviso(), lunes);
      expect(await RegistroSegundoPlano().fallaPendiente(), isNull);
    });

    test('dentro de la semana la falla se consume sin mostrar nada (no se acumula)', () async {
      final registro = RegistroSegundoPlano();
      await registro.marcarAvisoMostrado(lunes);
      final martes = lunes.add(const Duration(days: 1));
      await registro.anotarFalla(martes);
      expect(await control(martes).revisar(), isFalse);
      expect(await registro.fallaPendiente(), isNull);
      // Pasada la semana, esa falla vieja ya no hace salir el aviso.
      expect(await control(lunes.add(const Duration(days: 8))).revisar(), isFalse);
    });

    test('sin falla no muestra nada', () async {
      expect(await control(lunes).revisar(), isFalse);
    });

    test('cerrar lo oculta y ya cuenta como mostrado', () async {
      await RegistroSegundoPlano().anotarFalla(lunes);
      final c = control(lunes);
      await c.revisar();
      c.cerrar();
      expect(c.avisoVisible.value, isFalse);
      await RegistroSegundoPlano().anotarFalla(lunes.add(const Duration(days: 2)));
      expect(await control(lunes.add(const Duration(days: 2))).revisar(), isFalse);
    });

    test('"Ya lo activé" guarda la fecha, pero no impide un aviso futuro (punto 4)', () async {
      final registro = RegistroSegundoPlano();
      await registro.marcarGuiaVista(lunes);
      expect(await registro.guiaVista(), lunes);
      await registro.anotarFalla(lunes.add(const Duration(days: 1)));
      expect(await control(lunes.add(const Duration(days: 1))).revisar(), isTrue);
    });

    test('forzar (depuración) lo muestra aunque no haya falla', () async {
      final c = control(lunes);
      await c.forzar();
      expect(c.avisoVisible.value, isTrue);
      expect(await RegistroSegundoPlano().ultimoAviso(), lunes);
    });
  });

  group('rescate tardío en el procesador', () {
    const metodos = MethodChannel('subtrack/deteccion');
    final mensajero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final catalogo = CatalogoServicios.fromJson(
      jsonDecode(File('backend/db/guias.json').readAsStringSync()) as Object,
    );
    final reales = ((jsonDecode(File('test/fixtures/notificaciones_reales.json').readAsStringSync()) as Map)
            ['notificaciones'] as List)
        .cast<Map>();
    late List<Map<String, Object?>> cola;

    Map<String, Object?> entrada(int i, {required bool tardio}) => {
          'id': 'n$i',
          'paquete': 'com.google.android.apps.messaging',
          'app': 'Mensajes de Google (SMS)',
          'titulo': '',
          'texto': reales[i]['texto'],
          'recibida_en': DateTime.parse(reales[i]['recibida_en'] as String).millisecondsSinceEpoch,
          if (tardio) 'rescate_tardio': true,
        };

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      mensajero.setMockMethodCallHandler(metodos, (call) async {
        switch (call.method) {
          case 'estado':
            return {'permiso': true, 'conectado': true, 'es_debug': true, 'modo_descubrimiento': false};
          case 'recuperarActivas':
            return 0;
          case 'leerCola':
            return cola;
        }
        return null;
      });
    });

    tearDown(() => mensajero.setMockMethodCallHandler(metodos, null));

    ProcesadorDetecciones procesador() => ProcesadorDetecciones(
          lector: LectorNotificaciones(disponible: true),
          turno: Turno('app', disponible: false),
          servicio: FakeDeteccionService(),
          cargarCatalogo: () async => catalogo,
          almacen: AlmacenPagosLocales(),
          esperaConexion: Duration.zero,
          ahora: () => lunes,
        );

    test('la cola trae la marca del rescate tardío', () {
      final n = NotificacionCapturada.fromMap(entrada(0, tardio: true));
      expect(n.rescateTardio, isTrue);
      expect(NotificacionCapturada.fromMap(entrada(0, tardio: false)).rescateTardio, isFalse);
    });

    test('un cobro nuevo rescatado tarde anota la falla', () async {
      cola = [entrada(0, tardio: true)];
      final r = await procesador().procesar();
      expect(r.rescatadosTarde, 1);
      expect(await RegistroSegundoPlano().fallaPendiente(), lunes);
    });

    test('un cobro rescatado que ya estaba en el celular no cuenta', () async {
      cola = [entrada(0, tardio: false)];
      await procesador().procesar();
      // La misma notificación sigue en la barra y se rescata otra vez al reabrir.
      cola = [entrada(0, tardio: true)];
      final r = await procesador().procesar();
      expect(r.rescatadosTarde, 0);
      expect(await RegistroSegundoPlano().fallaPendiente(), isNull);
    });

    test('cobros nuevos sin la marca (lector conectado) no anotan falla', () async {
      cola = [entrada(0, tardio: false), entrada(1, tardio: false)];
      final r = await procesador().procesar();
      expect(r.rescatadosTarde, 0);
      expect(await RegistroSegundoPlano().fallaPendiente(), isNull);
    });
  });
}
