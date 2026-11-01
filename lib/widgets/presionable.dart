import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';

/// Se hunde levemente (escala 0,96) mientras se mantiene presionado, como
/// respuesta táctil. Sin animación si el sistema las tiene reducidas.
///
/// Escucha el dedo con un Listener, sin competir por el toque: puede envolver
/// un botón (FilledButton, OutlinedButton...) que tiene su propio onPressed.
/// Con [onTap] además hace de botón.
class Presionable extends StatefulWidget {
  const Presionable({super.key, required this.child, this.onTap, this.escala = 0.96});

  final Widget child;
  final VoidCallback? onTap;
  final double escala;

  @override
  State<Presionable> createState() => _PresionableState();
}

class _PresionableState extends State<Presionable> {
  bool _abajo = false;
  Offset? _inicio;

  void _cambiar(bool abajo) {
    if (_abajo != abajo) setState(() => _abajo = abajo);
  }

  @override
  Widget build(BuildContext context) {
    final reducir = MediaQuery.of(context).disableAnimations;
    Widget hijo = AnimatedScale(
      scale: _abajo && !reducir ? widget.escala : 1,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: widget.child,
    );
    if (widget.onTap != null) {
      hijo = GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onTap, child: hijo);
    }
    return Listener(
      onPointerDown: (e) {
        _inicio = e.position;
        _cambiar(true);
      },
      // Si el dedo se desliza (scroll), deja de hundirse.
      onPointerMove: (e) {
        if (_inicio != null && (e.position - _inicio!).distance > kTouchSlop) _cambiar(false);
      },
      onPointerUp: (_) => _cambiar(false),
      onPointerCancel: (_) => _cambiar(false),
      child: hijo,
    );
  }
}
