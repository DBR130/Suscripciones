import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Colores del logo "Cuenta regresiva" (design/logo/4-cuenta-regresiva/).
class ColoresLogo {
  ColoresLogo._();

  static const Color anillo = Color(0xFF60A5FA);
  static const Color tramoTenue = Color(0xFF17367B);
  static const Color s = Color(0xFFE9EFFA);
  static const Color fondo = Color(0xFF0B1220);
}

/// Animación de inicio de SubTrack, paso a paso como en
/// design/logo/4-cuenta-regresiva/animacion-inicio.md: 1500 ms de animación y
/// 300 ms de pausa; luego llama a [alTerminar].
///
/// Si la app aún no puede seguir (validando la sesión con el servidor
/// dormido), el anillo sigue girando suave hasta que se reemplace la pantalla.
/// Con las animaciones reducidas muestra el estado final y llama a
/// [alTerminar] a los 300 ms.
class AnimacionInicio extends StatefulWidget {
  const AnimacionInicio({super.key, this.alTerminar, this.ancho = 260});

  final VoidCallback? alTerminar;

  /// Ancho del logo con nombre (se reduce si la pantalla es más angosta).
  final double ancho;

  static const Duration duracion = Duration(milliseconds: 1500);
  static const Duration pausa = Duration(milliseconds: 300);

  @override
  State<AnimacionInicio> createState() => _AnimacionInicioState();
}

class _AnimacionInicioState extends State<AnimacionInicio> with TickerProviderStateMixin {
  // Intervalos del documento, en ms sobre 1500.
  static Interval _paso(int inicio, int duracion, Curve curva) =>
      Interval(inicio / 1500, (inicio + duracion) / 1500, curve: curva);

  late final AnimationController _controller =
      AnimationController(vsync: this, duration: AnimacionInicio.duracion);

  // 1. Anillo de fondo: opacidad.
  late final Animation<double> _fondo =
      CurvedAnimation(parent: _controller, curve: _paso(0, 200, Curves.easeOutCubic));
  // 2 y 3. Anillo y punto: el mismo valor, así el punto va en la punta.
  late final Animation<double> _trazo =
      CurvedAnimation(parent: _controller, curve: _paso(100, 700, Curves.easeInOutCubic));
  late final Animation<double> _escalaPunto =
      CurvedAnimation(parent: _controller, curve: _paso(100, 120, Curves.linear));
  // 4. S: escala 0.6 → 1 con rebote; opacidad en los primeros 150 ms.
  late final Animation<double> _escalaS = Tween<double>(begin: 0.6, end: 1)
      .animate(CurvedAnimation(parent: _controller, curve: _paso(750, 450, Curves.easeOutBack)));
  late final Animation<double> _opacidadS =
      CurvedAnimation(parent: _controller, curve: _paso(750, 150, Curves.linear));
  // 5. Nombre: opacidad y 12 px de izquierda a derecha.
  late final Animation<double> _nombre =
      CurvedAnimation(parent: _controller, curve: _paso(1100, 400, Curves.easeOutCubic));

  /// Giro del anillo en bucle (radianes) mientras se espera.
  final ValueNotifier<double> _giro = ValueNotifier(0);
  Ticker? _bucle;
  bool _iniciada = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciada) return;
    _iniciada = true;
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1;
      Future<void>.delayed(AnimacionInicio.pausa, _terminar);
    } else {
      _controller.forward().whenComplete(() {
        Future<void>.delayed(AnimacionInicio.pausa, () {
          _terminar();
          _empezarBucle();
        });
      });
    }
  }

  void _terminar() {
    if (mounted) widget.alTerminar?.call();
  }

  /// Gira el anillo y el punto: arranca despacio y sigue a una vuelta cada
  /// 1,8 s (velocidad · (t − τ·(1 − e^(−t/τ))), sin saltos).
  void _empezarBucle() {
    if (!mounted) return;
    const omega = 2 * math.pi / 1.8;
    const tau = 0.4;
    _bucle = createTicker((transcurrido) {
      final t = transcurrido.inMicroseconds / 1e6;
      _giro.value = omega * (t - tau * (1 - math.exp(-t / tau)));
    })..start();
  }

  @override
  void dispose() {
    _bucle?.dispose();
    _controller.dispose();
    _giro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, restricciones) {
      final ancho = math.min(widget.ancho, restricciones.maxWidth - 48);
      // Cuadrícula del logo con nombre: 239 × 64.
      final escala = ancho / 239;
      return SizedBox(
        width: ancho,
        height: 64 * escala,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _PintorMarca(
                  fondo: _fondo,
                  trazo: _trazo,
                  escalaPunto: _escalaPunto,
                  escalaS: _escalaS,
                  opacidadS: _opacidadS,
                  giro: _giro,
                ),
              ),
            ),
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _nombre,
                builder: (context, hijo) => Opacity(
                  opacity: _nombre.value,
                  child: Transform.translate(
                    offset: Offset(-12 * escala * (1 - _nombre.value), 0),
                    child: hijo,
                  ),
                ),
                child: SvgPicture.asset('assets/logo/nombre-oscuro.svg', fit: BoxFit.fill),
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// Anillo de fondo, anillo, punto y S en la cuadrícula de 108 del logo,
/// escalada a 0,59 como en logo-nombre-oscuro.svg.
class _PintorMarca extends CustomPainter {
  _PintorMarca({
    required this.fondo,
    required this.trazo,
    required this.escalaPunto,
    required this.escalaS,
    required this.opacidadS,
    required this.giro,
  }) : super(repaint: Listenable.merge([fondo, giro]));

  final Animation<double> fondo;
  final Animation<double> trazo;
  final Animation<double> escalaPunto;
  final Animation<double> escalaS;
  final Animation<double> opacidadS;
  final ValueListenable<double> giro;

  static const _centro = Offset(54, 54);
  static const double _radio = 27;

  static final Path _s = Path()
    ..moveTo(60.24, 43.2)
    ..arcToPoint(const Offset(54, 54), radius: const Radius.circular(7.2), largeArc: true, clockwise: false)
    ..arcToPoint(const Offset(47.76, 64.8), radius: const Radius.circular(7.2), largeArc: true, clockwise: true);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // 239 × 64 → tamaño real, y la marca a 0,59 dentro de esa cuadrícula.
    canvas.scale(size.width / 239);
    canvas.scale(0.59);

    // 1. Anillo de fondo.
    canvas.drawCircle(
      _centro,
      _radio,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = ColoresLogo.tramoTenue.withValues(alpha: fondo.value),
    );

    // 2. Anillo: desde las 12 en sentido horario hasta 270° × t.
    final t = trazo.value;
    final barrido = 1.5 * math.pi * t;
    final inicio = -math.pi / 2 + giro.value;
    if (t > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: _centro, radius: _radio),
        inicio,
        barrido,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..color = ColoresLogo.anillo,
      );
    }

    // 3. Punto en la punta del trazo (ángulo −90° + 270° × t).
    final e = escalaPunto.value;
    if (e > 0) {
      final angulo = inicio + barrido;
      final punto = _centro + Offset(math.cos(angulo), math.sin(angulo)) * _radio;
      canvas.drawCircle(punto, 6 * e, Paint()..color = ColoresLogo.s);
      canvas.drawCircle(
        punto,
        6 * e,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * e
          ..color = ColoresLogo.fondo,
      );
    }

    // 4. S desde el centro, con rebote.
    final o = opacidadS.value;
    if (o > 0) {
      canvas.save();
      canvas.translate(_centro.dx, _centro.dy);
      canvas.scale(escalaS.value);
      canvas.translate(-_centro.dx, -_centro.dy);
      canvas.drawPath(
        _s,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6.5
          ..strokeCap = StrokeCap.round
          ..color = ColoresLogo.s.withValues(alpha: o),
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PintorMarca oldDelegate) => false;
}
