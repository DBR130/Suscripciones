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

  // Igual que GET /api/guias: catálogo y procesadores.
  final catalogo = CatalogoServicios.fromJson({
    'guias': jsonDecode(File('backend/db/guias.json').readAsStringSync()),
    'procesadores': jsonDecode(File('backend/db/procesadores.json').readAsStringSync()),
  });
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

    test('servicios ambiguos (T2): sin señal, solo con patrón', () {
      // Pedido suelto de comida por Rappi: no es Rappi Pro.
      final pedido = cobro(bancolombia('RAPPI', '32.500,00', '05/10/2026'));
      expect(pedido.servicio, 'Rappi Pro');
      expect(AnalizadorPagos.seleccionarParaEnviar([pedido]), isEmpty);

      // Dos cobros mensuales iguales de Rappi: sí.
      final mensual = [
        cobro(bancolombia('RAPPI', '24.900,00', '05/09/2026')),
        cobro(bancolombia('RAPPI', '24.900,00', '05/10/2026')),
      ];
      expect(AnalizadorPagos.seleccionarParaEnviar(mensual), hasLength(2));

      // Con señal de suscripción, desde el primer cobro.
      final youtube = cobro(bancolombia('GOOGLE *YouTubePremium', '26.900,00', '05/10/2026'));
      expect(AnalizadorPagos.seleccionarParaEnviar([youtube]), [youtube]);

      // Un juego suelto de PlayStation: no.
      final juego = cobro(bancolombia('PLAYSTATION NETWORK', '259.900,00', '12/10/2026'));
      expect(AnalizadorPagos.seleccionarParaEnviar([juego]), isEmpty);
    });

    test('procesadores (T3): solo con patrón y separados por monto', () {
      // El formato del SMS real de Nequi (test/fixtures/sms_reales_nequi_2026_09.json).
      PagoExtraido ebanx(String monto, DateTime llegada) =>
          cobro('NEQUI: Pagaste $monto en SERVICIOS WEB EBANX CO', llegada);
      final pagos = [
        ebanx('19.900,00', DateTime(2026, 9, 16, 12, 43)),
        ebanx('19.900,00', DateTime(2026, 10, 16, 12, 44)),
        ebanx('34.900,00', DateTime(2026, 9, 20, 9, 10)),
        ebanx('34.900,00', DateTime(2026, 10, 20, 9, 11)),
      ];
      expect(pagos.map((p) => p.procesador).toSet(), {'EBANX'});
      expect(AnalizadorPagos.seleccionarParaEnviar(pagos), hasLength(4));
      // Un solo cobro de un procesador no sale (necesita patrón).
      expect(AnalizadorPagos.seleccionarParaEnviar([pagos.first]), isEmpty);
    });

    test('serie de monto exacto dentro de una mezcla de pedidos (DiDi Club, SMS reales)', () {
      PagoExtraido didi(String monto, DateTime llegada) =>
          cobro('NEQUI: Pagaste $monto en DLO*DiDi Food CO Payin', llegada);
      final suscripcion1 = didi('18.900,00', DateTime(2026, 9, 25, 19, 44));
      final suscripcion2 = didi('18.900,00', DateTime(2026, 10, 25, 19, 40));
      final pagos = [
        suscripcion1,
        didi('16.140,00', DateTime(2026, 9, 25, 19, 46)), // domicilio
        didi('18.500,00', DateTime(2026, 10, 10, 13, 5)), // domicilio de monto parecido
        didi('21.000,00', DateTime(2026, 10, 14, 20, 30)),
        suscripcion2,
      ];
      // Solo salen los dos cobros de la serie; los domicilios se quedan en el celular.
      expect(AnalizadorPagos.seleccionarParaEnviar(pagos), [suscripcion1, suscripcion2]);
    });

    test('una serie con un mes sin SMS (61 días) también cuenta (YouTube, SMS reales)', () {
      final junio = cobro(r'Bancolombia: Compraste $13.300,00 en GOOGLE YouTube con tu T.Deb *0000, el 21/06/2026 a las 12:41.');
      final agosto = cobro(r'Bancolombia: Compraste $13.300,00 en GOOGLE YouTube con tu T.Deb *0000, el 21/08/2026 a las 00:42.');
      expect(junio.servicio, 'YouTube Premium');
      expect(AnalizadorPagos.seleccionarParaEnviar([junio, agosto]), [junio, agosto]);
    });

    test('ambiguo por el valor exacto de su precio de referencia: sale con un solo cobro', () {
      final youtube = cobro(r'Bancolombia: Compraste $13.300,00 en GOOGLE YouTube con tu T.Deb *0000, el 21/06/2026 a las 12:41.');
      expect(youtube.coincidePrecioReferencia, isTrue);
      expect(AnalizadorPagos.seleccionarParaEnviar([youtube]), [youtube]);
      // Un alquiler de película en YouTube: otro monto, no sale.
      final alquiler = cobro(r'Bancolombia: Compraste $26.900,00 en GOOGLE YouTube con tu T.Deb *0000, el 02/07/2026 a las 21:00.');
      expect(AnalizadorPagos.seleccionarParaEnviar([alquiler]), isEmpty);

      final club = cobro('NEQUI: Pagaste 18.900,00 en DLO*DiDi Food CO Payin', DateTime(2026, 9, 25, 19, 44));
      expect(club.servicio, 'DiDi Club');
      expect(AnalizadorPagos.seleccionarParaEnviar([club]), [club]);
      final domicilio = cobro('NEQUI: Pagaste 16.140,00 en DLO*DiDi Food CO Payin', DateTime(2026, 9, 25, 19, 46));
      expect(AnalizadorPagos.seleccionarParaEnviar([domicilio]), isEmpty);
    });

    test('YouTube Premium y Google One vuelven sin falsos positivos (casos reales y simulados)', () {
      // Reales: los dos cobros de YouTube (sin "Premium", con un mes sin SMS).
      final youtube = [
        cobro(r'Bancolombia: Compraste $13.300,00 en GOOGLE YouTube con tu T.Deb *0000, el 21/06/2026 a las 12:41.'),
        cobro(r'Bancolombia: Compraste $13.300,00 en GOOGLE YouTube con tu T.Deb *0000, el 21/08/2026 a las 00:42.'),
      ];
      // Google One: SIMULADO (no hay SMS real todavía), formato de Bancolombia.
      final googleOne = [
        cobro(bancolombia('GOOGLE *Google One', '8.500,00', '05/09/2026')),
        cobro(bancolombia('GOOGLE *Google One', '8.500,00', '05/10/2026')),
      ];
      // Falsos positivos que no deben volver: pedido real de Rappi y una compra
      // suelta en Google Play.
      final rappi = cobro(r'Bancolombia: Compraste $30.300,00 en RAPPI COLOMBIA*DL con tu T.Deb *0000, el 21/06/2026 a las 13:24.');
      expect(rappi.servicio, 'Rappi Pro');
      final juego = cobro(bancolombia('GOOGLE *Clash Royale', '22.900,00', '12/10/2026'));

      final seleccion = AnalizadorPagos.seleccionarParaEnviar([...youtube, ...googleOne, rappi, juego]);
      expect(seleccion.map((p) => p.servicio).toSet(), {'YouTube Premium', 'Google One'});
      expect(seleccion, hasLength(4));
    });

    test('un retiro no es un cobro (SMS real)', () {
      final r = parser.interpretar(
        'Bancolombia: Retiraste \$70.000,00 en VIVA_ENVIG7 de tu T.Deb **0000 el 14/06/2026 a las 15:36.',
        recibidaEn: hoy,
      );
      expect(r.esCobro, isFalse);
      expect(r.motivo, 'retiro de dinero');
    });

    test('diagnóstico: decisión y motivo por comercio, igual que la selección', () {
      final pagos = [
        cobro(bancolombia('NETFLIX', '44.900,00', '05/10/2026')),
        cobro(r'Bancolombia: Compraste $13.300,00 en GOOGLE YouTube con tu T.Deb *0000, el 21/06/2026 a las 12:41.'),
        cobro(r'Bancolombia: Compraste $30.300,00 en RAPPI COLOMBIA*DL con tu T.Deb *0000, el 21/06/2026 a las 13:24.'),
        cobro('NEQUI: Pagaste 18.900,00 en DLO*DiDi Food CO Payin', DateTime(2026, 9, 25, 19, 44)),
        cobro('NEQUI: Pagaste 16.140,00 en DLO*DiDi Food CO Payin', DateTime(2026, 9, 25, 19, 46)),
        cobro('NEQUI: Pagaste 18.900,00 en DLO*DiDi Food CO Payin', DateTime(2026, 10, 25, 19, 40)),
        cobro('NEQUI: Pagaste 19.900,00 en SERVICIOS WEB EBANX CO', DateTime(2026, 9, 16, 12, 43)),
        cobro(bancolombia('TIENDAS D1', '18.900,00', '30/10/2026')),
        cobro(bancolombia('GIMNASIO LA 80', '99.900,00', '05/09/2026')),
        cobro(bancolombia('GIMNASIO LA 80', '98.000,00', '18/09/2026')),
        // El mismo cobro de Nequi por la notificación y por el historial.
        cobro(nequiClaude, llegadaNotificacion),
        cobro(nequiClaude, llegadaSms),
      ];
      final d = {for (final c in AnalizadorPagos.diagnosticar(pagos)) c.nombre: c};

      expect(d['Netflix']!.decision, DecisionEscaneo.servicioConocido);
      expect(d['YouTube Premium']!.decision, DecisionEscaneo.precioReferencia);
      expect(d['Rappi Pro']!.decision, DecisionEscaneo.ambiguoSinSenalNiPatron);
      expect(d['DiDi Club']!.decision, DecisionEscaneo.precioReferencia);
      expect(d['DiDi Club']!.cobros, 3);
      expect(d['DiDi Club']!.salen, 2); // los domicilios se quedan
      expect(d['EBANX']!.decision, DecisionEscaneo.procesadorSinPatron);
      expect(d['Tiendas D1']!.decision, DecisionEscaneo.compraSuelta);
      expect(d['Gimnasio La 80']!.decision, DecisionEscaneo.patronRoto);
      expect(d['Claude']!.repetidos, 1);
      expect(d['Claude']!.bancos, {'Nequi'});
      expect(d['Gimnasio La 80']!.montos, [99900, 98000]);
      // Sin texto de SMS: solo campos extraídos.
      expect(d.values.expand((c) => [c.nombre, c.motivo]).join(' '), isNot(contains('Compraste')));

      // Coherente con la selección: salen exactamente los mismos pagos.
      expect(
        d.values.fold<int>(0, (n, c) => n + c.salen),
        AnalizadorPagos.seleccionarParaEnviar(pagos).length,
      );
    });

    test('una compra puntual no sale', () {
      final didi = cobro(bancolombia('TIENDAS D1', '18.900,00', '30/10/2026'));
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
        cobro(bancolombia('TIENDAS D1', '18.900,00', '01/10/2026')),
        cobro(bancolombia('TIENDAS D1', '18.500,00', '13/10/2026')),
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
      final didi = cobro(bancolombia('TIENDAS D1', '18.900,00', '30/10/2026'));
      expect(await almacen.agregar([cobro(nequiClaude, llegadaNotificacion), didi]), 2);
      expect(await almacen.agregar([cobro(nequiClaude, llegadaSms)]), 0);
      expect(await almacen.leer(), hasLength(2));

      final pendientes = await almacen.pendientesDeEnviar();
      expect(pendientes.map((p) => p.comercio), ['Claude']);
      await almacen.marcarEnviados(pendientes);
      expect(await almacen.pendientesDeEnviar(), isEmpty);
    });

    test('un pedido suelto de un servicio ambiguo no sale, ni después de guardarse', () async {
      final almacen = AlmacenPagosLocales(ahora: () => hoy);
      await almacen.agregar([cobro(bancolombia('RAPPI', '32.500,00', '05/10/2026'))]);
      expect(await almacen.pendientesDeEnviar(), isEmpty);
    });

    test('el procesador se conserva al guardarse', () async {
      final almacen = AlmacenPagosLocales(ahora: () => hoy);
      await almacen.agregar([cobro('NEQUI: Pagaste 19.900,00 en SERVICIOS WEB EBANX CO')]);
      expect((await almacen.leer()).single.pago.procesador, 'EBANX');
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
        cobro(bancolombia('TIENDAS D1', '18.900,00', '01/09/2025')), // más de 400 días
        cobro(bancolombia('TIENDAS D1', '18.900,00', '30/10/2026')),
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
      mensaje('sms:3', bancolombia('TIENDAS D1', '18.900,00', '30/10/2026'), DateTime(2026, 10, 30, 8)),
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
      final p = procesador(servicio);
      final r = await p.buscarEnHistorial(alAvanzar: etapas.add);
      // El diagnóstico del último escaneo queda para la pantalla de depuración.
      final diagnostico = {for (final c in p.ultimoDiagnostico.value) c.nombre: c.decision};
      expect(diagnostico['Tiendas D1'], DecisionEscaneo.compraSuelta);
      expect(diagnostico['Netflix'], DecisionEscaneo.servicioConocido);
      expect(etapas, EtapaHistorial.values);
      expect(r.revisadas, 240);
      expect(r.cobros, 5);
      expect(r.enviados, 4);
      expect(r.sospechaSmsOcultos, isFalse);
      expect(
        servicio.enviados.map((p) => p['comercio_normalizado']),
        unorderedEquals(['Netflix', 'Claude', 'Gimnasio La 80', 'Gimnasio La 80']),
      );
      // La compra puntual (Tiendas D1) no sale; el texto de ningún SMS tampoco.
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
