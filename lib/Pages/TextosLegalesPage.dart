import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Common/AppTheme.dart';
import '../services/version_app.dart';
import '../textos/textos_legales.dart';
import '../widgets/app_card.dart';
import '../widgets/app_header.dart';
import '../widgets/app_marca.dart';

/// Pantalla de solo texto (Política de privacidad, Términos de uso, Qué datos
/// guardamos). Los textos viven en lib/textos/textos_legales.dart.
class TextoLegalPage extends StatelessWidget {
  const TextoLegalPage({super.key, required this.titulo, this.aviso, required this.secciones});

  final String titulo;

  /// Línea bajo el título ("Borrador – última actualización: …").
  final String? aviso;
  final List<SeccionTexto> secciones;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _Encabezado(titulo: titulo, subtitulo: aviso),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final s in secciones) ...[
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.titulo,
                          style: const TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w800),
                        ),
                        for (final p in s.parrafos) ...[
                          const SizedBox(height: 8),
                          _Parrafo(p),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 11),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Acerca de SubTrack": logo, nombre, versión del paquete, equipo y crédito.
class AcercaDePage extends StatelessWidget {
  const AcercaDePage({super.key, this.version = versionApp});

  final Future<String?> Function() version;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          const _Encabezado(titulo: tituloAcercaDe),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: AppMarca(altura: 72)),
                const SizedBox(height: 14),
                const Text(
                  'SubTrack',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.text, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                ),
                const SizedBox(height: 4),
                FutureBuilder<String?>(
                  future: version(),
                  builder: (context, snap) => Text(
                    snap.data ?? '',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.muted, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 18),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Parrafo(descripcionApp),
                      const SizedBox(height: 14),
                      const AppEtiqueta('Equipo'),
                      const SizedBox(height: 8),
                      for (final persona in equipo)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            persona,
                            style: const TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  creditoAcademico,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.titulo, this.subtitulo});

  final String titulo;
  final String? subtitulo;

  @override
  Widget build(BuildContext context) {
    return AppHeader(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppBotonVolver(
            onPressed: () => context.canPop() ? context.pop() : Navigator.of(context).maybePop(),
          ),
          const SizedBox(height: 14),
          Text(
            titulo,
            style: const TextStyle(color: AppColors.text, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.5),
          ),
          if (subtitulo != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitulo!,
              style: const TextStyle(color: AppColors.mutedHero, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}

class _Parrafo extends StatelessWidget {
  const _Parrafo(this.texto);

  final String texto;

  static const _estilo = TextStyle(color: AppColors.text2, fontSize: 13.5, fontWeight: FontWeight.w500, height: 1.5);

  @override
  Widget build(BuildContext context) {
    if (!texto.startsWith('• ')) return Text(texto, style: _estilo);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('•  ', style: _estilo),
        Expanded(child: Text(texto.substring(2), style: _estilo)),
      ],
    );
  }
}
