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
      // Flechas de renovación: "cobro que se repite" (las líneas de lista
      // parecían un menú).
      icono: Icons.autorenew_rounded,
      activo: Icons.autorenew_rounded,
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
              const SizedBox(width: 8),
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

/// Las 4 pestañas. Las inactivas muestran solo el ícono; la activa, ícono y
/// nombre dentro de una píldora que se ensancha con una animación suave.
class _Pestanas extends StatelessWidget {
  const _Pestanas({required this.activa, required this.onPestana});

  final int activa;
  final ValueChanged<int> onPestana;

  Widget _pestana(int i, ({String ruta, IconData icono, IconData activo, String texto}) p) => _Pestana(
        icono: i == activa ? p.activo : p.icono,
        texto: p.texto,
        activa: i == activa,
        onTap: () => onPestana(i),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (final (i, p) in AppShell._pestanas.indexed)
            if (i == activa)
              // Solo la activa es flexible: toma el ancho de su nombre y, en
              // pantallas angostas, se ajusta en vez de desbordarse.
              Flexible(child: _pestana(i, p))
            else
              _pestana(i, p),
        ],
      ),
    );
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

  static const Duration _duracion = Duration(milliseconds: 300);

  @override
  Widget build(BuildContext context) {
    final duracion = MediaQuery.of(context).disableAnimations ? Duration.zero : _duracion;
    // Lectores de pantalla: el nombre siempre (también en las inactivas). Al
    // mantener presionado se ve el nombre en un tooltip.
    return Semantics(
      container: true,
      selected: activa,
      button: true,
      label: texto,
      excludeSemantics: true,
      child: Tooltip(
        message: texto,
        excludeFromSemantics: true,
        child: Presionable(
          onTap: onTap,
          escala: 0.92,
          child: AnimatedContainer(
            duration: duracion,
            curve: Curves.easeOutCubic,
            height: 46,
            constraints: const BoxConstraints(minWidth: 42),
            padding: EdgeInsets.symmetric(horizontal: activa ? 12 : 10),
            decoration: BoxDecoration(
              color: activa ? AppColors.primary.withValues(alpha: 0.28) : AppColors.primary.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: activa ? AppColors.accent.withValues(alpha: 0.35) : AppColors.accent.withValues(alpha: 0),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icono, size: 22, color: activa ? AppColors.link : AppColors.muted),
                // El nombre aparece y la píldora crece a su ancho.
                Flexible(
                  child: AnimatedSize(
                    duration: duracion,
                    curve: Curves.easeOutCubic,
                    child: activa
                        ? Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(
                              texto,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.fade,
                              style: const TextStyle(
                                color: AppColors.text,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
