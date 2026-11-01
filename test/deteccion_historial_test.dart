import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_suscripciones/Common/AppTheme.dart';
import 'package:flutter_suscripciones/Pages/PerfilPage.dart';
import 'package:flutter_suscripciones/deteccion/almacen_pagos_locales.dart';
import 'package:flutter_suscripciones/deteccion/analizador_pagos.dart';
import 'package:flutter_suscripciones/deteccion/catalogo_servicios.dart';
import 'package:flutter_suscripciones/deteccion/compartir_page.dart';
import 'package:flutter_suscripciones/deteccion/escaneo_page.dart';
import 'package:flutter_suscripciones/deteccion/historial_sms.dart';
import 'package:flutter_suscripciones/deteccion/historial_sms_page.dart';
import 'package:flutter_suscripciones/deteccion/lector_notificaciones.dart';
import 'package:flutter_suscripciones/deteccion/parser_pagos.dart';
import 'package:flutter_suscripciones/deteccion/permisos_page.dart';
import 'package:flutter_suscripciones/deteccion/procesador_detecciones.dart';
import 'package:flutter_suscripciones/deteccion/vigilante_deteccion.dart';
import 'package:flutter_suscripciones/models/usuario.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'deteccion_flujo_test.dart' show FakeDeteccionService, vigilanteCorto;
import 'fake_auth_service.dart';

/// Búsqueda en el historial de SMS, análisis en el celular (minimización),
/// sin duplicados entre caminos y "Compartir". Sin celular: la parte nativa
/// se simula con los MethodChannel.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final catalogo = CatalogoServicios.fromJson(
    jsonDecode(File('backend/db/guias.json').readAsStringSync()) as Object,
  );
  final parser = ParserPagos(catalogo);
  final hoy = DateTime(2026, 11, 1, 9);

  PagoExtraido cobro(String texto, [DateTime? llegada]) =>
      parser.interpretar(texto, recibidaEn: llegada ?? hoy).pago!;

  String bancolombia(String comercio, String monto, String fecha) =>
      'Bancolombia: Compraste \$$monto en $comercio con tu T.Deb *0000, el $fecha a las 08:00.';

  const nequiClaude = 'NEQUI: Pagaste 68.139,27 en ANTHROPIC* CLAUDE SUB';
  final llegadaNotificacion = DateTime(2026, 10, 28, 10, 15, 21); // postTime
  final llegadaSms = DateTime(2026, 10, 28, 10, 15, 3); // fecha en el proveedor de SMS

  group('AnalizadorPagos: qué sale del celular', () {
    test('un servicio conocido sale desde el primer cobro', () {
      final netflix = cobro(bancolombia('NETFLIX', '44.900,00', '05/10/2026'));
      expect(netflix.esServicioConocido, isTrue);
      expect(AnalizadorPagos.seleccionarParaEnviar([netflix]), [netflix]);
    });

    test('una compra puntual no sale', () {
      final didi = cobro(bancolombia('DIDI FOOD', '18.900,00', '30/10/2026'));
      expect(AnalizadorPagos.seleccionarParaEnviar([didi]), isEmpty);
    });

    test('un comercio desconocido sale con 2 cobros mensuales de monto similar (±10 %)', () {
      final a = cobro(bancolombia('GIMNASIO LA 80', '95.000,00', '05/09/2026'));
      final b = cobro(bancolombia('GIMNASIO LA 80', '99.900,00', '05/10/2026'));
      expect(AnalizadorPagos.seleccionarParaEnviar([b, a]), [a, b]);

      // Montos muy distintos (más del 10 %): no es la misma suscripción.
      final c = cobro(bancolombia('GIMNASIO LA 80', '150.000,00', '05/10/2026'));
      expect(AnalizadorPagos.seleccionarParaEnviar([a, c]), isEmpty);
    });

    test('periodicidad semanal y anual sí; intervalos irregulares no', () {
      final semanal = [
        for (final d in ['03/10/2026', '10/10/2026', '17/10/2026'])
          cobro(bancolombia('LAVASECO EL SOL', '15.000,00', d)),
      ];
      expect(AnalizadorPagos.seleccionarParaEnviar(semanal), hasLength(3));

      final anual = [
        cobro(bancolombia('DOMINIO WEB SAS', '60.000,00', '20/10/2025')),
        cobro(bancolombia('DOMINIO WEB SAS', '62.000,00', '20/10/2026')),
      ];
      expect(AnalizadorPagos.seleccionarParaEnviar(anual), hasLength(2));

      final irregular = [
        cobro(bancolombia('DIDI FOOD', '18.900,00', '01/10/2026')),
        cobro(bancolombia('DIDI FOOD', '18.500,00', '13/10/2026')),
      ];
      expect(AnalizadorPagos.seleccionarParaEnviar(irregular), isEmpty);
    });

    test('Nequi sin fecha: notificación (postTime) e historial (fecha del SMS) son el mismo cobro', () {
      final porNotificacion = cobro(nequiClaude, llegadaNotificacion);
      final porHistorial = cobro(nequiClaude, llegadaSms);
      expect(porNotificacion.fechaDelMensaje, isFalse);
      expect(AnalizadorPagos.mismoCobro(porNotificacion, porHistorial), isTrue);
      expect(AnalizadorPagos.sinRepetidos([porNotificacion, porHistorial]), hasLength(1));

      // Más de 5 minutos de diferencia: otro cobro.
      final otro = cobro(nequiClaude, llegadaSms.add(const Duration(minutes: 6)));
      expect(AnalizadorPagos.mismoCobro(porNotificacion, otro), isFalse);
    });

    test('con la fecha del mensaje, la hora de llegada no importa y otra fecha es otro cobro', () {
      final texto = bancolombia('NETFLIX', '44.900,00', '05/10/2026');
      expect(AnalizadorPagos.mismoCobro(cobro(texto, DateTime(2026, 10, 5, 8, 1)), cobro(texto, hoy)), isTrue);
      final otraFecha = cobro(bancolombia('NETFLIX', '44.900,00', '05/11/2026'));
      expect(AnalizadorPagos.mismoCobro(cobro(texto), otraFecha), isFalse);
    });
  });

  group('AlmacenPagosLocales', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('no duplica, guarda las compras puntuales y solo deja salir lo seleccionado', () async {
      final almacen = AlmacenPagosLocales(ahora: () => hoy);
      final didi = cobro(bancolombia('DIDI FOOD', '18.900,00', '30/10/2026'));
      expect(await almacen.agregar([cobro(nequiClaude, llegadaNotificacion), didi]), 2);
      expect(await almacen.agregar([cobro(nequiClaude, llegadaSms)]), 0);
      expect(await almacen.leer(), hasLength(2));

      final pendientes = await almacen.pendientesDeEnviar();
      expect(pendientes.map((p) => p.comercio), ['Claude']);
      await almacen.marcarEnviados(pendientes);
      expect(await almacen.pendientesDeEnviar(), isEmpty);
    });

    test('la compra puntual sale cuando se vuelve recurrente', () async {
      final almacen = AlmacenPagosLocales(ahora: () => hoy);
      await almacen.agregar([cobro(bancolombia('GIMNASIO LA 80', '99.900,00', '05/09/2026'))]);
      expect(await almacen.pendientesDeEnviar(), isEmpty);
      await almacen.agregar([cobro(bancolombia('GIMNASIO LA 80', '99.900,00', '05/10/2026'))]);
      expect(await almacen.pendientesDeEnviar(), hasLength(2));
    });

    test('se borran solos a los 400 días y al cerrar sesión', () async {
      final almacen = AlmacenPagosLocales(ahora: () => hoy);
      await almacen.agregar([
        cobro(bancolombia('DIDI FOOD', '18.900,00', '01/09/2025')), // más de 400 días
        cobro(bancolombia('DIDI FOOD', '18.900,00', '30/10/2026')),
      ]);
      expect(await almacen.leer(), hasLength(1));
      await almacen.borrarTodo();
      expect(await almacen.leer(), isEmpty);
    });
  });

  // ─── Canales simulados ────────────────────────────────────────────────

  const canalDeteccion = MethodChannel('subtrack/deteccion');
  const canalSms = MethodChannel('subtrack/historial_sms');
  final mensajero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late bool smsDisponible;
  late bool permisoSms;
  late String respuestaPermiso;
  late List<Map<String, Object>> sms;
  late int smsLeidos;
  late int smsDeEmpresas;
  late int permisosAbiertos;
  late List<Map<String, Object?>> cola;

  Map<String, Object> mensaje(String id, String texto, DateTime fecha) =>
      {'id': id, 'texto': texto, 'fecha': fecha.millisecondsSinceEpoch};

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    smsDisponible = true;
    permisoSms = false;
    respuestaPermiso = 'concedido';
    permisosAbiertos = 0;
    cola = [];
    sms = [
      mensaje('sms:1', bancolombia('NETFLIX', '44.900,00', '05/10/2026'), DateTime(2026, 10, 5, 8)),
      mensaje('sms:2', nequiClaude, llegadaSms),
      mensaje('sms:3', bancolombia('DIDI FOOD', '18.900,00', '30/10/2026'), DateTime(2026, 10, 30, 8)),
      mensaje('sms:4', bancolombia('GIMNASIO LA 80', '95.000,00', '05/09/2026'), DateTime(2026, 9, 5, 8)),
      mensaje('sms:5', bancolombia('GIMNASIO LA 80', '99.900,00', '05/10/2026'), DateTime(2026, 10, 5, 8)),
    ];
    smsLeidos = 240;
    smsDeEmpresas = 37;
    mensajero.setMockMethodCallHandler(canalSms, (call) async {
      switch (call.method) {
        case 'disponible':
          return smsDisponible;
        case 'estadoPermiso':
          return permisoSms ? 'concedido' : 'no_concedido';
        case 'pedirPermiso':
          permisoSms = respuestaPermiso == 'concedido';
          return respuestaPermiso;
        case 'leer':
          return {'mensajes': sms, 'leidos': smsLeidos, 'de_empresas': smsDeEmpresas};
        case 'abrirPermisosApp':
          permisosAbiertos++;
          return true;
      }
      return null;
    });
    mensajero.setMockMethodCallHandler(canalDeteccion, (call) async => switch (call.method) {
          'estado' => {'permiso': true, 'conectado': true, 'es_debug': true, 'modo_descubrimiento': false},
          'recuperarActivas' => 0,
          'leerCola' => cola,
          _ => null,
        });
  });

  tearDown(() {
    mensajero.setMockMethodCallHandler(canalSms, null);
    mensajero.setMockMethodCallHandler(canalDeteccion, null);
  });

  ProcesadorDetecciones procesador(FakeDeteccionService servicio, {AlmacenPagosLocales? almacen}) =>
      ProcesadorDetecciones(
        lector: LectorNotificaciones(disponible: true),
        servicio: servicio,
        cargarCatalogo: () async => catalogo,
        almacen: almacen ?? AlmacenPagosLocales(ahora: () => hoy),
        historial: HistorialSms(plataforma: true),
        esperaConexion: Duration.zero,
        ahora: () => hoy,
      );

  group('buscar en el historial de SMS', () {
    test('envía solo servicios conocidos y comercios recurrentes, sin el texto', () async {
      final servicio = FakeDeteccionService();
      final etapas = <EtapaHistorial>[];
      final r = await procesador(servicio).buscarEnHistorial(alAvanzar: etapas.add);
      expect(etapas, EtapaHistorial.values);
      expect(r.revisadas, 240);
      expect(r.cobros, 5);
      expect(r.enviados, 4);
      expect(r.sospechaSmsOcultos, isFalse);
      expect(
        servicio.enviados.map((p) => p['comercio_normalizado']),
        unorderedEquals(['Netflix', 'Claude', 'Gimnasio La 80', 'Gimnasio La 80']),
      );
      // La compra puntual (DiDi Food) no sale; el texto de ningún SMS tampoco.
      for (final p in servicio.enviados) {
        expect(p.keys, isNot(contains('texto')));
        expect(p.values.join(' '), isNot(contains('Compraste')));
      }
      // Nequi no trae fecha: se usa la del SMS y se marca como aproximada.
      final claude = servicio.enviados.firstWhere((p) => p['comercio_normalizado'] == 'Claude');
      expect(claude['fecha'], '2026-10-28T10:15:03.000');
      expect(claude['fecha_del_mensaje'], isFalse);
    });

    test('repetir la búsqueda no vuelve a enviar nada', () async {
      final servicio = FakeDeteccionService();
      final almacen = AlmacenPagosLocales(ahora: () => hoy);
      await procesador(servicio, almacen: almacen).buscarEnHistorial();
      final r = await procesador(servicio, almacen: almacen).buscarEnHistorial();
      expect(r.enviados, 0);
      expect(servicio.enviados, hasLength(4));
    });

    test('un cobro que ya llegó por la notificación no se repite desde el historial', () async {
      cola = [
        {
          'id': 'n1',
          'paquete': 'com.truecaller',
          'app': 'Truecaller',
          'titulo': '',
          'texto': nequiClaude,
          'recibida_en': llegadaNotificacion.millisecondsSinceEpoch,
        },
      ];
      final servicio = FakeDeteccionService();
      final almacen = AlmacenPagosLocales(ahora: () => hoy);
      await procesador(servicio, almacen: almacen).procesar();
      expect(servicio.enviados.single['fecha'], '2026-10-28T10:15:21.000');

      cola = [];
      await procesador(servicio, almacen: almacen).buscarEnHistorial();
      expect(servicio.enviados.where((p) => p['comercio_normalizado'] == 'Claude'), hasLength(1));
    });

    test('SMS leídos pero ninguno de empresas: posible bloqueo de Xiaomi', () async {
      sms = [];
      smsDeEmpresas = 0;
      final r = await procesador(FakeDeteccionService()).buscarEnHistorial();
      expect(r.sospechaSmsOcultos, isTrue);
    });
  });

  // ─── Pantallas ──────────────────────────────────────────────────────────

  Future<void> abrir(WidgetTester tester, String inicial, Map<String, Widget Function(GoRouterState)> rutas) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final router = GoRouter(initialLocation: inicial, routes: [
      for (final MapEntry(key: ruta, value: pantalla) in rutas.entries)
        GoRoute(path: ruta, builder: (_, state) => pantalla(state)),
    ]);
    await tester.pumpWidget(MaterialApp.router(theme: AppTheme.dark, routerConfig: router));
    await tester.pumpAndSettle();
  }

  Widget destino(String texto) => Scaffold(body: Text(texto));
  String escaneo(GoRouterState s) => 'ESCANEO historial=${s.uri.queryParameters['historial'] ?? '0'}';

  group('divulgación "¿Buscamos suscripciones que ya pagas?"', () {
    Future<void> abrirDivulgacion(WidgetTester tester) => abrir(tester, '/historial-sms', {
          '/historial-sms': (s) => HistorialSmsPage(historial: HistorialSms(plataforma: true), trasPermisos: true),
          '/escaneo': (s) => destino(escaneo(s)),
        });

    testWidgets('explica qué se lee, para qué, qué sale y cómo revocarlo', (tester) async {
      await abrirDivulgacion(tester);
      expect(find.text(HistorialSmsPage.titulo), findsOneWidget);
      for (final (titulo, _) in HistorialSmsPage.puntos) {
        expect(find.text(titulo), findsOneWidget);
      }
      expect(find.textContaining('últimos 6 meses'), findsOneWidget);
      expect(find.textContaining('ajustes de Android'), findsOneWidget);
      expect(find.text('Buscar en mis SMS'), findsOneWidget);
      expect(find.text('Ahora no'), findsOneWidget);
    });

    testWidgets('"Ahora no" no pide el permiso y sigue con las notificaciones', (tester) async {
      await abrirDivulgacion(tester);
      await tester.tap(find.text('Ahora no'));
      await tester.pumpAndSettle();
      expect(find.text('ESCANEO historial=0'), findsOneWidget);
      expect(permisoSms, isFalse);
    });

    testWidgets('con el permiso concedido, busca en el historial', (tester) async {
      await abrirDivulgacion(tester);
      await tester.tap(find.text('Buscar en mis SMS'));
      await tester.pumpAndSettle();
      expect(find.text('ESCANEO historial=1'), findsOneWidget);
    });

    testWidgets('si rechaza el permiso, la app sigue sin problema', (tester) async {
      respuestaPermiso = 'denegado';
      await abrirDivulgacion(tester);
      await tester.tap(find.text('Buscar en mis SMS'));
      await tester.pump();
      expect(find.text('Sin problema: seguimos detectando los cobros nuevos'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('ESCANEO historial=0'), findsOneWidget);
    });

    testWidgets('si Android ya no pregunta, guía a los ajustes', (tester) async {
      respuestaPermiso = 'bloqueado';
      await abrirDivulgacion(tester);
      await tester.tap(find.text('Buscar en mis SMS'));
      await tester.pumpAndSettle();
      expect(find.text('Android ya no muestra la pregunta'), findsOneWidget);
      await tester.tap(find.text('Abrir los permisos de SubTrack'));
      await tester.pumpAndSettle();
      expect(permisosAbiertos, 1);

      // Lo concede en los ajustes y vuelve.
      permisoSms = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('ESCANEO historial=1'), findsOneWidget);
    });
  });

  group('pantalla 03 y versiones', () {
    Future<void> abrirPermisos(WidgetTester tester, VigilanteDeteccion vigilante) => abrir(tester, '/permisos', {
          '/permisos': (s) => PermisosPage(vigilante: vigilante, historial: HistorialSms(plataforma: true)),
          '/historial-sms': (s) => destino('DIVULGACION tras=${s.uri.queryParameters['tras']}'),
          '/escaneo': (s) => destino(escaneo(s)),
        });

    testWidgets('versión completa: tras el acceso a notificaciones ofrece buscar en los SMS', (tester) async {
      await abrirPermisos(tester, vigilanteCorto());
      await tester.tap(find.text('Dar permiso y detectar'));
      await tester.pumpAndSettle();
      expect(find.text('DIVULGACION tras=1'), findsOneWidget);
    });

    testWidgets('versión sinSms: va directo al escaneo de notificaciones', (tester) async {
      smsDisponible = false;
      await abrirPermisos(tester, vigilanteCorto());
      await tester.tap(find.text('Dar permiso y detectar'));
      await tester.pumpAndSettle();
      expect(find.text('ESCANEO historial=0'), findsOneWidget);
    });

    testWidgets('Perfil muestra "Buscar suscripciones en mis SMS" solo en la versión completa', (tester) async {
      await abrir(tester, '/perfil', {
        '/perfil': (s) => PerfilPage(authService: FakeAuthService(), historial: HistorialSms(plataforma: true)),
        '/historial-sms': (s) => destino('DIVULGACION'),
      });
      await tester.tap(find.text('Buscar suscripciones en mis SMS'));
      await tester.pumpAndSettle();
      expect(find.text('DIVULGACION'), findsOneWidget);
    });

    testWidgets('Perfil en la versión sinSms no muestra la opción', (tester) async {
      smsDisponible = false;
      await abrir(tester, '/perfil', {
        '/perfil': (s) => PerfilPage(authService: FakeAuthService(), historial: HistorialSms(plataforma: true)),
      });
      expect(find.text('Buscar suscripciones en mis SMS'), findsNothing);
    });
  });

  group('pantalla 04 con el historial', () {
    testWidgets('revisa los mensajes del banco y pasa a los resultados', (tester) async {
      final servicio = FakeDeteccionService();
      await abrir(tester, '/escaneo', {
        '/escaneo': (s) => EscaneoPage(
              procesador: procesador(servicio),
              historial: true,
              duracionMinima: const Duration(milliseconds: 100),
            ),
        '/deteccion': (s) => destino('RESULTADOS'),
      });
      expect(find.text('RESULTADOS'), findsOneWidget);
      expect(servicio.enviados, hasLength(4));
    });

    testWidgets('sin ningún SMS de empresas, explica el bloqueo de Xiaomi', (tester) async {
      sms = [];
      smsDeEmpresas = 0;
      await abrir(tester, '/escaneo', {
        '/escaneo': (s) => EscaneoPage(procesador: procesador(FakeDeteccionService()), historial: true, duracionMinima: Duration.zero),
        '/deteccion': (s) => destino('RESULTADOS'),
      });
      expect(find.text('Revisando tus mensajes del banco…'), findsOneWidget);
      expect(find.text(EscaneoPage.tituloSmsOcultos), findsOneWidget);
      await tester.tap(find.text('Abrir los permisos de SubTrack'));
      expect(permisosAbiertos, 1);
      await tester.tap(find.text('Ver resultados'));
      await tester.pumpAndSettle();
      expect(find.text('RESULTADOS'), findsOneWidget);
    });
  });

  group('compartir un SMS con SubTrack', () {
    final ana = Usuario(id: 1, nombre: 'Ana', correo: 'ana@prueba.com');

    Future<FakeDeteccionService> abrirCompartido(WidgetTester tester, String texto, {bool conSesion = true}) async {
      final servicio = FakeDeteccionService();
      await abrir(tester, '/compartir', {
        '/compartir': (s) => CompartirPage(
              texto: texto,
              servicio: servicio,
              cargarCatalogo: () async => catalogo,
              almacen: AlmacenPagosLocales(ahora: () => hoy),
              authService: FakeAuthService(usuario: conSesion ? ana : null),
              ahora: () => hoy,
            ),
        '/deteccion': (s) => destino('RESULTADOS'),
        '/suscripcion/:id': (s) => destino('SUSCRIPCION ${s.pathParameters['id']}'),
        '/suscripcion/nueva': (s) => destino('FORMULARIO'),
      });
      return servicio;
    }

    testWidgets('un cobro se muestra y, al usarlo, sale solo con los campos extraídos', (tester) async {
      final servicio = await abrirCompartido(tester, bancolombia('NETFLIX', '44.900,00', '05/10/2026'));
      expect(find.text('Encontramos un cobro'), findsOneWidget);
      expect(find.text('Netflix'), findsOneWidget);
      expect(find.text('\$44.900'), findsOneWidget);
      await tester.tap(find.text('Usar este cobro'));
      await tester.pumpAndSettle();
      expect(find.text('RESULTADOS'), findsOneWidget);
      expect(servicio.compartidos.single['comercio_normalizado'], 'Netflix');
      expect(servicio.compartidos.single.keys, isNot(contains('texto')));
    });

    testWidgets('si ya es una suscripción, registra el cobro en ella', (tester) async {
      final servicio = FakeDeteccionService()
        ..respuestaCompartido = (resultado: 'suscripcion_existente', suscripcionId: 5, candidatoId: null);
      await abrir(tester, '/compartir', {
        '/compartir': (s) => CompartirPage(
              texto: bancolombia('NETFLIX', '44.900,00', '05/10/2026'),
              servicio: servicio,
              cargarCatalogo: () async => catalogo,
              almacen: AlmacenPagosLocales(ahora: () => hoy),
              authService: FakeAuthService(usuario: ana),
            ),
        '/suscripcion/:id': (s) => destino('SUSCRIPCION ${s.pathParameters['id']}'),
      });
      await tester.tap(find.text('Usar este cobro'));
      await tester.pumpAndSettle();
      expect(find.text('SUSCRIPCION 5'), findsOneWidget);
    });

    testWidgets('sin fecha en el texto (Nequi) pide confirmar la fecha', (tester) async {
      await abrirCompartido(tester, nequiClaude);
      expect(find.text('El mensaje no trae la fecha. ¿Cuándo llegó?'), findsOneWidget);
    });

    testWidgets('si no es un cobro, explica por qué y no envía nada', (tester) async {
      final servicio = await abrirCompartido(tester, 'Hola, ¿nos vemos mañana?');
      expect(find.text(CompartirPage.tituloNoReconocido), findsOneWidget);
      expect(find.textContaining('no parece el cobro de un banco'), findsOneWidget);
      expect(servicio.compartidos, isEmpty);
    });

    testWidgets('sin sesión no se puede usar', (tester) async {
      await abrirCompartido(tester, bancolombia('NETFLIX', '44.900,00', '05/10/2026'), conSesion: false);
      expect(find.text('Inicia sesión en SubTrack y vuelve a compartir el mensaje.'), findsOneWidget);
      final boton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Usar este cobro'));
      expect(boton.onPressed, isNull);
    });
  });
}
