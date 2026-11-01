import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Common/AppTheme.dart';
import '../Common/Routers.dart';
import '../services/recordatorios_service.dart';
import '../widgets/app_botones.dart';
import '../widgets/app_card.dart';
import 'aviso_deteccion_pausada.dart';
import 'historial_sms.dart';
import 'lector_notificaciones.dart';
import 'vigilante_deteccion.dart';

/// Pantalla 03: permiso para leer notificaciones de pago. "Dar permiso y
/// detectar" abre los ajustes de "Acceso a notificaciones" y, al volver con
/// el permiso concedido, pasa al escaneo (04).
///
/// [inicio] = viene del registro (onboarding): al final sigue la pantalla 06.
/// Si no, se abrió desde Perfil.
class PermisosPage extends StatefulWidget {
  const PermisosPage({super.key, required this.vigilante, this.recordatorios, this.historial, this.inicio = false});

  /// Distingue permiso concedido de lector conectado: con el permiso ya dado
  /// pero el lector desconectado, guía a apagar y encender el acceso.
  final VigilanteDeteccion vigilante;
  LectorNotificaciones get lector => vigilante.lector;

  /// Para abrir la información de la app ("Permitir ajustes restringidos").
  final RecordatoriosService? recordatorios;

  /// Versión "completa": después del acceso a notificaciones se ofrece, aparte
  /// y opcional, buscar en el historial de SMS.
  final HistorialSms? historial;
  final bool inicio;

  @override
  State<PermisosPage> createState() => _PermisosPageState();
}

class _PermisosPageState extends State<PermisosPage> with WidgetsBindingObserver {
  /// Fue a los ajustes y volvió sin el permiso: puede ser "Ajuste restringido".
  bool _volvioSinPermiso = false;
  bool _esperandoAjustes = false;

  /// Permiso concedido pero el lector no conecta (HyperOS tras reinstalar).
  bool _pausada = false;
  bool _comprobando = false;

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _esperandoAjustes) _alVolverDeAjustes();
  }

  Future<void> _alVolverDeAjustes() async {
    _esperandoAjustes = false;
    final permiso = (await widget.lector.estado()).permiso;
    if (!mounted) return;
    if (permiso) {
      await _comprobarYSeguir();
    } else {
      setState(() {
        _volvioSinPermiso = true;
        _pausada = false;
      });
    }
  }

  Future<void> _darPermiso() async {
    if ((await widget.lector.estado()).permiso) {
      await _comprobarYSeguir();
      return;
    }
    await _abrirAjustes();
  }

  Future<void> _abrirAjustes() async {
    _esperandoAjustes = true;
    await widget.lector.abrirAjustesAcceso();
  }

  /// Con el permiso concedido, espera a que el lector conecte (intentando
  /// reconectarlo). Si conecta, sigue al escaneo; si no, explica qué hacer.
  Future<void> _comprobarYSeguir() async {
    setState(() => _comprobando = true);
    final estado = await widget.vigilante.verificar(motivo: 'pantalla de permisos');
    if (!mounted) return;
    setState(() {
      _comprobando = false;
      _pausada = estado == EstadoDeteccion.pausada;
      _volvioSinPermiso = estado == EstadoDeteccion.sinPermiso;
    });
    if (estado == EstadoDeteccion.activa) _irAEscaneo();
  }

  Future<void> _irAEscaneo() async {
    final conHistorial = await widget.historial?.disponible() ?? false;
    if (!mounted) return;
    context.pushReplacement(conHistorial
        ? Routers.rutaHistorialSms(inicio: widget.inicio, trasPermisos: true)
        : Routers.rutaEscaneo(inicio: widget.inicio));
  }

  Future<void> _aMano() async {
    if (widget.inicio) {
      // Formulario (13) y después la preferencia de recordatorio (06).
      await context.push(Routers.nuevaSuscripcion);
      if (mounted) context.go(Routers.preferencias);
    } else {
      context.pushReplacement(Routers.nuevaSuscripcion);
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
                    if (!widget.inicio)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => context.pop(),
                          icon: const Icon(Icons.chevron_left),
                          label: const Text('Volver'),
                        ),
                      ),
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
                        child: const Icon(Icons.notifications_none_rounded, color: AppColors.link),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Permiso para leer notificaciones de pago',
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
                      'Con este permiso detectamos automáticamente qué suscripciones tienes, '
                      'cuánto cuestan y cada cuánto se cobran.',
                      style: TextStyle(color: AppColors.muted, fontSize: 13.5, fontWeight: FontWeight.w500, height: 1.5),
                    ),
                    const SizedBox(height: 18),
                    const AppCard(
                      child: Column(
                        children: [
                          _Garantia('Solo leemos notificaciones que parecen cobros: comercio, monto y fecha.'),
                          SizedBox(height: 10),
                          _Garantia('No leemos mensajes personales, chats ni el contenido de otras apps.'),
                          SizedBox(height: 10),
                          _Garantia('Puedes revocar el permiso desde Configuración cuando quieras.'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'En iOS no es posible leer notificaciones de otras apps: allí el registro es '
                      'manual o por reenvío de correos de cobro.',
                      style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600, height: 1.5),
                    ),
                    if (_volvioSinPermiso) ...[
                      const SizedBox(height: 14),
                      _AjusteRestringido(onAbrirInfo: widget.recordatorios?.abrirAjustesApp),
                    ],
                    if (_pausada) ...[
                      const SizedBox(height: 14),
                      AvisoDeteccionPausada(onAbrirAjuste: _abrirAjustes),
                    ],
                    const Spacer(),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _comprobando ? null : _darPermiso,
                      child: Text(_comprobando ? 'Comprobando el lector…' : 'Dar permiso y detectar'),
                    ),
                    const SizedBox(height: 10),
                    AppBotonSecundario(texto: 'Prefiero agregarlas a mano', ambar: true, onPressed: _aMano),
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

class _Garantia extends StatelessWidget {
  const _Garantia(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('✓', style: TextStyle(color: AppColors.accent, fontSize: 14, fontWeight: FontWeight.w800)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            texto,
            style: const TextStyle(color: AppColors.text2, fontSize: 13, fontWeight: FontWeight.w600, height: 1.45),
          ),
        ),
      ],
    );
  }
}

/// Android 13+ bloquea el acceso a notificaciones de apps instaladas desde un
/// APK ("Ajuste restringido") hasta que el usuario lo permite a mano.
class _AjusteRestringido extends StatelessWidget {
  const _AjusteRestringido({this.onAbrirInfo});

  final Future<void> Function()? onAbrirInfo;

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
            '¿Android no te dejó activarlo?',
            style: TextStyle(color: AppColors.amber, fontSize: 13.5, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Si apareció «Ajuste restringido» (pasa con apps instaladas desde un archivo APK): '
            'abre Información de la app → menú ⋮ → «Permitir ajustes restringidos», '
            'y vuelve a tocar «Dar permiso y detectar».',
            style: TextStyle(color: AppColors.text2, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.5),
          ),
          if (onAbrirInfo != null) ...[
            const SizedBox(height: 10),
            AppBotonSecundario(texto: 'Abrir información de la app', ambar: true, onPressed: onAbrirInfo),
          ],
        ],
      ),
    );
  }
}
