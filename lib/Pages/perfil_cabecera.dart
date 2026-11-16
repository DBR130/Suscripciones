import '../models/resumen.dart';
import '../utils/formato.dart';

/// Un dato de la cabecera del Perfil: valor grande y etiqueta debajo.
typedef DatoCabecera = ({String valor, String etiqueta});

/// Datos de la cabecera del Perfil a partir del resumen que ya usa Inicio
/// (GET /api/resumen, sin endpoints nuevos): suscripciones activas y gasto
/// mensual, con COP y USD aparte (no se convierten) y COP primero.
/// "Miembro desde" no se muestra: el servidor no envía la fecha de registro.
List<DatoCabecera> datosCabeceraPerfil(Resumen? resumen) {
  if (resumen == null) {
    return const [(valor: '—', etiqueta: 'Activas'), (valor: '—', etiqueta: 'Gasto mensual')];
  }
  final totales = [...resumen.totales]..sort((a, b) => a.moneda == 'COP' ? -1 : (b.moneda == 'COP' ? 1 : 0));
  final activas = (valor: '${resumen.cantidadActivas}', etiqueta: 'Activas');
  if (totales.isEmpty) {
    return [activas, (valor: Formato.moneda(0, 'COP'), etiqueta: 'Gasto mensual')];
  }
  final variasMonedas = totales.length > 1;
  return [
    activas,
    for (final t in totales)
      (
        valor: Formato.moneda(t.gastoMensual, t.moneda),
        etiqueta: variasMonedas ? 'Gasto mensual ${t.moneda}' : 'Gasto mensual',
      ),
  ];
}
