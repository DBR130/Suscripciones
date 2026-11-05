import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_suscripciones/Common/AppTheme.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_suscripciones/deteccion/almacen_pagos_locales.dart';
import 'package:flutter_suscripciones/deteccion/candidato_suscripcion.dart';
import 'package:flutter_suscripciones/deteccion/catalogo_servicios.dart';
import 'package:flutter_suscripciones/deteccion/deteccion_service.dart';
import 'package:flutter_suscripciones/deteccion/escaneo_page.dart';
import 'package:flutter_suscripciones/deteccion/huella_pago.dart';
import 'package:flutter_suscripciones/deteccion/lector_notificaciones.dart';
import 'package:flutter_suscripciones/deteccion/parser_pagos.dart';
import 'package:flutter_suscripciones/deteccion/permisos_page.dart';
import 'package:flutter_suscripciones/deteccion/procesador_detecciones.dart';
import 'package:flutter_suscripciones/deteccion/resultados_deteccion_page.dart';
import 'package:flutter_suscripciones/deteccion/vigilante_deteccion.dart';
import 'package:flutter_suscripciones/Pages/PerfilPage.dart';
import 'package:flutter_suscripciones/models/suscripcion.dart';
import 'package:flutter_suscripciones/services/api_client.dart';
import 'package:flutter_suscripciones/services/recordatorios_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'fake_auth_service.dart';

/// Backend falso de detecciones: guarda lo que recibe.
class FakeDeteccionService implements DeteccionService {
  FakeDeteccionService({this.lista = const [], this.nuevos = const [], this.error});

  List<CandidatoSuscripcion> lista;
  List<CandidatoSuscripcion> nuevos;
  String? error;
  final List<Map<String, Object>> enviados = [];
  final List<(int, double?, Frecuencia?, String?)> confirmados = [];
  final List<int> descartados = [];

  /// Lo que responde a un cobro compartido, y los que recibió.
  ResultadoCompartido respuestaCompartido = (resultado: 'candidato_nuevo', suscripcionId: null, candidatoId: 9);
  final List<Map<String, Object>> compartidos = [];

  @override
  Future<ResultadoCompartido> enviarCompartido(Map<String, Object> pago) async {
    if (error != null) throw ApiException(error!);
    compartidos.add(pago);
    return respuestaCompartido;
  }

  /// Pagos que el backend "registró" en suscripciones existentes (T8).
  List<PagoRegistrado> registradosRespuesta = [];

  @override
  Future<ResultadoEnvio> enviarPagos(List<Map<String, Object>> pagos) async {
    if (error != null) throw ApiException(error!);
    enviados.addAll(pagos);
    return (nuevos: nuevos, registrados: registradosRespuesta);
  }

  @override
  Future<List<CandidatoSuscripcion>> candidatos() async {
    if (error != null) throw ApiException(error!);
    return lista;
  }

  @override
  Future<Suscripcion> confirmar(int id, {double? monto, Frecuencia? frecuencia, String? nombre}) async {
    confirmados.add((id, monto, frecuencia, nombre));
    return Suscripcion(
      id: id,
      nombreServicio: 'X',
      monto: monto ?? 1,
      frecuencia: frecuencia ?? Frecuencia.mensual,
      fechaProximoCobro: DateTime(2026, 12, 1),
      origen: 'notificacion',
    );
  }

  @override
  Future<void> descartar(int id) async => descartados.add(id);

  /// Para "Detecciones descartadas" (T6) y lo que se restauró.
  List<CandidatoSuscripcion> listaDescartadas = [];
  final List<int> restaurados = [];

  @override
  Future<List<CandidatoSuscripcion>> descartadas() async => listaDescartadas;

  @override
  Future<void> restaurar(int id) async => restaurados.add(id);
}

/// Vigilante con espera corta (el real espera 9 s a que el lector conecte).
VigilanteDeteccion vigilanteCorto() => VigilanteDeteccion(
      LectorNotificaciones(disponible: true),
      espera: const Duration(milliseconds: 200),
      intervalo: const Duration(milliseconds: 50),
    );

CandidatoSuscripcion candidato(int id, String nombre, double monto, {int pagos = 1, String? procesador}) =>
    CandidatoSuscripcion(
      id: id,
      nombre: nombre,
      monto: monto,
      moneda: 'COP',
      frecuencia: Frecuencia.mensual,
      fechaUltimoPago: DateTime(2026, 10, 23),
      banco: 'Bancolombia',
      esServicioConocido: procesador == null,
      numPagos: pagos,
      procesador: procesador,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final catalogo = CatalogoServicios.fromJson(
    jsonDecode(File('backend/db/guias.json').readAsStringSync()) as Object,
  );
  final reales = ((jsonDecode(File('test/fixtures/notificaciones_reales.json').readAsStringSync()) as Map)
          ['notificaciones'] as List)
      .cast<Map>();
  final parser = ParserPagos(catalogo);

  PagoExtraido extraer(String texto, DateTime recibidaEn) =>
      parser.interpretar(texto, recibidaEn: recibidaEn).pago!;

  group('huella del pago', () {
    final nequi = reales[1]['texto'] as String; // sin fecha en el texto
    final bancolombia = reales[0]['texto'] as String; // con fecha y hora
    final postTime = DateTime(2026, 10, 28, 10, 15, 3, 250);

    test('la misma notificación (mismo postTime) da la misma huella, en vivo o desde la barra', () {
      expect(huellaDePago(extraer(nequi, postTime)), huellaDePago(extraer(nequi, postTime)));
      expect(huellaDePago(extraer(nequi, postTime)), matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('sin fecha en el texto, otro postTime es otro cobro', () {
      final otroMes = DateTime(2026, 11, 28, 10, 15, 3, 250);
      expect(huellaDePago(extraer(nequi, postTime)), isNot(huellaDePago(extraer(nequi, otroMes))));
    });

    test('con fecha en el texto, la hora de llegada no cambia la huella', () {
      expect(
        huellaDePago(extraer(bancolombia, DateTime(2026, 10, 23, 7, 21))),
        huellaDePago(extraer(bancolombia, DateTime(2026, 10, 23, 9, 0))),
      );
    });

    test('se calcula con los campos extraídos: si cambia el monto, cambia', () {
      final a = extraer('NEQUI: Pagaste 68.139,27 en ANTHROPIC* CLAUDE SUB', postTime);
      final b = extraer('NEQUI: Pagaste 69.850,50 en ANTHROPIC* CLAUDE SUB', postTime);
      expect(huellaDePago(a), isNot(huellaDePago(b)));
    });

    test('lo que se envía al backend no lleva texto, título ni la tarjeta', () {
      final p = pagoParaEnviar(extraer(bancolombia, DateTime(2026, 10, 23, 7, 21)));
      expect(
        p.keys,
        unorderedEquals(
            ['huella', 'comercio', 'comercio_normalizado', 'monto', 'moneda', 'fecha', 'fecha_del_mensaje', 'banco']),
      );
      expect(p, containsPair('fecha_del_mensaje', true));
      expect(p, containsPair('comercio', 'GOOGLE *Crunchyroll'));
      expect(p, containsPair('comercio_normalizado', 'Crunchyroll'));
      expect(p, containsPair('monto', '19900.00'));
      expect(p, containsPair('fecha', '2026-10-23T07:20:00.000'));
      expect(p.values.join(' '), isNot(contains('0000')));
    });
  });

  group('ProcesadorDetecciones', () {
    const metodos = MethodChannel('subtrack/deteccion');
    final mensajero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<Map<String, Object?>> cola;
    late List<String> borrados;
    late bool permiso;

    Map<String, Object?> entrada(String id, String texto, DateTime recibida) => {
          'id': id,
          'paquete': 'com.google.android.apps.messaging',
          'app': 'Mensajes de Google (SMS)',
          'titulo': '',
          'texto': texto,
          'recibida_en': recibida.millisecondsSinceEpoch,
        };

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      permiso = true;
      borrados = [];
      cola = [
        for (final (i, r) in reales.indexed)
          entrada('n$i', r['texto'] as String, DateTime.parse(r['recibida_en'] as String)),
        // Pasó el filtro nativo (tiene "pago" y monto), pero no es un cobro.
        entrada('personal', 'Ya te hice el pago de 15.000 del almuerzo', DateTime(2026, 10, 30, 20)),
      ];
      mensajero.setMockMethodCallHandler(metodos, (call) async {
        switch (call.method) {
          case 'estado':
            return {'permiso': permiso, 'conectado': true, 'es_debug': true, 'modo_descubrimiento': false};
          case 'recuperarActivas':
            return 0;
          case 'leerCola':
            return cola;
          case 'borrarDeCola':
            borrados.addAll(((call.arguments as Map)['ids'] as List).cast<String>());
            return null;
        }
        return null;
      });
    });

    tearDown(() => mensajero.setMockMethodCallHandler(metodos, null));

    ProcesadorDetecciones procesador(FakeDeteccionService servicio, {bool falla = false}) => ProcesadorDetecciones(
          lector: LectorNotificaciones(disponible: true),
          servicio: servicio,
          cargarCatalogo: () async => falla ? throw const ApiException('sin conexión') : catalogo,
          almacen: AlmacenPagosLocales(),
          esperaConexion: Duration.zero,
        );

    test('envía solo los servicios conocidos y borra de la cola todo lo revisado', () async {
      final servicio = FakeDeteccionService(nuevos: [candidato(1, 'Crunchyroll', 19900), candidato(2, 'Claude', 68139.27)]);
      final r = await procesador(servicio).procesar();
      expect(r.revisadas, 4);
      expect(r.cobros, 3);
      expect(r.enviados, 3);
      expect(r.candidatosNuevos.map((c) => c.nombre), ['Crunchyroll', 'Claude']);
      // DiDi a $18.900 es el valor exacto de DiDi Club: sale para preguntar.
      expect(servicio.enviados.map((p) => p['comercio_normalizado']), ['Crunchyroll', 'Claude', 'DiDi Club']);
      // Nequi no trae fecha: se usa la de llegada (postTime).
      expect(servicio.enviados[1]['fecha'], '2026-10-28T10:15:00.000');
      expect(borrados, ['n0', 'n1', 'n2', 'personal']);
    });

    test('sin catálogo la cola queda intacta; si falla el envío, lo interpretado se reintenta después', () async {
      await expectLater(procesador(FakeDeteccionService(), falla: true).procesar(), throwsA(isA<ApiException>()));
      expect(borrados, isEmpty);

      // El envío falla: el texto crudo sale de la cola (ya se interpretó) y los
      // pagos esperan en el almacén local, sin perderse.
      final servicio = FakeDeteccionService(error: 'No se pudo conectar con el servidor');
      await expectLater(procesador(servicio).procesar(), throwsA(isA<ApiException>()));
      expect(borrados, ['n0', 'n1', 'n2', 'personal']);

      cola = [];
      servicio.error = null;
      final r = await procesador(servicio).procesar();
      expect(r.enviados, 3);
      expect(servicio.enviados.map((p) => p['comercio_normalizado']), ['Crunchyroll', 'Claude', 'DiDi Club']);
    });

    test('con la cola vacía no llama al backend', () async {
      cola = [];
      final servicio = FakeDeteccionService();
      final r = await procesador(servicio).procesar();
      expect(r.revisadas, 0);
      expect(servicio.enviados, isEmpty);
    });

    test('dos llamadas a la vez comparten el mismo procesamiento', () async {
      final servicio = FakeDeteccionService();
      final p = procesador(servicio);
      await Future.wait([p.procesar(), p.procesar()]);
      expect(servicio.enviados.length, 3);
    });
  });

  group('aviso del flujo B', () {
    test('texto y payload', () {
      expect(textoAvisoCandidato(candidato(1, 'Claude', 68139.27)), 'Detectamos un cobro de \$68.139 en Bancolombia. Toca para confirmarla o descartarla.');
      expect(textoAvisoCandidato(candidato(1, 'Smart Fit', 89900, pagos: 3)),
          'Detectamos 3 cobros de \$89.900 con la misma periodicidad. Toca para confirmarla.');
      expect(RecordatoriosService.candidatoDelPayload('candidato:12'), 12);
      expect(RecordatoriosService.candidatoDelPayload('12'), isNull);
      expect(RecordatoriosService.candidatoDelPayload(''), isNull);
    });
  });

  // ─── Pantallas ──────────────────────────────────────────────────────────

  Future<void> abrir(WidgetTester tester, String inicial, Map<String, Widget Function(GoRouterState)> rutas) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final router = GoRouter(initialLocation: inicial, routes: [
      for (final MapEntry(key: ruta, value: pantalla) in rutas.entries)
        GoRoute(path: ruta, builder: (_, state) => pantalla(state)),
    ]);
    await tester.pumpWidget(MaterialApp.router(theme: AppTheme.dark, routerConfig: router));
    await tester.pumpAndSettle();
  }

  Widget destino(String texto) => Scaffold(body: Text(texto));

  group('pantalla 03 Permisos', () {
    const metodos = MethodChannel('subtrack/deteccion');
    final mensajero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late bool permiso;
    late int ajustesAbiertos;

    setUp(() {
      permiso = false;
      ajustesAbiertos = 0;
      mensajero.setMockMethodCallHandler(metodos, (call) async {
        if (call.method == 'estado') {
          return {'permiso': permiso, 'conectado': permiso, 'es_debug': true, 'modo_descubrimiento': false};
        }
        if (call.method == 'abrirAjustesAcceso') ajustesAbiertos++;
        return true;
      });
    });

    tearDown(() => mensajero.setMockMethodCallHandler(metodos, null));

    testWidgets('abre los ajustes; si vuelve sin permiso explica el ajuste restringido, y con permiso pasa al escaneo',
        (tester) async {
      await abrir(tester, '/permisos?inicio=1', {
        '/permisos': (s) => PermisosPage(vigilante: vigilanteCorto(), inicio: true),
        '/escaneo': (s) => destino('ESCANEO inicio=${s.uri.queryParameters['inicio']}'),
      });
      expect(find.text('Permiso para leer notificaciones de pago'), findsOneWidget);
      expect(find.text('No leemos mensajes personales, chats ni el contenido de otras apps.'), findsOneWidget);
      expect(find.text('¿Android no te dejó activarlo?'), findsNothing);

      await tester.tap(find.text('Dar permiso y detectar'));
      await tester.pumpAndSettle();
      expect(ajustesAbiertos, 1);

      // Vuelve de los ajustes sin el permiso (p. ej., "Ajuste restringido").
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('¿Android no te dejó activarlo?'), findsOneWidget);
      expect(find.textContaining('Permitir ajustes restringidos'), findsOneWidget);

      // Lo intenta otra vez y ahora sí lo concede.
      // La tarjeta de ayuda empuja los botones hacia abajo: se desplaza.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dar permiso y detectar'));
      await tester.pumpAndSettle();
      expect(ajustesAbiertos, 2);
      permiso = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('ESCANEO inicio=1'), findsOneWidget);
    });
  });

  group('pantalla 04 Escaneo', () {
    const metodos = MethodChannel('subtrack/deteccion');
    final mensajero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      mensajero.setMockMethodCallHandler(metodos, (call) async => switch (call.method) {
            'estado' => {'permiso': true, 'conectado': true, 'es_debug': true, 'modo_descubrimiento': false},
            'recuperarActivas' => 0,
            'leerCola' => [
                {
                  'id': 'n1',
                  'paquete': 'com.android.shell',
                  'app': 'Shell',
                  'titulo': 'Nequi',
                  'texto': 'NEQUI: Pagaste 68.139,27 en ANTHROPIC* CLAUDE SUB',
                  'recibida_en': DateTime(2026, 10, 28, 10, 15).millisecondsSinceEpoch,
                },
              ],
            _ => null,
          });
    });

    tearDown(() => mensajero.setMockMethodCallHandler(metodos, null));

    ProcesadorDetecciones procesador(FakeDeteccionService s) => ProcesadorDetecciones(
          lector: LectorNotificaciones(disponible: true),
          servicio: s,
          cargarCatalogo: () async => catalogo,
          almacen: AlmacenPagosLocales(),
          esperaConexion: Duration.zero,
        );

    testWidgets('revisa, envía y pasa a los resultados', (tester) async {
      final servicio = FakeDeteccionService();
      await abrir(tester, '/escaneo', {
        '/escaneo': (s) => EscaneoPage(procesador: procesador(servicio), duracionMinima: const Duration(milliseconds: 100)),
        '/deteccion': (s) => destino('RESULTADOS'),
      });
      expect(find.text('RESULTADOS'), findsOneWidget);
      expect(servicio.enviados.single['comercio_normalizado'], 'Claude');
    });

    testWidgets('sin conexión permite reintentar o seguir sin detectar', (tester) async {
      final servicio = FakeDeteccionService(error: 'No se pudo conectar con el servidor');
      await abrir(tester, '/escaneo', {
        '/escaneo': (s) => EscaneoPage(procesador: procesador(servicio), duracionMinima: Duration.zero),
        '/resumen': (s) => destino('DASHBOARD'),
      });
      expect(find.text('Reintentar'), findsOneWidget);
      await tester.tap(find.text('Seguir sin detectar'));
      await tester.pumpAndSettle();
      expect(find.text('DASHBOARD'), findsOneWidget);
    });
  });

  group('Perfil: interruptor "Permiso de notificaciones"', () {
    const metodos = MethodChannel('subtrack/deteccion');
    final mensajero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late bool permiso;

    setUp(() {
      mensajero.setMockMethodCallHandler(metodos, (call) async {
        if (call.method == 'estado') {
          return {'permiso': permiso, 'conectado': permiso, 'es_debug': true, 'modo_descubrimiento': false};
        }
        return true;
      });
    });

    tearDown(() => mensajero.setMockMethodCallHandler(metodos, null));

    Future<void> abrirPerfil(WidgetTester tester) => abrir(tester, '/perfil', {
          '/perfil': (s) => PerfilPage(authService: FakeAuthService(), vigilante: vigilanteCorto()),
          '/permisos': (s) => destino('PERMISOS'),
        });

    testWidgets('refleja el estado real del acceso', (tester) async {
      permiso = true;
      await abrirPerfil(tester);
      expect(find.text('Activo · detección automática encendida'), findsOneWidget);
    });

    testWidgets('apagado: al encenderlo abre la pantalla de permisos', (tester) async {
      permiso = false;
      await abrirPerfil(tester);
      expect(find.text('Desactivado · solo registro manual'), findsOneWidget);
      await tester.tap(find.text('Permiso de notificaciones'));
      await tester.pumpAndSettle();
      expect(find.text('PERMISOS'), findsOneWidget);
    });
  });

  group('pantalla 05 Resultados', () {
    testWidgets('confirma las que son mías (con correcciones) y descarta las demás', (tester) async {
      final servicio = FakeDeteccionService(lista: [
        candidato(1, 'Crunchyroll', 19900, pagos: 2),
        candidato(2, 'Claude', 68139.27),
      ]);
      await abrir(tester, '/deteccion', {
        '/deteccion': (s) => ResultadosDeteccionPage(servicio: servicio),
        '/resumen': (s) => destino('DASHBOARD'),
      });

      expect(find.text('Encontramos 2 suscripciones'), findsOneWidget);
      expect(find.text('Datos de ejemplo · provisional'), findsNothing);
      expect(find.text('\$19.900 · Mensual · 2 cobros detectados'), findsOneWidget);
      expect(find.text('\$68.139 · Mensual · 1 cobro detectado'), findsOneWidget);
      expect(find.text('Confirmar 2 suscripciones'), findsOneWidget);

      // Claude no es mía: se descarta al instante.
      await tester.tap(find.text('No es mía').at(1));
      await tester.pumpAndSettle();
      expect(servicio.descartados, [2]);
      expect(find.text('Confirmar 1 suscripción'), findsOneWidget);

      // Corrige Crunchyroll: otro monto y anual.
      await tester.tap(find.byTooltip('Corregir nombre, monto y frecuencia').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('campo-monto')), '21.900');
      await tester.tap(find.text('Anual'));
      await tester.tap(find.text('Guardar corrección'));
      await tester.pumpAndSettle();
      expect(find.text('\$21.900 · Anual · 2 cobros detectados'), findsOneWidget);
      expect(find.text('Corregida por ti'), findsOneWidget);

      await tester.tap(find.text('Confirmar 1 suscripción'));
      await tester.pumpAndSettle();
      expect(servicio.confirmados, [(1, 21900.0, Frecuencia.anual, null)]);
      expect(servicio.descartados, [2]);
      expect(find.text('DASHBOARD'), findsOneWidget);
    });

    testWidgets('en el registro sigue la preferencia de recordatorio', (tester) async {
      final servicio = FakeDeteccionService(lista: [candidato(1, 'Crunchyroll', 19900)]);
      await abrir(tester, '/deteccion', {
        '/deteccion': (s) => ResultadosDeteccionPage(servicio: servicio, inicio: true),
        '/preferencias': (s) => destino('PREFERENCIAS'),
      });
      expect(find.text('PRIMERA DETECCIÓN'), findsOneWidget);
      await tester.tap(find.text('Confirmar 1 suscripción'));
      await tester.pumpAndSettle();
      expect(servicio.confirmados, [(1, null, null, null)]);
      expect(find.text('PREFERENCIAS'), findsOneWidget);
    });

    testWidgets('sin candidatos lo dice', (tester) async {
      await abrir(tester, '/deteccion', {
        '/deteccion': (s) => ResultadosDeteccionPage(servicio: FakeDeteccionService()),
      });
      expect(find.text('Encontramos 0 suscripciones'), findsOneWidget);
      expect(find.text('No encontramos suscripciones nuevas'), findsOneWidget);
      expect(find.text('Continuar'), findsOneWidget);
    });
  });
}
