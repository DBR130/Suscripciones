import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Common/AppTheme.dart';
import '../Common/Routers.dart';
import '../models/suscripcion.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/suscripcion_service.dart';
import '../widgets/app_botones.dart';
import '../widgets/app_card.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_header.dart';
import '../widgets/estado_vacio.dart';
import '../widgets/logo_servicio.dart';
import '../widgets/suscripcion_card.dart';

/// Lista de suscripciones (pantalla 08 del diseño, pestaña 2).
class SuscripcionesPage extends StatefulWidget {
  const SuscripcionesPage({
    super.key,
    required this.authService,
    required this.suscripcionService,
  });

  final AuthService authService;
  final SuscripcionService suscripcionService;

  @override
  State<SuscripcionesPage> createState() => _SuscripcionesPageState();
}

class _SuscripcionesPageState extends State<SuscripcionesPage> {
  List<Suscripcion>? _todas;
  int? _dias;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final resultados = await Future.wait([
        widget.suscripcionService.listar(),
        widget.authService.obtenerDiasAnticipacion(),
      ]);
      if (!mounted) return;
      setState(() {
        _todas = resultados[0] as List<Suscripcion>;
        _dias = resultados[1] as int;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    }
  }

  Future<void> _abrir(String ruta) async {
    await context.push(ruta);
    if (mounted) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final todas = _todas ?? const <Suscripcion>[];
    final activas = todas.where((s) => s.estado != EstadoSuscripcion.cancelada).toList()
      ..sort((a, b) => a.fechaClave.compareTo(b.fechaClave));
    final canceladas = todas.length - activas.length;

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
                    'Suscripciones',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _todas == null
                        ? ' '
                        : '${activas.length} activas · $canceladas canceladas · avisos ${_dias ?? 3} días antes',
                    style: const TextStyle(
                      color: AppColors.mutedOnGradient,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    BannerError(_error!),
                    const SizedBox(height: 12),
                    if (_todas == null) ...[
                      AppBotonSecundario(
                        texto: 'Reintentar',
                        onPressed: () {
                          setState(() => _error = null);
                          _cargar();
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                  if (_todas == null && _error == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_todas != null && activas.isEmpty)
                    const EstadoVacio(
                      titulo: 'Tu lista está vacía',
                      texto: 'Las suscripciones que agregues aparecerán aquí.',
                    )
                  else
                    for (final s in activas)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 11),
                        child: _Fila(s, onAbrir: () => _abrir(Routers.detalle(s.id!))),
                      ),
                  if (_todas != null) ...[
                    const SizedBox(height: 3),
                    AppBotonPunteado(
                      texto: '+ Agregar suscripción',
                      onPressed: () => _abrir(Routers.nuevaSuscripcion),
                    ),
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

class _Fila extends StatelessWidget {
  const _Fila(this.suscripcion, {required this.onAbrir});

  final Suscripcion suscripcion;
  final VoidCallback onAbrir;

  @override
  Widget build(BuildContext context) {
    final s = suscripcion;
    return AppCard(
      destacada: esDestacada(s),
      child: Row(
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
                  style: const TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  lineaDeEstado(s),
                  style: const TextStyle(color: AppColors.muted, fontSize: 12.5, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onAbrir,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSoft,
              side: const BorderSide(color: AppColors.lineStrong),
              shape: const StadiumBorder(),
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
              textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.montoTexto),
                const SizedBox(width: 2),
                const Icon(Icons.chevron_right, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
