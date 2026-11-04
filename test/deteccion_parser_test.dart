import 'dart:convert';
import 'dart:io';

import 'package:flutter_suscripciones/deteccion/catalogo_servicios.dart';
import 'package:flutter_suscripciones/deteccion/parser_pagos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // El mismo catálogo que carga el backend (GET /api/guias).
  final catalogo = CatalogoServicios.fromJson(
    jsonDecode(File('backend/db/guias.json').readAsStringSync()) as Object,
  );
  final parser = ParserPagos(catalogo);
  final llegada = DateTime(2026, 10, 31, 9, 30);

  PagoExtraido cobro(String texto, {String titulo = '', ParserPagos? con}) {
    final r = (con ?? parser).interpretar(texto, titulo: titulo, recibidaEn: llegada);
    expect(r.esCobro, isTrue, reason: 'debería ser un cobro: $texto (${r.motivo})');
    return r.pago!;
  }

  String? motivo(String texto, {String titulo = ''}) {
    final r = parser.interpretar(texto, titulo: titulo, recibidaEn: llegada);
    expect(r.esCobro, isFalse, reason: 'no debería ser un cobro: $texto');
    return r.motivo;
  }

  group('notificaciones reales (test/fixtures/notificaciones_reales.json)', () {
    final fixtures = (jsonDecode(File('test/fixtures/notificaciones_reales.json').readAsStringSync())
        as Map)['notificaciones'] as List;

    for (final f in fixtures.cast<Map>()) {
      test(f['caso'] as String, () {
        final esperado = f['esperado'] as Map;
        final r = parser.interpretar(
          f['texto'] as String,
          titulo: f['titulo'] as String,
          recibidaEn: DateTime.parse(f['recibida_en'] as String),
        );
        expect(r.esCobro, isTrue, reason: r.motivo);
        final p = r.pago!;
        expect(p.banco, esperado['banco']);
        expect(p.monto, (esperado['monto'] as num).toDouble());
        expect(p.moneda, esperado['moneda']);
        expect(p.comercio, esperado['comercio']);
        expect(p.servicio, esperado['servicio']);
        expect(p.medio, esperado['medio']);
        expect(p.indicaSuscripcion, esperado['indica_suscripcion']);
        if (esperado['fecha'] == null) {
          expect(p.fechaDelMensaje, isFalse);
          expect(p.fecha, DateTime.parse(f['recibida_en'] as String));
        } else {
          expect(p.fechaDelMensaje, isTrue);
          expect(p.fecha, DateTime.parse(esperado['fecha'] as String));
        }
      });
    }

    test('los dígitos de la tarjeta y los teléfonos no quedan en ningún campo', () {
      final p = cobro((fixtures.first as Map)['texto'] as String);
      final campos = [p.banco, p.comercio, p.comercioOriginal, p.medio, p.moneda].join(' ');
      expect(campos, isNot(contains('0000')));
      expect(campos, isNot(contains('6045109095')));
    });
  });

  group('montos', () {
    test('formatos colombianos e internacionales', () {
      expect(leerMonto(r'$19.900,00'), (valor: 19900.0, moneda: 'COP'));
      expect(leerMonto(r'$26.900'), (valor: 26900.0, moneda: 'COP'));
      expect(leerMonto('68.139,27'), (valor: 68139.27, moneda: 'COP'));
      expect(leerMonto('COP 26,900.00'), (valor: 26900.0, moneda: 'COP'));
      expect(leerMonto('USD 20.00'), (valor: 20.0, moneda: 'USD'));
      expect(leerMonto(r'US$ 9.99'), (valor: 9.99, moneda: 'USD'));
      expect(leerMonto('15,99 USD'), (valor: 15.99, moneda: 'USD'));
      expect(leerMonto(r'$1.234.567'), (valor: 1234567.0, moneda: 'COP'));
      expect(leerMonto('68139,27'), (valor: 68139.27, moneda: 'COP'));
      expect(leerMonto('45000'), (valor: 45000.0, moneda: 'COP'));
    });

    test('números ambiguos o mal formados no se adivinan', () {
      expect(leerNumero('1.23.4'), isNull);
      expect(leerNumero('12.3456'), isNull);
    });

    test('dentro de un mensaje', () {
      expect(cobro(r'Bancolombia: Compraste $26.900 en NETFLIX.COM').monto, 26900);
      final usd = cobro('Bancolombia: Compraste USD 20.00 en NETFLIX.COM con tu T.Cred *0000');
      expect((usd.monto, usd.moneda, usd.medio), (20.0, 'USD', 'T.Cred'));
      final cop = cobro('Davivienda: Compra por COP 26,900.00 en SPOTIFY el 01/11/2026');
      expect((cop.monto, cop.moneda, cop.banco), (26900.0, 'COP', 'Davivienda'));
    });
  });

  group('fecha', () {
    test('usa la fecha y hora del mensaje', () {
      expect(leerFecha('el 23/10/2026 a las 07:20.'), DateTime(2026, 10, 23, 7, 20));
      expect(leerFecha('23/10/26 18:05'), DateTime(2026, 10, 23, 18, 5));
      expect(leerFecha('el 5/1/2026'), DateTime(2026, 1, 5));
    });

    test('una fecha imposible no se usa', () {
      expect(leerFecha('el 31/02/2026 a las 10:00'), isNull);
      expect(leerFecha('el 12/10/2026 a las 25:00'), isNull);
    });

    test('sin fecha en el mensaje, la de llegada', () {
      final p = cobro('NEQUI: Pagaste 25.000 en SPOTIFY');
      expect(p.fecha, llegada);
      expect(p.fechaDelMensaje, isFalse);
    });
  });

  group('normalización del comercio', () {
    test('quita prefijos de pasarelas', () {
      expect(cobro(r'Bancolombia: Compraste $19.900 en GOOGLE *YouTube Premium').comercio, 'YouTube Premium');
      expect(cobro(r'Bancolombia: Compraste $4.900 en APPLE.COM/BILL').comercio, 'Apple');
      expect(cobro(r'Bancolombia: Compraste $16.900 en PAYPAL *SPOTIFY').comercio, 'Spotify');
      expect(cobro(r'Bancolombia: Compraste $38.900 en EBANX *DISNEY PLUS').comercio, 'Disney+');
      expect(cobro(r'Bancolombia: Compraste $20.000 en GOOGLE*CANVA').comercio, 'Canva Pro');
    });

    test('quita sufijos y variantes del mismo servicio', () {
      for (final variante in ['NETFLIX.COM', 'Netflix*Bogota', 'NETFLIX INC', 'netflix']) {
        expect(cobro('Bancolombia: Compraste \$26.900 en $variante').comercio, 'Netflix', reason: variante);
      }
      expect(cobro(r'Bancolombia: Compraste $9.900 en HBO MAX').comercio, 'Max');
      expect(cobro('NEQUI: Pagaste 79.000 en OPENAI *CHATGPT SUBSCR').comercio, 'ChatGPT Plus');
    });

    test('Claude con sus alias', () {
      for (final variante in ['ANTHROPIC* CLAUDE SUB', 'CLAUDE.AI SUBSCRIPTION', 'ANTHROPIC']) {
        final p = cobro('NEQUI: Pagaste 68.139,27 en $variante');
        expect(p.comercio, 'Claude', reason: variante);
        expect(p.esServicioConocido, isTrue);
      }
      expect(cobro('NEQUI: Pagaste 68.139,27 en ANTHROPIC* CLAUDE SUB').indicaSuscripcion, isTrue);
      expect(cobro('NEQUI: Pagaste 68.139,27 en ANTHROPIC').indicaSuscripcion, isFalse);
    });

    test('un comercio fuera del catálogo queda legible y sin servicio', () {
      final p = cobro(r'Bancolombia: Compraste $45.300 en TIENDAS D1 SAS*MEDELLIN con tu T.Deb *0000');
      expect(p.comercio, 'Tiendas D1');
      expect(p.servicio, isNull);
      expect(p.comercioOriginal, 'TIENDAS D1 SAS*MEDELLIN');
    });

    test('sin catálogo (backend no disponible) igual limpia el nombre', () {
      const sinCatalogo = ParserPagos();
      final p = cobro(r'Bancolombia: Compraste $19.900,00 en GOOGLE *Crunchyroll', con: sinCatalogo);
      expect(p.comercio, 'Crunchyroll');
      expect(p.servicio, isNull);
      expect(cobro(r'Bancolombia: Compraste $26.900 en NETFLIX.COM', con: sinCatalogo).comercio, 'Netflix');
    });
  });

  group('banco', () {
    test('por el remitente del texto o por el título', () {
      expect(cobro(r'Bancolombia: Compraste $5.000 en SPOTIFY').banco, 'Bancolombia');
      expect(cobro(r'Compraste $5.000 en SPOTIFY', titulo: 'Bancolombia').banco, 'Bancolombia');
      expect(cobro('NEQUI: Pagaste 5.000 en SPOTIFY').banco, 'Nequi');
      expect(cobro(r'BBVA: compra de $5.000 en SPOTIFY').banco, 'BBVA');
    });

    test('un "cobro" sin banco conocido no se acepta', () {
      expect(motivo(r'Compraste $5.000 en SPOTIFY'), 'no es de un banco conocido');
      expect(motivo(r'Compraste $5.000 en SPOTIFY', titulo: '89123'), 'no es de un banco conocido');
    });
  });

  group('limpieza del comercio (SMS reales, T1)', () {
    test('nombres pegados: GOOGLE *YouTubePremium es YouTube Premium, con señal de suscripción', () {
      final p = cobro(r'Bancolombia: Compraste $26.900,00 en GOOGLE *YouTubePremium con tu T.Deb *0000, el 05/10/2026 a las 08:00.');
      expect(p.servicio, 'YouTube Premium');
      expect(p.indicaSuscripcion, isTrue);
    });

    test('un teléfono pegado al comercio no es parte del nombre (Steam, SMS real)', () {
      final p = cobro('NEQUI: Pagaste 39.381,00 en STEAMGAMES.COM 4259522985');
      expect((p.banco, p.monto, p.comercio), ('Nequi', 39381, 'Steamgames'));
      expect(p.indicaSuscripcion, isFalse);
    });

    test('DLO* es el prefijo de dLocal: queda el comercio real (DiDi, SMS real)', () {
      final p = cobro('NEQUI: Pagaste 18.900,00 en DLO*DiDi Food CO Payin');
      expect((p.banco, p.monto, p.comercio, p.servicio), ('Nequi', 18900, 'DiDi Food', null));
    });

    test('"PRO" solo cuenta como palabra completa', () {
      expect(cobro(r'Bancolombia: Compraste $25.000,00 en PRODUCTOS RAPPI').indicaSuscripcion, isFalse);
      expect(cobro(r'Bancolombia: Compraste $25.000,00 en RAPPI PRO').indicaSuscripcion, isTrue);
    });
  });

  test('los SMS de prueba de docs/probar-la-app.md se reconocen', () {
    final b = cobro(r'Bancolombia: Compraste $19.900,00 en NETFLIX con tu T.Deb *1234, el 01/11/2026 a las 10:30.');
    expect((b.banco, b.monto, b.servicio), ('Bancolombia', 19900, 'Netflix'));
    final n = cobro('NEQUI: Pagaste 26.900 en SPOTIFY');
    expect((n.banco, n.monto, n.servicio), ('Nequi', 26900, 'Spotify'));
  });

  group('textos que NO son cobros', () {
    test('transferencias recibidas', () {
      expect(motivo('NEQUI: Recibiste 50.000 de JUAN PEREZ'), 'dinero recibido');
      expect(motivo(r'Bancolombia: Recibiste una transferencia por $120.000 de MARIA'), 'dinero recibido');
      expect(motivo('Nequi: Te enviaron 20.000 pesos'), 'dinero recibido');
    });

    test('transferencias enviadas y retiros', () {
      expect(motivo(r'Bancolombia: Transferiste $50.000 a la cuenta *0000'), 'transferencia');
      expect(motivo('NEQUI: Enviaste 30.000 a Pedro'), 'transferencia');
      expect(motivo(r'Bancolombia: Retiraste $200.000 en CAJERO CENTRO'), 'retiro de dinero');
    });

    test('códigos de verificación, aunque nombren una compra', () {
      expect(motivo('Bancolombia: tu codigo para la compra de \$19.900 es 123456'), 'código de verificación');
      expect(motivo('NEQUI: Tu clave dinamica es 482913. No la compartas'), 'código de verificación');
      expect(motivo('Su OTP para pagar 50.000 en AMAZON es 1234'), 'código de verificación');
    });

    test('recargas', () {
      expect(motivo(r'NEQUI: Recargaste $20.000 a tu Nequi'), 'recarga');
      expect(motivo(r'Bancolombia: Compraste una recarga de $10.000 en CLARO'), 'recarga');
    });

    test('publicidad', () {
      expect(motivo(r'Bancolombia: Aprovecha 20% de descuento en compras desde $50.000 en EXITO'), 'publicidad');
      expect(motivo('NEQUI: Paga con Nequi y participa por 1.000.000'), 'publicidad');
    });

    test('SMS personales y textos sin la forma de un cobro', () {
      expect(motivo('prueba'), 'no es de un banco conocido');
      expect(motivo('Hola, ya te pagué lo del almuerzo, eran 15.000'), 'no es de un banco conocido');
      expect(motivo('Bancolombia: Estamos cerca. Actualiza tus datos en la app'),
          'no dice "compraste/pagaste <monto> en <comercio>"');
      expect(motivo(''), 'sin texto');
    });

    // Truecaller como app de SMS: también avisa de llamadas y spam. El filtro
    // nativo los descarta (FiltroCobrosTest.kt); el parser, por si acaso, tampoco
    // los acepta.
    final avisos = (jsonDecode(File('test/fixtures/avisos_no_sms.json').readAsStringSync())
        as Map<String, Object?>)['avisos'] as List<Object?>;
    for (final a in avisos.cast<Map<String, Object?>>()) {
      test('aviso que no es SMS: ${a['caso']}', () => motivo(a['texto'] as String));
    }
  });
}
