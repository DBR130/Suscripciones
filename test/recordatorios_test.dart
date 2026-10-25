import 'package:flutter_suscripciones/models/suscripcion.dart';
import 'package:flutter_suscripciones/services/recordatorios_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // "Ahora": 10 nov 2026, 8:00 a. m. en Colombia.
  final ahora = DateTime(2026, 11, 10, 8);

  Suscripcion sus(
    int id,
    String nombre,
    DateTime cobro, {
    double monto = 26900,
    int? diasAviso,
    DateTime? finPrueba,
    EstadoSuscripcion estado = EstadoSuscripcion.activa,
    Frecuencia frecuencia = Frecuencia.mensual,
  }) =>
      Suscripcion(
        id: id,
        nombreServicio: nombre,
        monto: monto,
        frecuencia: frecuencia,
        fechaProximoCobro: cobro,
        esPruebaGratis: finPrueba != null,
        fechaFinPrueba: finPrueba,
        diasAviso: diasAviso,
        estado: estado,
      );

  RecordatorioPlan porId(List<RecordatorioPlan> planes, int id) =>
      planes.singleWhere((p) => p.id == id);

  test('próximo cobro: 9:00 del día (cobro - días de aviso globales)', () {
    final planes = planificarRecordatorios([sus(5, 'Netflix', DateTime(2026, 11, 20))], 3, ahora);

    final p = porId(planes, 51);
    expect(p.cuando, DateTime(2026, 11, 17, 9));
    expect(p.titulo, 'Próximo cobro');
    expect(p.cuerpo, r'Netflix te cobra $26.900 en 3 días');
    expect(p.payload, '5');
  });

  test('usa los días de aviso propios de la suscripción', () {
    final planes = planificarRecordatorios(
      [sus(5, 'Netflix', DateTime(2026, 11, 20), diasAviso: 7)],
      3,
      ahora,
    );
    expect(porId(planes, 51).cuando, DateTime(2026, 11, 13, 9));
    expect(porId(planes, 51).cuerpo, endsWith('en 7 días'));
  });

  test('fin de prueba gratis: aviso por la fecha de fin', () {
    final planes = planificarRecordatorios(
      [sus(8, 'Disney+', DateTime(2026, 11, 14), monto: 38900, finPrueba: DateTime(2026, 11, 14))],
      2,
      ahora,
    );
    final p = porId(planes, 82);
    expect(p.cuando, DateTime(2026, 11, 12, 9));
    expect(p.titulo, 'Fin de prueba gratis');
    expect(p.cuerpo, r'Tu prueba de Disney+ termina en 2 días: luego se cobran $38.900/mes');
  });

  test('si la hora del aviso ya pasó pero el cobro no, se programa en 1 minuto', () {
    final planes = planificarRecordatorios(
      [
        sus(1, 'Mañana', DateTime(2026, 11, 11)), // aviso era el 8 nov
        sus(2, 'Hoy', DateTime(2026, 11, 10)),
      ],
      3,
      ahora,
    );
    expect(porId(planes, 11).cuando, ahora.add(const Duration(minutes: 1)));
    expect(porId(planes, 11).cuerpo, r'Mañana te cobra $26.900 mañana');
    expect(porId(planes, 21).cuerpo, r'Hoy te cobra $26.900 hoy');
  });

  test('nunca programa cobros pasados ni suscripciones canceladas', () {
    final planes = planificarRecordatorios(
      [
        sus(1, 'Vencida', DateTime(2026, 11, 9)),
        sus(2, 'Cancelada', DateTime(2026, 11, 20), estado: EstadoSuscripcion.cancelada),
        sus(3, 'Prueba vencida', DateTime(2026, 11, 20), finPrueba: DateTime(2026, 11, 1)),
      ],
      3,
      ahora,
      resumenMensual: false,
    );
    expect(planes, isEmpty);
    expect(planes.every((p) => !p.cuando.isBefore(ahora)), isTrue);
  });

  test('resumen mensual: día 1 del mes siguiente con el total del mes', () {
    final planes = planificarRecordatorios(
      [
        sus(1, 'Netflix', DateTime(2026, 11, 20), monto: 38900),
        sus(2, 'Canva', DateTime(2027, 1, 14), monto: 120000, frecuencia: Frecuencia.anual),
        sus(3, 'Prueba', DateTime(2026, 11, 30), finPrueba: DateTime(2026, 11, 30)),
      ],
      3,
      ahora,
    );
    final r = porId(planes, idResumenMensual);
    expect(r.cuando, DateTime(2026, 12, 1, 9));
    expect(r.cuerpo, contains(r'$48.900')); // 38.900 + 120.000/12; la prueba suma 0
    expect(r.payload, '');
  });

  test('el 1 del mes antes de las 9:00, el resumen sale ese mismo día', () {
    final planes = planificarRecordatorios(
      [sus(1, 'Netflix', DateTime(2026, 12, 20))],
      3,
      DateTime(2026, 12, 1, 7),
    );
    expect(porId(planes, idResumenMensual).cuando, DateTime(2026, 12, 1, 9));
  });

  test('sin suscripciones no hay resumen', () {
    expect(planificarRecordatorios(const [], 3, ahora), isEmpty);
  });
}
