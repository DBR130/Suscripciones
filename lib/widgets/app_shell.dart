import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../Common/AppTheme.dart';
import '../Common/Routers.dart';
import '../services/avisos_nuevos.dart';
import 'presionable.dart';

/// Pantallas con sesión: barra de pestañas flotante (Resumen, Suscripciones,
/// Análisis, Perfil) y, a su derecha, el botón "+" para agregar una
/// suscripción. Los avisos están en la campana de cada encabezado.
///
/// El contenido pasa por debajo de la barra (vidrio esmerilado): cada
/// pantalla deja abajo el espacio de [rellenoInferior].
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.child, this.avisosNuevos});

  final Widget child;

  /// Contador de la campana; null en los tests.
  final AvisosNuevos? avisosNuevos;

  /// Se incrementa al volver del formulario abierto con "+", para que la
  /// pantalla visible recargue sus datos.
  static final ValueNotifier<int> cambios = ValueNotifier(0);

  static const double altoBarra = 64;
  static const double margen = 16;

  /// Espacio para que la barra no tape la última tarjeta. Dentro del shell la
  /// barra ya está en MediaQuery.padding.bottom (Scaffold.extendBody).
  static EdgeInsets rellenoInferior(BuildContext context) =>
      EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 8);

  static const _pestanas = [
    (ruta: Routers.dashboard, icono: Icons.home_outlined, activo: Icons.home_rounded, texto: 'Resumen'),
    (
      ruta: Routers.suscripciones,
      icono: Icons.format_list_bulleted,
      activo: Icons.format_list_bulleted_rounded,
      texto: 'Suscripciones',
    ),
    (ruta: Routers.analisis, icono: Icons.insights_outlined, activo: Icons.insights_rounded, texto: 'Análisis'),
    (ruta: Routers.perfil, icono: Icons.person_outline, activo: Icons.person_rounded, texto: 'Perfil'),
  ];

  /// Pestaña de la ruta visible, o -1 si ninguna.
  static int indiceDe(String ubicacion) {
    // El detalle (/suscripcion/:id) pertenece a la pestaña Suscripciones y
    // Ahorro a Análisis.
    if (ubicacion.startsWith(Routers.suscripciones) || ubicacion.startsWith('/suscripcion/')) return 1;
    if (ubicacion.startsWith(Routers.analisis) || ubicacion.startsWith(Routers.ahorro)) return 2;
    if (ubicacion.startsWith(Routers.perfil)) return 3;
    if (ubicacion.startsWith(Routers.dashboard)) return 0;
    return -1;
  }

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  @override
  void initState() {
    super.initState();
    widget.avisosNuevos?.actualizar();
  }

  Future<void> _agregar() async {
    HapticFeedback.lightImpact();
    await context.push(Routers.nuevaSuscripcion);
    AppShell.cambios.value++;
    widget.avisosNuevos?.actualizar();
  }

  @override
  Widget build(BuildContext context) {
    // Ruta visible (también las abiertas con push, como el detalle), para
    // marcar la pestaña activa.
    final delegado = GoRouter.of(context).routerDelegate;
    final scaffold = Scaffold(
      extendBody: true,
      body: widget.child,
      bottomNavigationBar: ListenableBuilder(
        listenable: delegado,
        builder: (context, _) => _BarraFlotante(
          activa: AppShell.indiceDe(delegado.currentConfiguration.uri.path),
          onPestana: (i) {
            HapticFeedback.selectionClick();
            context.go(AppShell._pestanas[i].ruta);
          },
          onAgregar: _agregar,
        ),
      ),
    );
    final avisos = widget.avisosNuevos;
    return avisos == null ? scaffold : AvisosNuevosScope(notifier: avisos, child: scaffold);
  }
}

class _BarraFlotante extends StatelessWidget {
  const _BarraFlotante({required this.activa, required this.onPestana, required this.onAgregar});

  final int activa;
  final ValueChanged<int> onPestana;
  final VoidCallback onAgregar;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: AppShell.margen),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppShell.margen),
        child: SizedBox(
          height: AppShell.altoBarra,
          child: Row(
            children: [
              Expanded(
                child: _Vidrio(
                  forma: const StadiumBorder(),
                  child: _Pestanas(activa: activa, onPestana: onPestana),
                ),
              ),
              const SizedBox(width: 10),
              Semantics(
                button: true,
                label: 'Agregar suscripción',
                excludeSemantics: true,
                child: Presionable(
                  onTap: onAgregar,
                  escala: 0.9,
                  child: const _Vidrio(
                    forma: CircleBorder(),
                    relleno: AppColors.primary,
                    child: SizedBox.square(
                      dimension: AppShell.altoBarra,
                      child: Icon(Icons.add_rounded, color: Colors.white, size: 28),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fondo semitransparente con desenfoque, borde sutil y sombra suave.
class _Vidrio extends StatelessWidget {
  const _Vidrio({required this.forma, required this.child, this.relleno});

  final OutlinedBorder forma;
  final Widget child;

  /// Color sólido (el botón "+"); sin él, el panel translúcido.
  final Color? relleno;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: forma,
        shadows: [
          BoxShadow(
            color: (relleno ?? Colors.black).withValues(alpha: relleno == null ? 0.35 : 0.4),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: forma),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: relleno ?? AppColors.panel.withValues(alpha: 0.72),
              shape: forma.copyWith(
                side: BorderSide(color: Colors.white.withValues(alpha: relleno == null ? 0.09 : 0.18)),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Las 4 pestañas con la "píldora" de la activa, que se desliza entre ellas.
class _Pestanas extends StatelessWidget {
  const _Pestanas({required this.activa, required this.onPestana});

  final int activa;
  final ValueChanged<int> onPestana;

  @override
  Widget build(BuildContext context) {
    final reducir = MediaQuery.of(context).disableAnimations;
    const n = 4;
    return LayoutBuilder(builder: (context, restricciones) {
      final ancho = restricciones.maxWidth / n;
      return Stack(
        children: [
          AnimatedPositioned(
            duration: reducir ? Duration.zero : const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            left: (activa < 0 ? 0 : activa) * ancho + 5,
            width: ancho - 10,
            top: 7,
            bottom: 7,
            child: AnimatedOpacity(
              opacity: activa < 0 ? 0 : 1,
              duration: reducir ? Duration.zero : const Duration(milliseconds: 200),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (final (i, p) in AppShell._pestanas.indexed)
                Expanded(
                  child: _Pestana(
                    icono: i == activa ? p.activo : p.icono,
                    texto: p.texto,
                    activa: i == activa,
                    onTap: () => onPestana(i),
                  ),
                ),
            ],
          ),
        ],
      );
    });
  }
}

class _Pestana extends StatelessWidget {
  const _Pestana({
    required this.icono,
    required this.texto,
    required this.activa,
    required this.onTap,
  });

  final IconData icono;
  final String texto;
  final bool activa;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = activa ? AppColors.text : AppColors.muted;
    return Semantics(
      selected: activa,
      button: true,
      child: Presionable(
        onTap: onTap,
        escala: 0.9,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icono, size: 21, color: activa ? AppColors.link : AppColors.muted),
              const SizedBox(height: 3),
              // "Suscripciones" se reduce un poco en pantallas angostas.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  texto,
                  maxLines: 1,
                  style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
