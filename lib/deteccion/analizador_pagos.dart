import 'parser_pagos.dart';

/// Qué decidió el análisis con un comercio (pantalla de depuración, "Último
/// escaneo").
enum DecisionEscaneo {
  /// Servicio del catálogo que no es ambiguo: sale desde el primer cobro.
  servicioConocido,

  /// Ambiguo con señal de suscripción ("RAPPI PRO", "YouTubePremium").
  conSenal,

  /// Ambiguo por el valor exacto de su precio de referencia.
  precioReferencia,

  /// Serie periódica (todos los de monto similar, o una de monto exacto
  /// dentro de la mezcla).
  serie,

  /// Ambiguo sin señal, sin precio de referencia y sin serie.
  ambiguoSinSenalNiPatron,

  /// Procesador de pagos sin serie.
  procesadorSinPatron,

  /// Varios cobros de monto parecido, pero sin periodicidad.
  patronRoto,

  /// Compras sueltas de un comercio cualquiera.
  compraSuelta,
}

/// Un comercio agrupado por el análisis, con su decisión. Solo campos
/// extraídos: nunca el texto de los SMS.
class DiagnosticoComercio {
  DiagnosticoComercio({
    required this.nombre,
    required this.bancos,
    required this.montos,
    required this.fechas,
    required this.decision,
    required this.motivo,
    required this.pagosQueSalen,
    required this.repetidos,
  });

  /// Comercio normalizado, o el procesador ("EBANX").
  final String nombre;
  final Set<String> bancos;
  final List<double> montos;
  final List<DateTime> fechas;
  final DecisionEscaneo decision;
  final String motivo;

  /// Los que salen hacia el backend.
  final List<PagoExtraido> pagosQueSalen;

  /// Cobros repetidos (el mismo por notificación e historial) que no cuentan.
  final int repetidos;

  int get cobros => montos.length;
  int get salen => pagosQueSalen.length;
}

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
  static List<PagoExtraido> seleccionarParaEnviar(Iterable<PagoExtraido> pagos) =>
      [for (final c in diagnosticar(pagos)) ...c.pagosQueSalen]..sort((a, b) => a.fecha.compareTo(b.fecha));

  /// Agrupa los cobros por comercio (o procesador) y decide, para cada grupo,
  /// qué sale hacia el backend y por qué. [seleccionarParaEnviar] usa esta
  /// misma decisión, así el diagnóstico de la pantalla de depuración nunca
  /// contradice lo que realmente sale.
  static List<DiagnosticoComercio> diagnosticar(Iterable<PagoExtraido> pagos) {
    String clave(PagoExtraido p) => '${(p.procesador ?? p.comercio).toLowerCase()}|${p.moneda}';
    final todos = pagos.toList();
    final porComercio = <String, List<PagoExtraido>>{};
    for (final p in sinRepetidos(todos)) {
      porComercio.putIfAbsent(clave(p), () => []).add(p);
    }

    return [
      for (final MapEntry(key: llave, value: grupo) in porComercio.entries)
        _decidir(grupo..sort((a, b) => a.fecha.compareTo(b.fecha)),
            repetidos: todos.where((p) => clave(p) == llave).length - grupo.length),
    ];
  }

  static DiagnosticoComercio _decidir(List<PagoExtraido> grupo, {required int repetidos}) {
    final primero = grupo.first;
    DiagnosticoComercio con(DecisionEscaneo decision, String motivo, List<PagoExtraido> salen) => DiagnosticoComercio(
          nombre: primero.procesador ?? primero.comercio,
          bancos: {for (final p in grupo) p.banco},
          montos: [for (final p in grupo) p.monto],
          fechas: [for (final p in grupo) p.fecha],
          decision: decision,
          motivo: motivo,
          pagosQueSalen: salen,
          repetidos: repetidos,
        );

    final conocido = grupo.any((p) => p.esServicioConocido);
    final ambiguo = grupo.any((p) => p.servicioAmbiguo);
    if (conocido && !ambiguo) {
      return con(DecisionEscaneo.servicioConocido, 'Servicio conocido: se propone desde el primer cobro', grupo);
    }

    // Ambiguo: los cobros con señal ("RAPPI PRO", "YouTubePremium") o por el
    // valor exacto de su precio de referencia (YouTube a $13.300) salen
    // solos; el resto, solo si forma una serie periódica.
    final conSenal = ambiguo ? grupo.where((p) => p.indicaSuscripcion).toList() : <PagoExtraido>[];
    final porPrecio = ambiguo ? grupo.where((p) => p.coincidePrecioReferencia).toList() : <PagoExtraido>[];

    // Series: todos los de monto similar (±10 %) periódicos (un gimnasio de
    // $95.000 y luego $99.900), o una de monto exacto dentro de la mezcla
    // (DiDi Club entre domicilios de DiDi Food).
    final enSerie = <PagoExtraido>[];
    String? frecuencia;
    for (final serie in _seriesPorMonto(grupo)) {
      final f = estimarFrecuencia([for (final p in serie) p.fecha]);
      if (f != null) {
        enSerie.addAll(serie);
        frecuencia ??= f;
      }
    }
    final mezcla = serieEnMezcla(grupo);
    if (mezcla.isNotEmpty) {
      frecuencia ??= frecuenciaDeIntervalo(_dias(mezcla[0].fecha, mezcla[1].fecha), conHuecos: true);
      enSerie.addAll(mezcla.where((p) => !enSerie.contains(p)));
    }

    final salen = [
      for (final p in grupo)
        if (conSenal.contains(p) || porPrecio.contains(p) || enSerie.contains(p)) p,
    ];
    if (conSenal.isNotEmpty) return con(DecisionEscaneo.conSenal, 'Ambiguo con señal de suscripción', salen);
    if (porPrecio.isNotEmpty) {
      return con(DecisionEscaneo.precioReferencia, 'Cobro por el valor exacto de ${primero.comercio}', salen);
    }
    if (enSerie.isNotEmpty) {
      return con(DecisionEscaneo.serie, 'Serie $frecuencia de ${enSerie.length} cobros', salen);
    }
    if (primero.procesador != null) {
      return con(DecisionEscaneo.procesadorSinPatron,
          'Procesador sin patrón: necesita 2 cobros periódicos del mismo monto', const []);
    }
    if (ambiguo) {
      return con(DecisionEscaneo.ambiguoSinSenalNiPatron,
          'Ambiguo sin señal, sin precio de referencia y sin serie', const []);
    }
    final parecidos = grupo.any((a) => grupo.any((b) => !identical(a, b) && montosSimilares(a.monto, b.monto)));
    if (parecidos) {
      return con(DecisionEscaneo.patronRoto, '${grupo.length} cobros de monto parecido, sin periodicidad', const []);
    }
    return con(DecisionEscaneo.compraSuelta, grupo.length == 1 ? 'Compra suelta' : 'Compras sueltas', const []);
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
