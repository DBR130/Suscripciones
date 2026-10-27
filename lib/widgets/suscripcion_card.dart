import 'package:flutter/material.dart';

import '../Common/AppTheme.dart';
import '../models/suscripcion.dart';
import '../utils/formato.dart';
import 'app_card.dart';
import 'logo_servicio.dart';

/// Aviso que se muestra en la tarjeta de una suscripción, o null si no hay.
/// Reglas de design/subtrack-pantallas.md, en orden: marcada, prueba gratis,
/// (cambio de precio, cuando exista el dato) y cobro cercano. Un cobro con
/// fecha vencida también avisa en ámbar para que se actualice.
({String texto, bool ambar})? avisoDeSuscripcion(
  Suscripcion s,
  DateTime hoy,
  int diasGlobales,
) {
  final dias = s.diasHasta(hoy);
  if (s.estado == EstadoSuscripcion.marcadaParaCancelar) {
    return (texto: 'Marcada por ti para cancelar', ambar: true);
  }
  if (s.esPruebaGratis) {
    final precio = '${s.montoTexto}${s.frecuencia.sufijo}';
    if (dias < 0) {
      return (texto: 'La prueba terminó: ahora cuesta $precio', ambar: true);
    }
    final cuando = switch (dias) {
      0 => 'hoy',
      1 => 'en 1 día',
      _ => 'en $dias días',
    };
    return (texto: 'Prueba gratis: se convierte en $precio $cuando', ambar: true);
  }
  if (dias < 0) {
    return (
      texto: 'El cobro del ${Formato.fecha(s.fechaProximoCobro)} ya pasó: '
          'actualiza la fecha',
      ambar: true,
    );
  }
  if (dias <= s.diasAvisoEfectivos(diasGlobales)) {
    final texto = switch (dias) {
      0 => 'Se cobra hoy',
      1 => 'Se cobra mañana',
      _ => 'Se cobra en $dias días',
    };
    return (texto: texto, ambar: false);
  }
  return null;
}

/// Línea bajo el nombre: la categoría o, si no tiene, "Mensual · Registro manual".
String descripcionSuscripcion(Suscripcion s) {
  if (s.categoria != null) return s.categoria!;
  final origen = s.origen == 'notificacion' ? 'Detectada' : 'Registro manual';
  return '${s.frecuencia.etiqueta} · $origen';
}

/// Línea de estado de la lista (pantalla 08): "Mensual · próximo 20 sep",
/// "Prueba gratis hasta 19 sep" o "Marcada para cancelar · 20 sep".
String lineaDeEstado(Suscripcion s) {
  if (s.estado == EstadoSuscripcion.marcadaParaCancelar) {
    return 'Marcada para cancelar · ${Formato.fechaCorta(s.fechaClave)}';
  }
  if (s.esPruebaGratis) return 'Prueba gratis hasta ${Formato.fechaCorta(s.fechaClave)}';
  return '${s.frecuencia.etiqueta} · próximo ${Formato.fechaCorta(s.fechaProximoCobro)}';
}

/// La tarjeta va resaltada en ámbar si es prueba gratis o está marcada.
bool esDestacada(Suscripcion s) =>
    s.esPruebaGratis || s.estado == EstadoSuscripcion.marcadaParaCancelar;

/// Tarjeta de una suscripción en el dashboard (pantalla 07 del diseño).
class SuscripcionCard extends StatelessWidget {
  const SuscripcionCard({
    super.key,
    required this.suscripcion,
    required this.hoy,
    required this.diasGlobales,
    required this.onVerDetalle,
  });

  final Suscripcion suscripcion;
  final DateTime hoy;
  final int diasGlobales;
  final VoidCallback onVerDetalle;

  @override
  Widget build(BuildContext context) {
    final s = suscripcion;
    final aviso = avisoDeSuscripcion(s, hoy, diasGlobales);
    final linea = s.esPruebaGratis
        ? 'Prueba termina ${Formato.fechaCorta(s.fechaClave)}'
        : 'Próximo cobro: ${Formato.fechaCorta(s.fechaProximoCobro)}';

    return AppCard(
      destacada: esDestacada(s),
      child: InkWell(
        onTap: onVerDetalle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                LogoServicio(s.nombreServicio),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.nombreServicio,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        descripcionSuscripcion(s),
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      s.montoTexto,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      s.frecuencia.sufijo,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (aviso != null) ...[
              const SizedBox(height: 12),
              AvisoFlag(aviso.texto, ambar: aviso.ambar),
            ],
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.line),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 13, color: AppColors.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    linea,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: onVerDetalle,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 13),
                    textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Ver detalle'),
                      SizedBox(width: 4),
                      Icon(Icons.chevron_right, size: 16),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
