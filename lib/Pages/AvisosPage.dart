import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Common/AppTheme.dart';
import '../Common/Routers.dart';
import '../models/aviso.dart';
import '../services/api_client.dart';
import '../services/suscripcion_service.dart';
import '../utils/formato.dart';
import '../widgets/app_botones.dart';
import '../widgets/app_card.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_header.dart';
import '../widgets/estado_vacio.dart';

/// "hoy", "ayer" o "14 sep" (fecha de cada aviso).
String fechaRelativa(DateTime fecha, DateTime hoy) {
  final dias = DateTime.utc(hoy.year, hoy.month, hoy.day)
      .difference(DateTime.utc(fecha.year, fecha.month, fecha.day))
      .inDays;
  return switch (dias) {
    0 => 'hoy',
    1 => 'ayer',
    _ => Formato.fechaCorta(fecha),
  };
}

/// Avisos (pantalla 11 del diseño, pestaña 3) con datos reales de
/// GET /api/avisos: próximos cobros, pruebas que terminan y cambios de precio.
class AvisosPage extends StatefulWidget {
  const AvisosPage({super.key, required this.suscripcionService});

  final SuscripcionService suscripcionService;

  @override
  State<AvisosPage> createState() => _AvisosPageState();
}

class _AvisosPageState extends State<AvisosPage> {
  List<Aviso>? _avisos;
  int _dias = 3;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final r = await widget.suscripcionService.avisos();
      if (!mounted) return;
      setState(() {
        _avisos = r.avisos;
        _dias = r.dias;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    }
  }

  Future<void> _abrir(int id) async {
    await context.push(Routers.detalle(id));
    if (mounted) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final hoy = DateUtils.dateOnly(DateTime.now());
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            AppHeader(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Avisos',
                    style: TextStyle(color: AppColors.text, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Recordatorios enviados · $_dias días antes de cada cobro',
                    style: const TextStyle(color: AppColors.mutedHero, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    BannerError(_error!),
                    const SizedBox(height: 12),
                    AppBotonSecundario(
                      texto: 'Reintentar',
                      onPressed: () {
                        setState(() => _error = null);
                        _cargar();
                      },
                    ),
                  ] else if (_avisos == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_avisos!.isEmpty)
                    const EstadoVacio(
                      titulo: 'No tienes avisos por ahora',
                      texto: 'Aquí verás los cobros que se acercan, las pruebas gratis que '
                          'terminan y los cambios de precio.',
                    )
                  else
                    for (final a in _avisos!)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 11),
                        child: _TarjetaAviso(
                          aviso: a,
                          fecha: fechaRelativa(a.fechaAviso, hoy),
                          onTap: () => _abrir(a.suscripcionId),
                        ),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TarjetaAviso extends StatelessWidget {
  const _TarjetaAviso({required this.aviso, required this.fecha, required this.onTap});

  final Aviso aviso;
  final String fecha;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      aviso.tipo.etiqueta.toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  Text(
                    fecha,
                    style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                aviso.titulo,
                style: const TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(
                aviso.cuerpo,
                style: const TextStyle(color: AppColors.muted, fontSize: 12.5, fontWeight: FontWeight.w500, height: 1.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
