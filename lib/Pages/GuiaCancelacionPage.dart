import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../Common/AppTheme.dart';
import '../Common/Routers.dart';
import '../models/guia.dart';
import '../models/suscripcion.dart';
import '../services/api_client.dart';
import '../services/recordatorios_service.dart';
import '../services/suscripcion_service.dart';
import '../widgets/app_botones.dart';
import '../widgets/app_card.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_header.dart';
import '../widgets/presionable.dart';

/// Abre una URL en el navegador del celular (fuera de la app).
Future<bool> abrirEnNavegador(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

/// Guía de cancelación (pantalla 10 del diseño, flujo E). Muestra los pasos
/// del catálogo del servidor y, al confirmar, marca la suscripción como
/// cancelada y lleva a Ahorro.
class GuiaCancelacionPage extends StatefulWidget {
  const GuiaCancelacionPage({
    super.key,
    required this.id,
    required this.suscripcionService,
    this.recordatorios,
    this.abrirEnlace = abrirEnNavegador,
  });

  final int id;
  final SuscripcionService suscripcionService;
  final RecordatoriosService? recordatorios;

  /// Se puede reemplazar en los tests para no abrir un navegador real.
  final Future<bool> Function(Uri url) abrirEnlace;

  @override
  State<GuiaCancelacionPage> createState() => _GuiaCancelacionPageState();
}

class _GuiaCancelacionPageState extends State<GuiaCancelacionPage> {
  GuiaDeSuscripcion? _datos;
  String? _error;
  bool _confirmando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final datos = await widget.suscripcionService.guia(widget.id);
      if (mounted) setState(() => _datos = datos);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    }
  }

  Future<void> _abrirSitio(String enlace) async {
    bool abierto;
    try {
      abierto = await widget.abrirEnlace(Uri.parse(enlace));
    } catch (_) {
      abierto = false;
    }
    if (!abierto && mounted) mostrarToast(context, 'No se pudo abrir el navegador');
  }

  Future<void> _confirmar() async {
    HapticFeedback.lightImpact();
    final nombre = _datos!.nombreServicio;
    setState(() {
      _confirmando = true;
      _error = null;
    });
    try {
      await widget.suscripcionService.cambiarEstado(widget.id, EstadoSuscripcion.cancelada);
      // Quita los recordatorios de esta suscripción (ya no está en curso).
      widget.recordatorios?.sincronizar(widget.suscripcionService);
      if (!mounted) return;
      // go (no push): "atrás" desde Ahorro no vuelve a la guía.
      context.go(Routers.ahorro, extra: nombre);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _confirmando = false;
        _error = e.mensaje;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final datos = _datos;
    final guia = datos?.guia;
    return Scaffold(
      body: Column(
        children: [
          AppHeader(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppBotonVolver(onPressed: () => context.pop()),
                if (datos != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Cómo cancelar ${datos.nombreServicio}',
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    guia!.resumen,
                    style: const TextStyle(color: AppColors.mutedHero, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: datos == null
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: _error == null
                        ? const Center(child: CircularProgressIndicator())
                        : Column(children: [BannerError(_error!)]),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    children: [
                      if (_error != null) ...[BannerError(_error!), const SizedBox(height: 11)],
                      if (datos.esGenerica) ...[
                        _AvisoGenerica(datos.nombreServicio),
                        const SizedBox(height: 11),
                      ],
                      for (final (i, paso) in guia!.pasos.indexed) ...[
                        _Paso(numero: i + 1, texto: paso),
                        const SizedBox(height: 11),
                      ],
                      if (guia.enlaceDirecto != null) ...[
                        AppBotonSecundario(
                          texto: datos.esGenerica
                              ? 'Abrir suscripciones de Google Play'
                              : 'Abrir sitio de ${guia.nombreServicio}',
                          icon: Icons.open_in_new,
                          onPressed: () => _abrirSitio(guia.enlaceDirecto!),
                        ),
                        const SizedBox(height: 11),
                      ],
                      const SizedBox(height: 4),
                      const Text(
                        'El catálogo de guías se actualiza desde el servidor: si el proveedor cambia '
                        'su flujo, no hace falta publicar una nueva versión de la app.',
                        style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600, height: 1.5),
                      ),
                    ],
                  ),
          ),
          if (datos != null)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                color: AppColors.bar,
                border: Border(top: BorderSide(color: AppColors.divider)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Presionable(
                      child: FilledButton(
                        onPressed: _confirmando ? null : _confirmar,
                        child: _confirmando
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Ya cancelé, confirmar'),
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: _confirmando ? null : () => context.pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.muted,
                        minimumSize: const Size.fromHeight(42),
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      child: const Text('Lo haré después'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Paso extends StatelessWidget {
  const _Paso({required this.numero, required this.texto});

  final int numero;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface3,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AppColors.line2),
            ),
            child: Text(
              '$numero',
              style: const TextStyle(color: Color(0xFFCFE0FF), fontSize: 12.5, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(color: AppColors.text2, fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Aviso cuando no hay guía específica para el servicio.
class _AvisoGenerica extends StatelessWidget {
  const _AvisoGenerica(this.servicio);

  final String servicio;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.amberBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.55), width: 1.5),
      ),
      child: Text(
        'No tenemos una guía específica para $servicio. Estos pasos sirven para la mayoría de servicios.',
        style: const TextStyle(color: AppColors.amberStrong, fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.45),
      ),
    );
  }
}
