import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../Common/AppTheme.dart';
import '../widgets/app_botones.dart';
import '../widgets/app_card.dart';
import '../widgets/app_header.dart';
import 'aviso_segundo_plano.dart';

/// Guía "Mantén SubTrack activa en segundo plano" (encargo C). Pantalla
/// aparte: no es un paso del onboarding. Se llega desde el aviso de Inicio
/// (aviso_segundo_plano.dart) o desde Perfil. Ver docs/deteccion.md,
/// "Fabricantes que cierran apps".

/// Estado que informa la parte nativa (MainActivity, canal subtrack/sistema).
class InfoSegundoPlano {
  const InfoSegundoPlano({required this.fabricante, required this.grupo, required this.bateriaSinRestricciones});

  static const noDisponible = InfoSegundoPlano(fabricante: '', grupo: 'otra', bateriaSinRestricciones: false);

  /// Build.MANUFACTURER tal cual.
  final String fabricante;

  /// "xiaomi", "samsung", "oppo", "vivo", "huawei" u "otra"
  /// (FabricanteSegundoPlano.kt).
  final String grupo;

  /// PowerManager.isIgnoringBatteryOptimizations.
  final bool bateriaSinRestricciones;

  factory InfoSegundoPlano.fromMap(Map<Object?, Object?> m) => InfoSegundoPlano(
        fabricante: m['fabricante'] as String? ?? '',
        grupo: m['grupo'] as String? ?? 'otra',
        bateriaSinRestricciones: m['bateria_sin_restricciones'] == true,
      );
}

/// Puente con el canal "subtrack/sistema". Fuera de Android no hace nada.
class SistemaSegundoPlano {
  SistemaSegundoPlano({bool? disponible})
      : disponible = disponible ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  static const _canal = MethodChannel('subtrack/sistema');
  final bool disponible;

  Future<InfoSegundoPlano> info() async {
    if (!disponible) return InfoSegundoPlano.noDisponible;
    try {
      final m = await _canal.invokeMapMethod<Object?, Object?>('segundoPlano');
      return m == null ? InfoSegundoPlano.noDisponible : InfoSegundoPlano.fromMap(m);
    } on PlatformException catch (e) {
      debugPrint('No se pudo leer el estado de segundo plano: $e');
      return InfoSegundoPlano.noDisponible;
    } on MissingPluginException {
      return InfoSegundoPlano.noDisponible; // sin la parte nativa (tests)
    }
  }

  /// Pantalla de la marca (inicio automático); si no existe, los ajustes de la app.
  Future<void> abrirSegundoPlano() => _invocar('abrirSegundoPlano');

  /// Lista de optimización de batería; si no existe, los ajustes de la app.
  Future<void> abrirBateria() => _invocar('abrirBateria');

  Future<void> _invocar(String metodo) async {
    if (!disponible) return;
    try {
      await _canal.invokeMethod<bool>(metodo);
    } on PlatformException catch (e) {
      debugPrint('No se pudo abrir $metodo: $e');
    } on MissingPluginException {
      // Sin la parte nativa (tests).
    }
  }
}

/// Qué interruptor buscar en cada marca. [ajuste] es null en "otra": allí la
/// guía solo muestra la batería.
typedef InstruccionesSegundoPlano = ({String? ajuste, List<String> pasos, String bateria});

const _bateriaGeneral = 'Quita a SubTrack de la optimización de batería: búscala en la lista y elige "No optimizar" '
    'o "Sin restricciones".';

InstruccionesSegundoPlano instruccionesSegundoPlano(String grupo) => switch (grupo) {
      // Textos que ya se probaron en el Xiaomi (antes en GuiaXiaomi).
      'xiaomi' => (
          ajuste: 'Inicio automático',
          pasos: const [
            'Inicio automático: actívalo para SubTrack.',
            'En HyperOS puede llamarse "Autoencendido en segundo plano".',
          ],
          bateria: 'En los ajustes de la app, entra a "Ahorro de batería" y elige "Sin restricciones".',
        ),
      'samsung' => (
          ajuste: 'Batería de la app',
          pasos: const [
            'En Batería, elige "Sin restricciones" para SubTrack.',
            'Si aparece en "Apps en suspensión" o "Apps en suspensión profunda", quítala de ahí.',
          ],
          bateria: _bateriaGeneral,
        ),
      'oppo' => (
          ajuste: 'Inicio automático',
          pasos: const ['Activa "Inicio automático" o "Permitir actividad en segundo plano" para SubTrack.'],
          bateria: _bateriaGeneral,
        ),
      'vivo' => (
          ajuste: 'Inicio automático',
          pasos: const ['Activa "Inicio automático" o "Alto consumo en segundo plano" para SubTrack.'],
          bateria: _bateriaGeneral,
        ),
      'huawei' => (
          ajuste: 'Inicio de apps',
          pasos: const [
            'En "Inicio de apps", desactiva "Gestionar automáticamente" para SubTrack.',
            'Deja activado "Ejecutar en segundo plano".',
          ],
          bateria: _bateriaGeneral,
        ),
      _ => (ajuste: null, pasos: const <String>[], bateria: _bateriaGeneral),
    };

/// Texto del aviso de Inicio (encargo C, punto 5).
const textoAvisoSegundoPlano = 'Tu celular cerró SubTrack y algunos cobros se revisaron tarde. '
    'Activa el segundo plano para que te avisemos al instante.';

class GuiaSegundoPlanoPage extends StatefulWidget {
  GuiaSegundoPlanoPage({
    super.key,
    SistemaSegundoPlano? sistema,
    RegistroSegundoPlano? registro,
    DateTime Function()? ahora,
  })  : sistema = sistema ?? SistemaSegundoPlano(),
        registro = registro ?? RegistroSegundoPlano(),
        ahora = ahora ?? DateTime.now;

  final SistemaSegundoPlano sistema;
  final RegistroSegundoPlano registro;
  final DateTime Function() ahora;

  static const titulo = 'Mantén SubTrack activa en segundo plano';

  @override
  State<GuiaSegundoPlanoPage> createState() => _GuiaSegundoPlanoPageState();
}

class _GuiaSegundoPlanoPageState extends State<GuiaSegundoPlanoPage> with WidgetsBindingObserver {
  InfoSegundoPlano? _info;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cargar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Al volver de los ajustes, la batería pudo cambiar.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _cargar();
  }

  Future<void> _cargar() async {
    final info = await widget.sistema.info();
    if (mounted) setState(() => _info = info);
  }

  Future<void> _yaLoActive() async {
    await widget.registro.marcarGuiaVista(widget.ahora());
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final i = instruccionesSegundoPlano(info?.grupo ?? 'otra');
    const estiloPaso = TextStyle(color: AppColors.text2, fontSize: 13, fontWeight: FontWeight.w600, height: 1.45);
    const estiloTitulo = TextStyle(color: AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w700);
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppHeader(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (Navigator.of(context).canPop()) ...[
                  AppBotonVolver(onPressed: () => Navigator.of(context).pop()),
                  const SizedBox(height: 14),
                ],
                const Text(
                  GuiaSegundoPlanoPage.titulo,
                  style: TextStyle(color: AppColors.text, fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -0.6),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Algunos celulares cierran las apps para ahorrar batería. Con estos ajustes te avisamos '
                  'en el momento del cobro, aunque la app esté cerrada.',
                  style: TextStyle(color: AppColors.mutedHero, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Expanded(
            child: info == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (i.ajuste != null) ...[
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(i.ajuste!, style: estiloTitulo),
                              const SizedBox(height: 10),
                              for (final paso in i.pasos) ...[
                                Text(paso, style: estiloPaso),
                                const SizedBox(height: 6),
                              ],
                              const SizedBox(height: 6),
                              AppBotonSecundario(texto: 'Abrir ajustes', onPressed: widget.sistema.abrirSegundoPlano),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Expanded(child: Text('Batería sin restricciones', style: estiloTitulo)),
                                Text(
                                  info.bateriaSinRestricciones ? 'Activo' : 'Pendiente',
                                  style: TextStyle(
                                    color: info.bateriaSinRestricciones ? AppColors.accent : AppColors.amber,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(i.bateria, style: estiloPaso),
                            const SizedBox(height: 12),
                            AppBotonSecundario(texto: 'Abrir ajustes de batería', onPressed: widget.sistema.abrirBateria),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      FilledButton(onPressed: _yaLoActive, child: const Text('Ya lo activé')),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Aviso de Inicio cuando el celular cerró SubTrack y hubo cobros revisados
/// tarde. Informativo (azul): la detección funciona, pero llegó tarde.
class AvisoSegundoPlano extends StatelessWidget {
  const AvisoSegundoPlano({super.key, required this.onComoActivar, required this.onCerrar});

  final VoidCallback onComoActivar;
  final VoidCallback onCerrar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 14),
      decoration: BoxDecoration(
        color: AppColors.flagBlueBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.lineStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Icon(Icons.schedule, color: AppColors.accent, size: 20),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    textoAvisoSegundoPlano,
                    style: TextStyle(color: AppColors.flagBlueText, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.5),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Cerrar aviso',
                onPressed: onCerrar,
                icon: const Icon(Icons.close, color: AppColors.muted, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AppBotonSecundario(texto: 'Cómo activarlo', onPressed: onComoActivar),
          ),
        ],
      ),
    );
  }
}
