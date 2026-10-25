import 'package:flutter_suscripciones/models/suscripcion.dart';
import 'package:flutter_suscripciones/utils/formato.dart';
import 'package:flutter_suscripciones/widgets/suscripcion_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // intl separa el símbolo con un espacio que no se parte (U+00A0).
  String sinNbsp(String s) => s.replaceAll(' ', ' ');

  test('montos con formato colombiano', () {
    expect(sinNbsp(Formato.moneda(45900, 'COP')), r'$ 45.900');
    expect(sinNbsp(Formato.moneda(1234567, 'COP')), r'$ 1.234.567');
    expect(sinNbsp(Formato.moneda(0, 'COP')), r'$ 0');
    expect(sinNbsp(Formato.moneda(12.99, 'USD')), r'US$ 12,99');
  });

  test('fechas dd/mm/aaaa', () {
    expect(Formato.fecha(DateTime(2026, 3, 5)), '05/03/2026');
    expect(Formato.fechaApi(DateTime(2026, 3, 5)), '2026-03-05');
    expect(Formato.leerFechaApi('2026-12-31'), DateTime(2026, 12, 31));
  });

  test('lee montos como los escribe un colombiano', () {
    expect(Formato.leerMonto('45900', 'COP'), 45900);
    expect(Formato.leerMonto('45.900', 'COP'), 45900);
    expect(Formato.leerMonto(r'$ 45.900', 'COP'), 45900);
    expect(Formato.leerMonto('45900,5', 'COP'), 45900.5);
    expect(Formato.leerMonto('12.99', 'USD'), 12.99);
    expect(Formato.leerMonto('12,99', 'USD'), 12.99);
    expect(Formato.leerMonto('12.999', 'USD'), isNull);
    expect(Formato.leerMonto('-5', 'COP'), isNull);
    expect(Formato.leerMonto('abc', 'COP'), isNull);
    expect(Formato.leerMonto('', 'COP'), isNull);
  });

  test('monto para editar vuelve a leerse igual', () {
    for (final (monto, moneda) in [(45900.0, 'COP'), (45900.5, 'COP'), (12.99, 'USD')]) {
      final texto = Formato.montoParaEditar(monto, moneda);
      expect(Formato.leerMonto(texto, moneda), monto, reason: texto);
    }
  });

  group('aviso de la tarjeta', () {
    final hoy = DateTime(2026, 11, 10);
    Suscripcion sus({
      required DateTime fecha,
      bool prueba = false,
      int? diasAviso,
      EstadoSuscripcion estado = EstadoSuscripcion.activa,
    }) =>
        Suscripcion(
          id: 1,
          nombreServicio: 'Netflix',
          monto: 38900,
          frecuencia: Frecuencia.mensual,
          fechaProximoCobro: fecha,
          esPruebaGratis: prueba,
          fechaFinPrueba: prueba ? fecha : null,
          diasAviso: diasAviso,
          estado: estado,
        );

    test('cobro dentro de los días de aviso', () {
      expect(avisoDeSuscripcion(sus(fecha: DateTime(2026, 11, 11)), hoy, 3)?.texto, 'Se cobra mañana');
      expect(avisoDeSuscripcion(sus(fecha: DateTime(2026, 11, 13)), hoy, 3)?.texto, 'Se cobra en 3 días');
      expect(avisoDeSuscripcion(sus(fecha: DateTime(2026, 11, 14)), hoy, 3), isNull);
      // Los días propios de la suscripción ganan sobre los globales.
      expect(avisoDeSuscripcion(sus(fecha: DateTime(2026, 11, 14), diasAviso: 7), hoy, 3)?.ambar, isFalse);
    });

    test('pruebas gratis, marcadas y cobros vencidos en ámbar', () {
      final prueba = avisoDeSuscripcion(sus(fecha: DateTime(2026, 11, 12), prueba: true), hoy, 3)!;
      expect(prueba.ambar, isTrue);
      expect(sinNbsp(prueba.texto), r'Prueba gratis: se convierte en $ 38.900/mes en 2 días');

      final marcada = avisoDeSuscripcion(
        sus(fecha: DateTime(2026, 12, 30), estado: EstadoSuscripcion.marcadaParaCancelar),
        hoy,
        3,
      )!;
      expect(marcada.texto, 'Marcada por ti para cancelar');

      final vencida = avisoDeSuscripcion(sus(fecha: DateTime(2026, 11, 1)), hoy, 3)!;
      expect(vencida.ambar, isTrue);
      expect(vencida.texto, contains('01/11/2026'));
    });
  });
}
