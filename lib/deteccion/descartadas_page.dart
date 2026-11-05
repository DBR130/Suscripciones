import 'package:flutter/material.dart';

import '../Common/AppTheme.dart';
import '../services/api_client.dart';
import '../utils/formato.dart';
import '../widgets/app_botones.dart';
import '../widgets/app_card.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_header.dart';
import '../widgets/estado_vacio.dart';
import '../widgets/logo_servicio.dart';
import 'candidato_suscripcion.dart';
import 'deteccion_service.dart';

/// "Detecciones descartadas" (Perfil): los comercios que el usuario marcó
/// "No es mía". "Volver a proponer" los deja pendientes otra vez y aparecen
/// en la pantalla 05 (POST /api/detecciones/candidatos/:id/restaurar).
class DescartadasPage extends StatefulWidget {
  const DescartadasPage({super.key, required this.servicio});

  final DeteccionService servicio;

  @override
  State<DescartadasPage> createState() => _DescartadasPageState();
}

class _DescartadasPageState extends State<DescartadasPage> {
  List<CandidatoSuscripcion>? _lista;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final lista = await widget.servicio.descartadas();
      if (mounted) setState(() => _lista = lista);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    }
  }

  Future<void> _restaurar(CandidatoSuscripcion c) async {
    try {
      await widget.servicio.restaurar(c.id);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
      return;
    }
    if (!mounted) return;
    setState(() => _lista = [...?_lista]..remove(c));
    mostrarToast(context, 'Volveremos a proponer ${c.titulo}');
  }

  @override
  Widget build(BuildContext context) {
    final lista = _lista;
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
                  'Detecciones descartadas',
                  style: TextStyle(color: AppColors.text, fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -0.6),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Comercios que marcaste como «No es mía». No te los volvemos a proponer, salvo que lo pidas.',
                  style: TextStyle(color: AppColors.mutedHero, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Expanded(
            child: lista == null
                ? (_error == null
                    ? const Center(child: CircularProgressIndicator())
                    : Padding(padding: const EdgeInsets.all(16), child: BannerError(_error!)))
                : lista.isEmpty
                    ? ListView(children: const [
                        EstadoVacio(titulo: 'No hay detecciones descartadas', texto: 'Aquí aparecen las que marques como «No es mía».'),
                      ])
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (_error != null) ...[BannerError(_error!), const SizedBox(height: 12)],
                          for (final c in lista) ...[
                            _FilaDescartada(candidato: c, onRestaurar: () => _restaurar(c)),
                            const SizedBox(height: 10),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

class _FilaDescartada extends StatelessWidget {
  const _FilaDescartada({required this.candidato, required this.onRestaurar});

  final CandidatoSuscripcion candidato;
  final VoidCallback onRestaurar;

  @override
  Widget build(BuildContext context) {
    final c = candidato;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              LogoServicio(c.nombre, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.titulo, style: const TextStyle(color: AppColors.text, fontSize: 14.5, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      '${Formato.moneda(c.monto, c.moneda)} · ${c.frecuencia.etiqueta}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AppBotonSecundario(texto: 'Volver a proponer', onPressed: onRestaurar),
        ],
      ),
    );
  }
}
