import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_suscripciones/Common/AppTheme.dart';
import 'package:flutter_suscripciones/deteccion/depuracion_deteccion_page.dart';
import 'package:flutter_suscripciones/deteccion/lector_notificaciones.dart';
import 'package:flutter_suscripciones/deteccion/notificacion_capturada.dart';
import 'package:flutter_test/flutter_test.dart';

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

  setUp(() {
    llamadas = [];
    cola = [Map.of(notificacion)];
    descubrimiento = false;
    mensajero.setMockMethodCallHandler(metodos, (call) async {
      llamadas.add(call);
      switch (call.method) {
        case 'estado':
          return {'permiso': true, 'conectado': true, 'es_debug': true, 'modo_descubrimiento': descubrimiento};
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
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    mensajero.setMockStreamHandler(
      eventos,
      MockStreamHandler.inline(onListen: (args, sink) {
        sink.success({
          'tipo': 'descubierta',
          'paquete': 'com.ejemplo.mensajes',
          'titulo': 'Bancolombia',
          'recibida_en': DateTime(2026, 10, 31, 9).millisecondsSinceEpoch,
        });
      }),
    );

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: DepuracionDeteccionPage(lector: lector()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Depuración: detección'), findsOneWidget);
    expect(find.text('Concedido'), findsOneWidget);
    expect(find.text('Conectado'), findsOneWidget);
    expect(find.text('com.android.shell · Shell (simulación con adb)'), findsOneWidget);
    expect(find.textContaining('Todavía no hay apps reales'), findsOneWidget);
    expect(find.text('Cola guardada (1)'), findsOneWidget);
    // El comando de simulación también nombra Crunchyroll, pero con la comilla
    // invertida antes del signo de pesos; esto solo está en la cola.
    expect(find.textContaining(r'Compraste $19.900,00 en GOOGLE', findRichText: true), findsOneWidget);

    // Evento en vivo de una app no permitida: paquete sí, texto no.
    expect(find.text('En vivo (1)'), findsOneWidget);
    expect(find.textContaining('com.ejemplo.mensajes', findRichText: true), findsOneWidget);
    expect(find.textContaining('Texto no leído', findRichText: true), findsOneWidget);

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
}
