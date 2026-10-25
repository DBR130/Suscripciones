import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Common/AppTheme.dart';
import '../Common/Routers.dart';
import '../widgets/app_marca.dart';

/// Bienvenida (pantalla 01 del diseño): 3 slides que se pasan con el dedo o
/// con "Siguiente". Se muestra en "/" cuando no hay sesión.
class BienvenidaPage extends StatefulWidget {
  const BienvenidaPage({super.key});

  @override
  State<BienvenidaPage> createState() => _BienvenidaPageState();
}

class _BienvenidaPageState extends State<BienvenidaPage> {
  static const _slides = [
    (
      titulo: 'Todo lo que pagas cada mes, en una sola lista.',
      texto: 'Monto, frecuencia y próxima fecha de cobro de cada suscripción. '
          'Sin tener que revisar el extracto línea por línea.',
    ),
    (
      titulo: 'Te avisamos antes del cobro, no después.',
      texto: 'Recordatorios antes de cada cobro recurrente, antes de que termine '
          'una prueba gratis y cuando un precio cambia.',
    ),
    (
      titulo: 'No adivinamos qué usas. Tú decides.',
      texto: 'La app nunca marca una suscripción como olvidada. Te da datos reales '
          'a tiempo y la decisión de cancelar es siempre tuya.',
    ),
  ];

  final _paginas = PageController();
  int _actual = 0;

  bool get _esUltimo => _actual == _slides.length - 1;

  @override
  void dispose() {
    _paginas.dispose();
    super.dispose();
  }

  void _siguiente() {
    if (_esUltimo) {
      context.go(Routers.registro);
      return;
    }
    _paginas.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.bienvenida),
        child: Stack(
          children: [
            // Orbes decorativos del diseño, detrás del contenido.
            const Positioned(top: -74, right: -44, child: _Orbe(206, AppColors.orbA, Alignment(-0.2, -0.2))),
            const Positioned(top: 104, left: -84, child: _Orbe(210, AppColors.orbB, Alignment.center)),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 34, 24, 26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppMarca.fila(),
                    const SizedBox(height: 30),
                    Expanded(
                      child: PageView.builder(
                        controller: _paginas,
                        itemCount: _slides.length,
                        onPageChanged: (i) => setState(() => _actual = i),
                        itemBuilder: (context, i) =>
                            _Slide(titulo: _slides[i].titulo, texto: _slides[i].texto),
                      ),
                    ),
                    _Puntos(total: _slides.length, actual: _actual),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _siguiente,
                        child: Text(_esUltimo ? 'Crear mi cuenta' : 'Siguiente'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => context.go(Routers.login),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.mutedHero,
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.all(10),
                          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                        child: const Text('Ya tengo cuenta'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un slide: título Display y texto, centrados en vertical. Si no cabe
/// (pantalla pequeña o letra grande), hace scroll en lugar de desbordarse.
class _Slide extends StatelessWidget {
  const _Slide({required this.titulo, required this.texto});

  final String titulo;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 31,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.93, // -0.03em
                  height: 1.12,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                texto,
                style: const TextStyle(
                  color: AppColors.mutedHero,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Indicador de slides: el activo mide 22×7 en accent; los demás, 7×7 en line-2.
class _Puntos extends StatelessWidget {
  const _Puntos({required this.total, required this.actual});

  final int total;
  final int actual;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Paso ${actual + 1} de $total',
      child: Row(
        children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) const SizedBox(width: 7),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: i == actual ? 22 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: i == actual ? AppColors.accent : AppColors.line2,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Círculo con degradado radial que se desvanece al 70 % del radio.
class _Orbe extends StatelessWidget {
  const _Orbe(this.tamano, this.color, this.centro);

  final double tamano;
  final Color color;
  final Alignment centro;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: tamano,
        height: tamano,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: centro,
            radius: 0.5,
            colors: [color, color.withValues(alpha: 0)],
            stops: const [0, 0.7],
          ),
        ),
      ),
    );
  }
}
