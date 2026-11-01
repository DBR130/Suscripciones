import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Common/AppTheme.dart';
import '../Common/Routers.dart';
import '../widgets/app_botones.dart';
import '../widgets/app_card.dart';
import '../widgets/app_feedback.dart';
import 'historial_sms.dart';

/// "¿Buscamos suscripciones que ya pagas?": divulgación destacada (prominent
/// disclosure, como exige Google Play) antes de pedir READ_SMS. Es opcional y
/// separada del acceso a notificaciones: el permiso se pide solo si el usuario
/// toca "Buscar en mis SMS". Si lo rechaza, la app sigue igual.
///
/// Se abre después de la pantalla 03 ([trasPermisos]) y desde Perfil. Solo
/// existe en la versión "completa" (en "sinSms" no se llega aquí).
class HistorialSmsPage extends StatefulWidget {
  const HistorialSmsPage({
    super.key,
    required this.historial,
    this.inicio = false,
    this.trasPermisos = false,
  });

  final HistorialSms historial;

  /// Viene del registro (onboarding).
  final bool inicio;

  /// Viene de la pantalla 03: "Ahora no" sigue con el escaneo de las
  /// notificaciones. Si no (desde Perfil), "Ahora no" vuelve atrás.
  final bool trasPermisos;

  /// Textos de la divulgación (también los usan los tests y docs/google-play.md).
  static const titulo = '¿Buscamos suscripciones que ya pagas?';
  static const puntos = [
    (
      'Qué leemos',
      'Revisamos tus SMS recibidos, pero solo usamos los que parecen cobros de bancos '
          '(por ejemplo, «Compraste \$19.900 en NETFLIX»). Los demás se descartan en el '
          'celular sin guardarse.'
    ),
    ('Para qué', 'Para encontrar las suscripciones que ya pagas y agregarlas a SubTrack.'),
    (
      'Qué sale del celular',
      'Solo el monto, el comercio y la fecha de los cobros de suscripciones. Ni el texto '
          'de tus SMS, ni tus compras puntuales, ni tus mensajes personales.'
    ),
    ('Una sola revisión', 'Revisamos una vez los últimos 6 meses, cuando tú lo pides.'),
    (
      'Tú decides',
      'Puedes quitar el permiso cuando quieras en los ajustes de Android '
          '(Aplicaciones → SubTrack → Permisos → SMS).'
    ),
  ];

  @override
  State<HistorialSmsPage> createState() => _HistorialSmsPageState();
}

class _HistorialSmsPageState extends State<HistorialSmsPage> with WidgetsBindingObserver {
  bool _pidiendo = false;
  bool _esperandoAjustes = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Al volver de los ajustes: si ya concedió el permiso, busca.
  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state != AppLifecycleState.resumed || !_esperandoAjustes) return;
    _esperandoAjustes = false;
    if (await widget.historial.permisoConcedido() && mounted) {
      context.pushReplacement(Routers.rutaEscaneo(inicio: widget.inicio, historial: true));
    }
  }

  /// Android ya no muestra el diálogo: hay que darlo en los ajustes.
  bool _bloqueado = false;

  Future<void> _buscar() async {
    setState(() => _pidiendo = true);
    final permiso = await widget.historial.pedirPermiso();
    if (!mounted) return;
    setState(() => _pidiendo = false);
    switch (permiso) {
      case PermisoSms.concedido:
        context.pushReplacement(Routers.rutaEscaneo(inicio: widget.inicio, historial: true));
      case PermisoSms.bloqueado:
        setState(() => _bloqueado = true);
      case PermisoSms.denegado || PermisoSms.noDisponible:
        mostrarToast(context, 'Sin problema: seguimos detectando los cobros nuevos');
        _ahoraNo();
    }
  }

  Future<void> _abrirAjustes() async {
    _esperandoAjustes = true;
    await widget.historial.abrirPermisosApp();
  }

  void _ahoraNo() {
    if (widget.trasPermisos) {
      context.pushReplacement(Routers.rutaEscaneo(inicio: widget.inicio));
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routers.perfil);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.line2),
                        ),
                        child: const Icon(Icons.sms_outlined, color: AppColors.link),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      HistorialSmsPage.titulo,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        height: 1.18,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Las notificaciones solo muestran los cobros nuevos. Si nos dejas revisar tus '
                      'SMS, también encontramos las suscripciones que pagabas antes de instalar SubTrack.',
                      style: TextStyle(color: AppColors.muted, fontSize: 13.5, fontWeight: FontWeight.w500, height: 1.5),
                    ),
                    const SizedBox(height: 18),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (i, (titulo, texto)) in HistorialSmsPage.puntos.indexed) ...[
                            if (i > 0) const SizedBox(height: 12),
                            Text(
                              titulo,
                              style: const TextStyle(color: AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              texto,
                              style: const TextStyle(
                                color: AppColors.text2,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_bloqueado) ...[
                      const SizedBox(height: 14),
                      _PermisoBloqueado(onAbrirAjustes: _abrirAjustes),
                    ],
                    const Spacer(),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _pidiendo ? null : _buscar,
                      child: const Text('Buscar en mis SMS'),
                    ),
                    const SizedBox(height: 10),
                    AppBotonSecundario(texto: 'Ahora no', onPressed: _pidiendo ? null : _ahoraNo),
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

/// El usuario rechazó el permiso antes y Android ya no vuelve a preguntar.
class _PermisoBloqueado extends StatelessWidget {
  const _PermisoBloqueado({required this.onAbrirAjustes});

  final VoidCallback onAbrirAjustes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.amberBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.amberLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Android ya no muestra la pregunta',
            style: TextStyle(color: AppColors.amber, fontSize: 13.5, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Antes rechazaste el permiso. Si quieres buscar en tus SMS, permítelo en los ajustes: '
            'Permisos → SMS → Permitir. Si no, toca «Ahora no»: la app funciona igual.',
            style: TextStyle(color: AppColors.text2, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.5),
          ),
          const SizedBox(height: 10),
          AppBotonSecundario(texto: 'Abrir los permisos de SubTrack', ambar: true, onPressed: onAbrirAjustes),
        ],
      ),
    );
  }
}
