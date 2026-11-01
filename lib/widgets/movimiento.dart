import 'package:flutter/material.dart';

import '../Common/AppTheme.dart';

/// Animaciones pequeñas que comparten las pantallas. Todas respetan
/// "reducir animaciones" (MediaQuery.disableAnimations): muestran el estado
/// final sin moverse.
bool animacionesReducidas(BuildContext context) => MediaQuery.of(context).disableAnimations;

/// Transición entre pantallas: fundido con un desplazamiento corto hacia
/// arriba (24 px aprox.). Se usa en el tema para todas las rutas.
class TransicionSuave extends PageTransitionsBuilder {
  const TransicionSuave();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 320);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 260);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (animacionesReducidas(context)) return child;
    final entrada = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    return FadeTransition(
      opacity: entrada,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(entrada),
        child: child,
      ),
    );
  }
}

/// Aparece con fundido y subiendo 14 px, [indice] × 55 ms después que el
/// anterior (hasta el octavo), para las tarjetas de una lista recién cargada.
/// Usa un solo controlador por elemento, sin temporizadores.
class AparicionEscalonada extends StatefulWidget {
  const AparicionEscalonada({super.key, required this.indice, required this.child});

  final int indice;
  final Widget child;

  static const Duration _paso = Duration(milliseconds: 55);
  static const Duration _duracion = Duration(milliseconds: 380);

  @override
  State<AparicionEscalonada> createState() => _AparicionEscalonadaState();
}

class _AparicionEscalonadaState extends State<AparicionEscalonada> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _valor;

  @override
  void initState() {
    super.initState();
    final retraso = AparicionEscalonada._paso * widget.indice.clamp(0, 8);
    final total = retraso + AparicionEscalonada._duracion;
    _controller = AnimationController(vsync: this, duration: total);
    _valor = CurvedAnimation(
      parent: _controller,
      curve: Interval(retraso.inMicroseconds / total.inMicroseconds, 1, curve: Curves.easeOutCubic),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_controller.isDismissed) return;
    if (animacionesReducidas(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _valor,
      builder: (context, hijo) => Opacity(
        opacity: _valor.value,
        child: Transform.translate(offset: Offset(0, 14 * (1 - _valor.value)), child: hijo),
      ),
      child: widget.child,
    );
  }
}

/// Un número que "cuenta" desde 0 (o desde su valor anterior) hasta [valor].
class NumeroAnimado extends StatelessWidget {
  const NumeroAnimado({
    super.key,
    required this.valor,
    required this.formato,
    this.style,
    this.duracion = const Duration(milliseconds: 900),
  });

  final double valor;
  final String Function(double) formato;
  final TextStyle? style;
  final Duration duracion;

  @override
  Widget build(BuildContext context) {
    if (animacionesReducidas(context)) return Text(formato(valor), style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: valor),
      duration: duracion,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(formato(v), style: style),
    );
  }
}

/// Brillo (shimmer) que recorre los [CajaEsqueleto] de adentro mientras se
/// cargan los datos. Con animaciones reducidas queda quieto.
class Esqueleto extends StatefulWidget {
  const Esqueleto({super.key, required this.child});

  final Widget child;

  @override
  State<Esqueleto> createState() => _EsqueletoState();
}

class _EsqueletoState extends State<Esqueleto> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (animacionesReducidas(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Cargando',
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, hijo) {
            // Franja clara de izquierda a derecha (de -1 a 2 veces el ancho).
            final x = -1 + 3 * _controller.value;
            return ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (rect) => LinearGradient(
                begin: Alignment(x - 1, -0.3),
                end: Alignment(x + 1, 0.3),
                colors: const [AppColors.surface, Color(0xFF22304A), AppColors.surface],
                stops: const [0.3, 0.5, 0.7],
              ).createShader(rect),
              child: hijo,
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}

/// Bloque gris de un esqueleto de carga.
class CajaEsqueleto extends StatelessWidget {
  const CajaEsqueleto({super.key, this.alto = 14, this.ancho, this.radio = 8});

  final double alto;
  final double? ancho;
  final double radio;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: alto,
      width: ancho,
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(radio)),
    );
  }
}

/// Esqueleto de una lista de tarjetas (logo, dos líneas y el monto), para el
/// dashboard, la lista de suscripciones y el detalle.
class EsqueletoTarjetas extends StatelessWidget {
  const EsqueletoTarjetas({super.key, this.cantidad = 4, this.titulo = true});

  final int cantidad;

  /// Una línea de título de sección arriba.
  final bool titulo;

  @override
  Widget build(BuildContext context) {
    return Esqueleto(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (titulo) ...[
            const CajaEsqueleto(alto: 16, ancho: 130),
            const SizedBox(height: 14),
          ],
          for (var i = 0; i < cantidad; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 11),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.line),
              ),
              child: const Row(
                children: [
                  CajaEsqueleto(alto: 44, ancho: 44, radio: 12),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FractionallySizedBox(widthFactor: 0.55, child: CajaEsqueleto(alto: 14)),
                        SizedBox(height: 8),
                        FractionallySizedBox(widthFactor: 0.8, child: CajaEsqueleto(alto: 11)),
                      ],
                    ),
                  ),
                  SizedBox(width: 12),
                  CajaEsqueleto(alto: 30, ancho: 70, radio: 99),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
