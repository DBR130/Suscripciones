import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Common/AppTheme.dart';
import '../Common/Routers.dart';
import '../widgets/app_botones.dart';
import '../widgets/app_feedback.dart';
import 'procesador_detecciones.dart';

/// Pantalla 04: revisa la cola de notificaciones de pago y las activas de la
/// barra, las interpreta y las envía al backend. Al terminar pasa a los
/// resultados (05).
class EscaneoPage extends StatefulWidget {
  const EscaneoPage({
    super.key,
    required this.procesador,
    this.inicio = false,
    this.duracionMinima = const Duration(milliseconds: 1900),
  });

  final ProcesadorDetecciones procesador;
  final bool inicio;

  /// El diseño muestra la animación al menos 1,9 s, aunque termine antes.
  final Duration duracionMinima;

  @override
  State<EscaneoPage> createState() => _EscaneoPageState();
}

class _EscaneoPageState extends State<EscaneoPage> with SingleTickerProviderStateMixin {
  late final AnimationController _pulso =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
  String? _error;

  @override
  void initState() {
    super.initState();
    _escanear();
  }

  @override
  void dispose() {
    _pulso.dispose();
    super.dispose();
  }

  Future<void> _escanear() async {
    setState(() => _error = null);
    _pulso.repeat(reverse: true);
    try {
      await Future.wait([widget.procesador.procesar(), Future<void>.delayed(widget.duracionMinima)]);
      if (mounted) context.pushReplacement(Routers.rutaDeteccion(inicio: widget.inicio));
    } catch (e) {
      // La cola queda intacta: se puede reintentar.
      if (!mounted) return;
      _pulso.stop();
      setState(() => _error = '$e');
    }
  }

  void _seguirSinDetectar() => context.go(widget.inicio ? Routers.preferencias : Routers.dashboard);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: ScaleTransition(
                  scale: Tween(begin: 0.92, end: 1.05).animate(CurvedAnimation(parent: _pulso, curve: Curves.easeInOut)),
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.surface2,
                      border: Border.all(color: AppColors.primary, width: 2),
                    ),
                    child: const Icon(Icons.search_rounded, color: AppColors.link, size: 40),
                  ),
                ),
              ),
              const SizedBox(height: 26),
              const Text(
                'Revisando tus notificaciones de pago…',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4),
              ),
              const SizedBox(height: 8),
              const Text(
                'Buscamos cobros que se repitan con el mismo monto y comercio.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 13.5, fontWeight: FontWeight.w500, height: 1.5),
              ),
              const SizedBox(height: 22),
              if (_error == null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: const LinearProgressIndicator(
                    minHeight: 6,
                    color: AppColors.primary,
                    backgroundColor: AppColors.surface,
                  ),
                )
              else ...[
                const BannerError('No pudimos revisar tus cobros. Revisa tu conexión e inténtalo de nuevo.'),
                const SizedBox(height: 14),
                FilledButton(onPressed: _escanear, child: const Text('Reintentar')),
                const SizedBox(height: 10),
                AppBotonSecundario(texto: 'Seguir sin detectar', onPressed: _seguirSinDetectar),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
