import 'package:flutter/material.dart';
import 'package:flutter_suscripciones/Common/AppTheme.dart';
import 'package:flutter_suscripciones/Common/Routers.dart';
import 'package:flutter_suscripciones/Pages/PerfilPage.dart';
import 'package:flutter_suscripciones/Pages/TextosLegalesPage.dart';
import 'package:flutter_suscripciones/Pages/perfil_cabecera.dart';
import 'package:flutter_suscripciones/models/resumen.dart';
import 'package:flutter_suscripciones/models/usuario.dart';
import 'package:flutter_suscripciones/textos/textos_legales.dart';
import 'package:flutter_suscripciones/utils/formato.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'fake_auth_service.dart';
import 'fake_suscripcion_service.dart';

Resumen resumen(List<TotalMoneda> totales, {int activas = 0}) => Resumen(
      totales: totales,
      cantidadActivas: activas,
      proximosCobros: const [],
      pruebasPorTerminar: const [],
      diasAnticipacion: 3,
    );

TotalMoneda total(String moneda, double mensual) =>
    TotalMoneda(moneda: moneda, gastoMensual: mensual, proyeccionAnual: mensual * 12, cantidad: 1);

/// Resumen con montos largos en COP y USD (el caso más ancho de la cabecera).
class _DosMonedas extends FakeSuscripcionService {
  @override
  Future<Resumen> resumen() async => _resumen([total('COP', 1234567), total('USD', 1234.56)], activas: 12);
}

Resumen _resumen(List<TotalMoneda> totales, {int activas = 0}) => resumen(totales, activas: activas);

void main() {
  group('datos de la cabecera del Perfil', () {
    test('mientras carga (o si el servidor no responde) muestra guiones', () {
      expect(datosCabeceraPerfil(null), [
        (valor: '—', etiqueta: 'Activas'),
        (valor: '—', etiqueta: 'Gasto mensual'),
      ]);
    });

    test('sin suscripciones: cero y \$0', () {
      expect(datosCabeceraPerfil(resumen(const [])), [
        (valor: '0', etiqueta: 'Activas'),
        (valor: Formato.moneda(0, 'COP'), etiqueta: 'Gasto mensual'),
      ]);
    });

    test('una sola moneda: un solo gasto, sin la moneda en la etiqueta', () {
      expect(datosCabeceraPerfil(resumen([total('COP', 45900)], activas: 3)), [
        (valor: '3', etiqueta: 'Activas'),
        (valor: Formato.moneda(45900, 'COP'), etiqueta: 'Gasto mensual'),
      ]);
    });

    test('COP y USD van aparte, COP primero (sin convertir)', () {
      expect(datosCabeceraPerfil(resumen([total('USD', 19.99), total('COP', 45900)], activas: 9)), [
        (valor: '9', etiqueta: 'Activas'),
        (valor: Formato.moneda(45900, 'COP'), etiqueta: 'Gasto mensual COP'),
        (valor: Formato.moneda(19.99, 'USD'), etiqueta: 'Gasto mensual USD'),
      ]);
    });
  });

  group('pantalla de Perfil', () {
    final ana = Usuario(id: 1, nombre: 'Ana Gómez', correo: 'ana@prueba.com');

    Future<void> abrir(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 6000);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp.router(
        theme: AppTheme.dark,
        routerConfig: GoRouter(initialLocation: '/perfil', routes: [
          GoRoute(
            path: '/perfil',
            builder: (_, _) => PerfilPage(
              authService: FakeAuthService(usuario: ana),
              version: () async => 'Versión 1.0.0 (1)',
            ),
          ),
          GoRoute(
            path: Routers.privacidad,
            builder: (_, _) =>
                const TextoLegalPage(titulo: tituloPrivacidad, aviso: avisoPrivacidad, secciones: textoPrivacidad),
          ),
          GoRoute(
            path: Routers.terminos,
            builder: (_, _) => const TextoLegalPage(titulo: tituloTerminos, secciones: textoTerminos),
          ),
          GoRoute(
            path: Routers.datosGuardados,
            builder: (_, _) => const TextoLegalPage(titulo: tituloDatos, secciones: textoDatos),
          ),
          GoRoute(
            path: Routers.acercaDe,
            builder: (_, _) => AcercaDePage(version: () async => 'Versión 1.0.0 (1)'),
          ),
        ]),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('cabecera, secciones y versión al pie', (tester) async {
      await abrir(tester);
      expect(find.text('Ana Gómez'), findsOneWidget);
      expect(find.text('ana@prueba.com'), findsOneWidget);
      expect(find.text('Colombia · COP'), findsOneWidget);
      // Sin servicio de suscripciones (o sin respuesta): guiones.
      expect(find.text('Activas'), findsOneWidget);
      expect(find.text('—'), findsNWidgets(2));
      for (final titulo in ['AVISOS', 'DETECCIÓN AUTOMÁTICA', 'PRIVACIDAD Y LEGAL', 'ACERCA DE']) {
        expect(find.text(titulo), findsOneWidget);
      }
      expect(find.text('1 día antes'), findsNothing);
      expect(find.text('3 días antes'), findsOneWidget);
      expect(find.text('Cerrar sesión'), findsOneWidget);
      expect(find.text('SubTrack · Versión 1.0.0 (1)'), findsOneWidget);
      // Sin el historial de SMS (versión sinSms o fuera de Android) no aparece.
      expect(find.text('Buscar suscripciones en mis SMS'), findsNothing);
    });

    for (final (fila, titulo) in [
      ('Política de privacidad', tituloPrivacidad),
      ('Términos de uso', tituloTerminos),
      ('Qué datos guardamos', tituloDatos),
      ('Acerca de SubTrack', tituloAcercaDe),
    ]) {
      testWidgets('"$fila" abre su pantalla y "Volver" regresa', (tester) async {
        await abrir(tester);
        await tester.tap(find.text(fila));
        await tester.pumpAndSettle();
        expect(find.text(titulo), findsOneWidget);
        await tester.tap(find.text('Volver'));
        await tester.pumpAndSettle();
        expect(find.text('PRIVACIDAD Y LEGAL'), findsOneWidget);
      });
    }

    testWidgets('con COP y USD la cabecera cabe en un celular angosto (360 dp)', (tester) async {
      tester.view.physicalSize = const Size(900, 6000);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: PerfilPage(
          authService: FakeAuthService(usuario: ana),
          suscripcionService: _DosMonedas(),
          version: () async => null,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('12'), findsOneWidget);
      expect(find.text(Formato.moneda(1234567, 'COP')), findsOneWidget);
      expect(find.text(Formato.moneda(1234.56, 'USD')), findsOneWidget);
      expect(find.text('Gasto mensual USD'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('la política dice que es un borrador y deja el contacto por definir', (tester) async {
      await abrir(tester);
      await tester.tap(find.text('Política de privacidad'));
      await tester.pumpAndSettle();
      expect(find.text(avisoPrivacidad), findsOneWidget);
      expect(find.textContaining('[correo de contacto por definir]'), findsOneWidget);
    });

    testWidgets('Acerca de muestra la versión, el equipo y el crédito académico', (tester) async {
      await abrir(tester);
      await tester.tap(find.text('Acerca de SubTrack'));
      await tester.pumpAndSettle();
      expect(find.text('Versión 1.0.0 (1)'), findsOneWidget);
      for (final persona in equipo) {
        expect(find.text(persona), findsOneWidget);
      }
      expect(find.text(creditoAcademico), findsOneWidget);
    });
  });
}
