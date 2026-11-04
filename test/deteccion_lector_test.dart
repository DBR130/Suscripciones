import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_suscripciones/Common/AppTheme.dart';
import 'package:flutter_suscripciones/Common/Routers.dart';
import 'package:flutter_suscripciones/deteccion/catalogo_servicios.dart';
import 'package:flutter_suscripciones/deteccion/depuracion_deteccion_page.dart';
import 'package:flutter_suscripciones/deteccion/lector_notificaciones.dart';
import 'package:flutter_suscripciones/deteccion/notificacion_capturada.dart';
import 'package:flutter_suscripciones/services/api_client.dart';
import 'package:flutter_suscripciones/services/auth_service.dart';
import 'package:flutter_suscripciones/services/suscripcion_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const metodos = MethodChannel('subtrack/deteccion');
  const eventos = EventChannel('subtrack/deteccion/eventos');
  final mensajero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final notificacion = {
    'id': 'abc123',
    'paquete': 'com.android.shell',
    'app': 'Shell (simulación con adb)',
    'titulo': 'Bancolombia',
    'texto': 'Bancolombia: Compraste \$19.900,00 en GOOGLE *Crunchyroll con tu T.Deb *0000',
    'recibida_en': DateTime(2026, 10, 23, 7, 20).millisecondsSinceEpoch,
  };

  late List<MethodCall> llamadas;
  late List<Map<String, Object?>> cola;
  late bool descubrimiento;
  late int recuperables;

  setUp(() {
    llamadas = [];
    cola = [Map.of(notificacion)];
    descubrimiento = false;
    recuperables = 0;
    mensajero.setMockMethodCallHandler(metodos, (call) async {
      llamadas.add(call);
      switch (call.method) {
        case 'estado':
          return {
            'permiso': true,
            'conectado': true,
            'es_debug': true,
            'modo_descubrimiento': descubrimiento,
            'ultima_conexion': DateTime(2026, 10, 31, 8, 5).millisecondsSinceEpoch,
            'ultima_desconexion': null,
            'ultima_notificacion': DateTime(2026, 10, 31, 9, 15, 30).millisecondsSinceEpoch,
            'ultimo_resultado': 'guardada',
            'app_sms_paquete': 'com.truecaller',
            'app_sms_nombre': 'Truecaller',
          };
        case 'recuperarActivas':
          return recuperables;
        case 'reconectar':
          return null;
        case 'leerCola':
          return cola;
        case 'borrarDeCola':
          final ids = ((call.arguments as Map)['ids'] as List).cast<String>();
          cola.removeWhere((n) => ids.contains(n['id']));
          return null;
        case 'vaciarCola':
          cola.clear();
          return null;
        case 'configuracion':
          return {
            'apps_permitidas': [
              {'paquete': 'com.android.shell', 'nombre': 'Shell (simulación con adb)'},
            ],
            'palabras_cobro': ['compra', 'pagaste'],
            'palabras_excluidas': ['codigo'],
          };
        case 'modoDescubrimiento':
          descubrimiento = (call.arguments as Map)['activo'] as bool;
          return descubrimiento;
      }
      return null;
    });
  });

  tearDown(() {
    mensajero.setMockMethodCallHandler(metodos, null);
    mensajero.setMockStreamHandler(eventos, null);
  });

  LectorNotificaciones lector() => LectorNotificaciones(disponible: true);

  group('LectorNotificaciones', () {
    test('lee estado, cola y configuración del lado nativo', () async {
      final l = lector();
      final estado = await l.estado();
      expect(estado.permiso, isTrue);
      expect(estado.conectado, isTrue);

      final lista = await l.leerCola();
      expect(lista.single.titulo, 'Bancolombia');
      expect(lista.single.recibidaEn, DateTime(2026, 10, 23, 7, 20));

      final config = await l.configuracion();
      expect(config!.apps.single.paquete, 'com.android.shell');
      expect(config.palabrasExcluidas, ['codigo']);
    });

    test('borra de la cola solo las procesadas', () async {
      cola.add({...notificacion, 'id': 'otra'});
      final l = lector();
      await l.borrarDeCola(['abc123']);
      expect((await l.leerCola()).map((n) => n.id), ['otra']);
      expect(llamadas.where((c) => c.method == 'borrarDeCola').single.arguments, {
        'ids': ['abc123'],
      });
    });

    test('lee las horas de conexión y de la última notificación', () async {
      final estado = await lector().estado();
      expect(estado.ultimaConexion, DateTime(2026, 10, 31, 8, 5));
      expect(estado.ultimaDesconexion, isNull);
      expect(estado.ultimaNotificacion, DateTime(2026, 10, 31, 9, 15, 30));
      expect(estado.ultimoResultado, 'guardada');
    });

    test('recuperarActivas: cuántas se guardaron, o null si el servicio no está conectado', () async {
      final l = lector();
      recuperables = 2;
      expect(await l.recuperarActivas(), 2);
      recuperables = -1; // el servicio está desconectado
      expect(await l.recuperarActivas(), isNull);
    });

    test('sincronizar reconecta y luego recupera de la barra', () async {
      await lector().sincronizar();
      expect(llamadas.map((c) => c.method), ['reconectar', 'recuperarActivas']);
    });

    test('fuera de Android no llama a la parte nativa', () async {
      final l = LectorNotificaciones(disponible: false);
      expect((await l.estado()).permiso, isFalse);
      expect(await l.leerCola(), isEmpty);
      await l.abrirAjustesAcceso();
      expect(llamadas, isEmpty);
    });
  });

  group('EventoDeteccion', () {
    test('guardada trae la notificación completa', () {
      final e = EventoDeteccion.fromMap({'tipo': 'guardada', 'notificacion': notificacion});
      expect(e.tipo, TipoEvento.guardada);
      expect(e.notificacion!.texto, contains('Crunchyroll'));
    });

    test('descubierta y descartada no traen el texto', () {
      final d = EventoDeteccion.fromMap({
        'tipo': 'descubierta',
        'paquete': 'com.whatsapp',
        'titulo': 'Mamá',
        'recibida_en': 0,
      });
      expect(d.notificacion, isNull);
      final x = EventoDeteccion.fromMap({
        'tipo': 'descartada',
        'paquete': 'com.android.shell',
        'titulo': 'Banco',
        'motivo': 'no tiene monto',
        'recibida_en': 0,
      });
      expect(x.motivo, 'no tiene monto');
    });
  });

  test('el comando de simulación escapa el signo de pesos para PowerShell', () {
    expect(comandoSimulacion, contains(r'`$19.900,00'));
    expect(comandoSimulacion, startsWith('adb shell "cmd notification post -S bigtext'));
    // El texto va entre comillas simples para el shell del celular.
    expect(comandoSimulacion, contains("pago1 'Bancolombia: Compraste"));
  });

  testWidgets('la pantalla de depuración muestra estado, apps, cola y eventos en vivo', (tester) async {
    // Alta para que toda la lista (incluida la cola) quede construida.
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    mensajero.setMockStreamHandler(
      eventos,
      MockStreamHandler.inline(onListen: (args, sink) {
        sink.success({
          'tipo': 'descubierta',
          'paquete': 'com.ejemplo.mensajes',
          // Aunque llegara un título (nombre de un contacto), no se muestra.
          'titulo': 'Mamá',
          'recibida_en': DateTime(2026, 10, 31, 9).millisecondsSinceEpoch,
        });
      }),
    );

    // Un SMS que pasó el filtro nativo pero que el parser no reconoce.
    cola.insert(0, {
      ...notificacion,
      'id': 'otra',
      'titulo': '',
      'texto': 'Hola, ya te pagué lo del almuerzo, eran 15.000',
    });

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: DepuracionDeteccionPage(
        lector: lector(),
        cargarCatalogo: () async => const CatalogoServicios([(nombre: 'Crunchyroll', alias: [], ambiguo: false)]),
      ),
    ));
    await tester.pumpAndSettle();

    // Lo que extrajo el parser, debajo de cada entrada de la cola.
    expect(find.text('Catálogo de servicios: 1 (de /api/guias)'), findsOneWidget);
    expect(find.text('EXTRAÍDO POR EL PARSER'), findsOneWidget);
    expect(find.text('Bancolombia'), findsWidgets);
    expect(find.text('19.900 COP'), findsOneWidget);
    expect(find.text('Crunchyroll (servicio conocido)'), findsOneWidget);
    expect(find.text('GOOGLE *Crunchyroll'), findsOneWidget);
    expect(find.text('23/10/2026 07:20 (de llegada)'), findsOneWidget);
    expect(find.text('T.Deb'), findsOneWidget);
    expect(find.text('No es un cobro (no es de un banco conocido)'), findsOneWidget);

    expect(find.text('Depuración: detección'), findsOneWidget);
    expect(find.text('Concedido'), findsOneWidget);
    expect(find.text('Conectado'), findsOneWidget);
    expect(find.text('Última conexión'), findsOneWidget);
    expect(find.text('31/10 08:05:00'), findsOneWidget);
    expect(find.text('Nunca'), findsOneWidget); // última desconexión
    expect(find.text('31/10 09:15:30 (guardada)'), findsOneWidget);
    expect(find.text('com.android.shell · Shell (simulación con adb)'), findsOneWidget);
    expect(find.textContaining('Todavía no hay apps reales'), findsOneWidget);
    expect(find.text('Cola guardada (2)'), findsOneWidget);
    // El comando de simulación también nombra Crunchyroll, pero con la comilla
    // invertida antes del signo de pesos; esto solo está en la cola.
    expect(find.textContaining(r'Compraste $19.900,00 en GOOGLE', findRichText: true), findsOneWidget);

    // Evento en vivo de una app no permitida: paquete sí, texto no.
    expect(find.text('En vivo (1)'), findsOneWidget);
    expect(find.textContaining('com.ejemplo.mensajes', findRichText: true), findsOneWidget);
    expect(find.textContaining('Texto no leído', findRichText: true), findsOneWidget);
    expect(find.textContaining('Mamá', findRichText: true), findsNothing);

    // Modo descubrimiento.
    await tester.tap(find.text('Modo descubrimiento'));
    await tester.pumpAndSettle();
    expect(descubrimiento, isTrue);

    // Vaciar la cola.
    await tester.tap(find.text('Vaciar cola'));
    await tester.pumpAndSettle();
    expect(find.text('Cola guardada (0)'), findsOneWidget);

    // Al salir, el modo descubrimiento se apaga.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(descubrimiento, isFalse);
  });

  testWidgets('al actualizar, avisa cuántas notificaciones recuperó de la barra', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    recuperables = 3;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: DepuracionDeteccionPage(lector: lector()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Se recuperaron 3 de la barra de notificaciones'), findsOneWidget);
  });

  testWidgets('muestra la app de SMS predeterminada detectada', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: DepuracionDeteccionPage(lector: lector()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('App de SMS predeterminada'), findsOneWidget);
    expect(find.text('Truecaller (com.truecaller)'), findsOneWidget);
  });

  group('ruta de depuración', () {
    List<String> rutas({required bool depuracion}) {
      final api = ApiClient();
      final router = Routers.crear(AuthService(api), SuscripcionService(api), depuracion: depuracion);
      return router.configuration.routes.whereType<GoRoute>().map((r) => r.path).toList();
    }

    test('en release (depuracion: false) la ruta no existe', () {
      expect(rutas(depuracion: false), isNot(contains(Routers.depuracionDeteccion)));
    });

    test('en debug sí existe', () {
      expect(rutas(depuracion: true), contains(Routers.depuracionDeteccion));
    });
  });
}
