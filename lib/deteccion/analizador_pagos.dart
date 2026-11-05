import 'parser_pagos.dart';

/// Análisis en el celular (minimización de datos): de todos los cobros que
/// se interpretaron, decide cuáles pueden salir hacia el backend.
///
/// Salen solo:
///  - los pagos a servicios conocidos del catálogo de guías (si el servicio
///    es ambiguo, como Rappi o Apple, solo con señal de suscripción o con
///    patrón), y
///  - los de comercios con patrón recurrente: 2 o más cobros con montos
///    similares (±10 %) y periodicidad semanal, mensual o anual.
///
/// Las compras puntuales (por ejemplo, una compra en DiDi Food) se quedan en
/// el celular. Es la misma regla que aplica el backend
/// (backend/src/services/detecciones.js), para que lo que se envía sí forme
/// un candidato allá.
class AnalizadorPagos {
  const AnalizadorPagos._();

  /// Dos pagos son "del mismo monto" si difieren máximo un 10 %.
  static const toleranciaMontos = 0.1;

  /// Un SMS sin fecha en el texto (Nequi) toma la hora en que llegó, y esa
  /// hora cambia unos segundos según el camino: postTime de la notificación o
  /// la fecha del SMS en el historial. Dentro de este margen, mismo banco,
  /// comercio y monto es el mismo cobro.
  static const toleranciaSinFecha = Duration(minutes: 5);

  /// Días entre dos cobros para cada frecuencia (los mismos del backend).
  static const _intervalos = [
    (frecuencia: 'semanal', min: 6, max: 8),
    (frecuencia: 'mensual', min: 26, max: 35),
    (frecuencia: 'anual', min: 355, max: 375),
  ];

  /// Huecos: en una serie del mismo monto, 2 o 3 meses entre dos cobros
  /// (61 días) cuentan como mensual, porque a veces falta el SMS de un mes.
  /// Solo meses: dos pedidos iguales a 14 días no deben parecer una
  /// suscripción semanal. La misma tabla está en services/detecciones.js.
  static const _huecos = [
    (frecuencia: 'mensual', min: 56, max: 66),
    (frecuencia: 'mensual', min: 87, max: 97),
  ];

  /// "Mismo monto" para buscar una serie dentro de una mezcla: ±1 % en pesos
  /// enteros; ±10 % si es un cobro convertido de USD (con centavos), porque la
  /// tasa del dólar lo mueve cada mes.
  static const toleranciaMontoExacto = 0.01;

  static bool _esConvertido(double monto) => (monto * 100).round() % 100 != 0;

  static bool mismoMonto(double a, double b) {
    final tolerancia = _esConvertido(a) || _esConvertido(b) ? toleranciaMontos : toleranciaMontoExacto;
    return (a - b).abs() <= tolerancia * (a > b ? a : b);
  }

  /// true si [a] y [b] son el mismo cobro llegado por caminos distintos
  /// (notificación, historial de SMS o compartir).
  static bool mismoCobro(PagoExtraido a, PagoExtraido b) {
    if (a.banco != b.banco ||
        a.moneda != b.moneda ||
        a.monto != b.monto ||
        a.comercio.toLowerCase() != b.comercio.toLowerCase()) {
      return false;
    }
    final diferencia = a.fecha.difference(b.fecha).abs();
    // Con la fecha del propio mensaje en los dos, debe ser la misma.
    if (a.fechaDelMensaje && b.fechaDelMensaje) return diferencia < const Duration(minutes: 1);
    return diferencia <= toleranciaSinFecha;
  }

  /// Quita los repetidos (ver [mismoCobro]); se queda con el primero.
  static List<PagoExtraido> sinRepetidos(Iterable<PagoExtraido> pagos) {
    final unicos = <PagoExtraido>[];
    for (final p in pagos) {
      if (!unicos.any((u) => mismoCobro(u, p))) unicos.add(p);
    }
    return unicos;
  }

  static String? frecuenciaDeIntervalo(int dias, {bool conHuecos = false}) {
    for (final i in [..._intervalos, if (conHuecos) ..._huecos]) {
      if (dias >= i.min && dias <= i.max) return i.frecuencia;
    }
    return null;
  }

  /// Frecuencia de una serie de fechas ordenadas: todos los intervalos deben
  /// ser de la misma. null si son menos de 2 o no son periódicas.
  static String? estimarFrecuencia(List<DateTime> fechas) {
    if (fechas.length < 2) return null;
    String? frecuencia;
    for (var i = 1; i < fechas.length; i++) {
      final f = frecuenciaDeIntervalo(_dias(fechas[i - 1], fechas[i]));
      if (f == null || (frecuencia != null && f != frecuencia)) return null;
      frecuencia = f;
    }
    return frecuencia;
  }

  static bool montosSimilares(double a, double b) => (a - b).abs() <= toleranciaMontos * (a > b ? a : b);

  /// Los pagos que pueden salir del celular, del más antiguo al más reciente.
  static List<PagoExtraido> seleccionarParaEnviar(Iterable<PagoExtraido> pagos) {
    final porComercio = <String, List<PagoExtraido>>{};
    for (final p in sinRepetidos(pagos)) {
      porComercio.putIfAbsent('${p.comercio.toLowerCase()}|${p.moneda}', () => []).add(p);
    }

    final seleccion = <PagoExtraido>[];
    for (final grupo in porComercio.values) {
      grupo.sort((a, b) => a.fecha.compareTo(b.fecha));
      final conocido = grupo.any((p) => p.esServicioConocido);
      final ambiguo = grupo.any((p) => p.servicioAmbiguo);
      if (conocido && !ambiguo) {
        seleccion.addAll(grupo);
        continue;
      }
      // Ambiguo: los cobros con señal ("RAPPI PRO", "YouTubePremium") o por el
      // valor exacto de su precio de referencia (YouTube a $13.300) salen
      // solos; el resto, solo si forma una serie periódica.
      if (ambiguo) seleccion.addAll(grupo.where((p) => p.indicaSuscripcion || p.coincidePrecioReferencia));
      // Comercio desconocido: series de montos similares (±10 %) que sean
      // periódicas en su totalidad (un gimnasio de $95.000 y luego $99.900)...
      for (final serie in _seriesPorMonto(grupo)) {
        if (estimarFrecuencia([for (final p in serie) p.fecha]) != null) {
          seleccion.addAll(serie.where((p) => !seleccion.contains(p)));
        }
      }
      // ...o, si los pedidos de montos parecidos rompen ese patrón, una serie de
      // monto exacto dentro de la mezcla (DiDi Club entre domicilios de DiDi Food).
      seleccion.addAll(serieEnMezcla(grupo).where((p) => !seleccion.contains(p)));
    }
    seleccion.sort((a, b) => a.fecha.compareTo(b.fecha));
    return seleccion;
  }

  /// La serie periódica más larga (2 o más cobros) de un mismo monto
  /// ([mismoMonto]) dentro de [grupo], aunque haya otros cobros del mismo
  /// comercio en medio. Vacía si no hay.
  static List<PagoExtraido> serieEnMezcla(List<PagoExtraido> grupo) {
    final ordenados = [...grupo]..sort((a, b) => a.fecha.compareTo(b.fecha));
    var mejor = <PagoExtraido>[];
    for (final ancla in ordenados) {
      final mismos = ordenados.where((p) => mismoMonto(ancla.monto, p.monto)).toList();
      for (final frecuencia in const ['semanal', 'mensual', 'anual']) {
        // Cadena más larga en la que cada salto es de esa frecuencia.
        final largo = List.filled(mismos.length, 1);
        final anterior = List<int?>.filled(mismos.length, null);
        for (var j = 0; j < mismos.length; j++) {
          for (var i = 0; i < j; i++) {
            final f = frecuenciaDeIntervalo(_dias(mismos[i].fecha, mismos[j].fecha), conHuecos: true);
            if (f == frecuencia && largo[i] + 1 > largo[j]) {
              largo[j] = largo[i] + 1;
              anterior[j] = i;
            }
          }
        }
        for (var j = 0; j < mismos.length; j++) {
          if (largo[j] < 2 || largo[j] <= mejor.length) continue;
          final cadena = <PagoExtraido>[];
          for (int? k = j; k != null; k = anterior[k]) {
            cadena.insert(0, mismos[k]);
          }
          mejor = cadena;
        }
      }
    }
    return mejor;
  }

  /// Agrupa por monto: cada pago va a la primera serie cuyo primer monto sea
  /// similar (±10 %).
  static List<List<PagoExtraido>> _seriesPorMonto(List<PagoExtraido> grupo) {
    final series = <List<PagoExtraido>>[];
    for (final p in grupo) {
      final serie = series.where((s) => montosSimilares(s.first.monto, p.monto)).firstOrNull;
      if (serie == null) {
        series.add([p]);
      } else {
        serie.add(p);
      }
    }
    return series;
  }

  /// Días de calendario entre dos fechas (sin importar la hora).
  static int _dias(DateTime a, DateTime b) =>
      DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
}
