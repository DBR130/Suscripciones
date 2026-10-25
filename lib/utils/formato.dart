import 'package:intl/intl.dart';

/// Formato colombiano para montos y fechas.
class Formato {
  Formato._();

  // es_CO usa punto para miles y coma para decimales. Su patrón por defecto
  // pone el símbolo al final ("45.900 $"), así que se fuerza "$ 45.900".
  // ¤ = símbolo de la moneda;   = espacio que no se parte en dos líneas.
  static final NumberFormat _cop = NumberFormat.currency(
    locale: 'es_CO',
    symbol: r'$',
    decimalDigits: 0,
    customPattern: '¤ #,##0',
  );
  static final NumberFormat _usd = NumberFormat.currency(
    locale: 'es_CO',
    symbol: r'US$',
    decimalDigits: 2,
    customPattern: '¤ #,##0.00',
  );
  static final DateFormat _fecha = DateFormat('dd/MM/yyyy');
  static final DateFormat _fechaApi = DateFormat('yyyy-MM-dd');

  /// "$ 45.900" en COP o "US$ 12,99" en USD.
  static String moneda(num monto, String moneda) {
    return (moneda == 'USD' ? _usd : _cop).format(monto);
  }

  /// "24/11/2026"
  static String fecha(DateTime fecha) => _fecha.format(fecha);

  /// "2026-11-24", el formato que usa el backend.
  static String fechaApi(DateTime fecha) => _fechaApi.format(fecha);

  /// Lee una fecha "2026-11-24" del backend (sin hora).
  static DateTime leerFechaApi(String texto) {
    final partes = texto.split('-').map(int.parse).toList();
    return DateTime(partes[0], partes[1], partes[2]);
  }

  static final RegExp _montoValido = RegExp(r'^\d{1,10}(\.\d{1,2})?$');

  /// Convierte lo que escribe el usuario en un monto, o null si no es válido.
  /// - COP: el punto es separador de miles ("45.900") y la coma, decimal.
  /// - USD: se acepta punto o coma como decimal ("12.99" o "12,99").
  static double? leerMonto(String texto, String moneda) {
    var limpio = texto.trim().replaceAll(RegExp(r'[\s$]'), '');
    if (moneda == 'COP') {
      limpio = limpio.replaceAll('.', '').replaceAll(',', '.');
    } else {
      limpio = limpio.replaceAll(',', '.');
    }
    if (!_montoValido.hasMatch(limpio)) return null;
    return double.parse(limpio);
  }

  /// Monto para poner en un campo de texto al editar ("45900" o "12.99").
  static String montoParaEditar(double monto, String moneda) {
    final entero = monto == monto.roundToDouble();
    if (entero) return monto.toStringAsFixed(0);
    final texto = monto.toStringAsFixed(2);
    return moneda == 'COP' ? texto.replaceAll('.', ',') : texto;
  }
}
