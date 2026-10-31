import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Common/AppTheme.dart';
import '../Common/Routers.dart';
import '../models/ahorro.dart';
import '../services/api_client.dart';
import '../services/suscripcion_service.dart';
import '../utils/formato.dart';
import '../widgets/app_botones.dart';
import '../widgets/app_card.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_header.dart';
import '../widgets/estado_vacio.dart';
import '../widgets/logo_servicio.dart';

/// Ahorro (pantalla 12 del diseño) con datos reales de GET /api/ahorro.
class AhorroPage extends StatefulWidget {
  const AhorroPage({super.key, required this.suscripcionService, this.recienCancelada});

  final SuscripcionService suscripcionService;

  /// Nombre de la suscripción que se acaba de cancelar desde la guía, para
  /// mostrar el aviso azul.
  final String? recienCancelada;

  @override
  State<AhorroPage> createState() => _AhorroPageState();
}

class _AhorroPageState extends State<AhorroPage> {
  Ahorro? _ahorro;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final ahorro = await widget.suscripcionService.ahorro();
      if (!mounted) return;
      setState(() {
        _ahorro = ahorro;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ahorro = _ahorro;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            _Encabezado(ahorro),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.recienCancelada != null) ...[
                    _AvisoCancelada(widget.recienCancelada!),
                    const SizedBox(height: 14),
                  ],
                  if (_error != null && ahorro == null) ...[
                    BannerError(_error!),
                    const SizedBox(height: 12),
                    AppBotonSecundario(
                      texto: 'Reintentar',
                      onPressed: () {
                        setState(() => _error = null);
                        _cargar();
                      },
                    ),
                  ] else if (ahorro == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    for (final serie in ahorro.evolucion)
                      if (serie.moneda == 'COP' || serie.tieneDatos) ...[
                        _Subtitulo(serie.moneda == 'COP'
                            ? 'Evolución del gasto mensual'
                            : 'Evolución del gasto mensual (${serie.moneda})'),
                        GraficaGasto(serie: serie),
                        const SizedBox(height: 14),
                      ],
                    const _Subtitulo('Canceladas'),
                    if (ahorro.canceladas.isEmpty)
                      const EstadoVacio(
                        titulo: 'Aún no has cancelado suscripciones',
                        texto: 'Cuando canceles una con la guía, aquí verás cuánto ahorras al año.',
                      )
                    else
                      for (final c in ahorro.canceladas) ...[
                        _FilaCancelada(c),
                        const SizedBox(height: 10),
                      ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado(this.ahorro);

  final Ahorro? ahorro;

  @override
  Widget build(BuildContext context) {
    final totales = ahorro?.totales ?? const <TotalAhorro>[];
    final principal = totales.isEmpty ? null : totales.first;
    final cantidad = ahorro?.canceladas.length ?? 0;
    final menosAlMes = totales.isEmpty
        ? Formato.moneda(0, 'COP')
        : totales.map((t) => Formato.moneda(t.mensual, t.moneda)).join(' + ');

    return AppHeader(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppBotonVolver(texto: 'Dashboard', onPressed: () => context.go(Routers.dashboard)),
          const SizedBox(height: 16),
          const AppEtiqueta('Ahorro proyectado al año', color: AppColors.mutedHero),
          const SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              Formato.moneda(principal?.anual ?? 0, principal?.moneda ?? 'COP'),
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 36,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.9,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          // Si también hay ahorro en otra moneda, va aparte (no se convierte).
          for (final t in totales.skip(1))
            Text(
              '+ ${Formato.moneda(t.anual, t.moneda)} al año',
              style: const TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w700),
            ),
          const SizedBox(height: 3),
          Text(
            '$cantidad ${cantidad == 1 ? 'suscripción cancelada' : 'suscripciones canceladas'} · $menosAlMes menos al mes',
            style: const TextStyle(color: AppColors.mutedHero, fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _Subtitulo extends StatelessWidget {
  const _Subtitulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 9),
      child: Text(
        texto,
        style: const TextStyle(color: AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w800),
      ),
    );
  }
}

/// Barras del gasto de los últimos 6 meses; el mes actual va en primary.
class GraficaGasto extends StatelessWidget {
  const GraficaGasto({super.key, required this.serie});

  final EvolucionMoneda serie;

  static const _meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

  @override
  Widget build(BuildContext context) {
    final maximo = serie.meses.fold<double>(0, (m, g) => g.total > m ? g.total : m);
    final descripcion = serie.meses
        .map((g) => '${_meses[g.mes.month - 1]}: ${Formato.moneda(g.total, serie.moneda)}')
        .join(', ');
    return Semantics(
      label: 'Gasto por mes. $descripcion',
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
        child: SizedBox(
          height: 122,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (i, g) in serie.meses.indexed) ...[
                if (i > 0) const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            // Mínimo 4 % para que se vea la barra aunque sea 0.
                            heightFactor: maximo == 0 ? 0.04 : (g.total / maximo).clamp(0.04, 1.0),
                            widthFactor: 1,
                            child: Container(
                              decoration: BoxDecoration(
                                color: i == serie.meses.length - 1 ? AppColors.primary : const Color(0xFF1E2E4A),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(8),
                                  bottom: Radius.circular(3),
                                ),
                                border: i == serie.meses.length - 1 ? null : Border.all(color: AppColors.line),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        _meses[g.mes.month - 1],
                        style: const TextStyle(color: AppColors.muted, fontSize: 10.5, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FilaCancelada extends StatelessWidget {
  const _FilaCancelada(this.cancelada);

  final Cancelada cancelada;

  @override
  Widget build(BuildContext context) {
    final c = cancelada;
    return AppCard(
      padding: const EdgeInsets.all(13),
      child: Row(
        children: [
          LogoServicio(c.nombreServicio, size: 38),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.nombreServicio,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.text, fontSize: 14.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Cancelada el ${Formato.fechaCorta(c.fecha)}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '+${Formato.moneda(c.ahorroAnual, c.moneda)}',
                style: const TextStyle(
                  color: AppColors.link,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const Text(
                'al año',
                style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Aviso azul con ✓ después de cancelar desde la guía.
class _AvisoCancelada extends StatelessWidget {
  const _AvisoCancelada(this.servicio);

  final String servicio;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check, size: 18, color: AppColors.link),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '$servicio quedó en canceladas. Sumamos el ahorro proyectado y apagamos sus recordatorios.',
              style: const TextStyle(color: AppColors.text2, fontSize: 13, fontWeight: FontWeight.w700, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
