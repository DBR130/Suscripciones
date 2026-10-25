import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Common/AppTheme.dart';
import '../Common/Routers.dart';
import '../models/resumen.dart';
import '../models/suscripcion.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/suscripcion_service.dart';
import '../utils/formato.dart';
import '../widgets/app_botones.dart';
import '../widgets/app_card.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_header.dart';
import '../widgets/estado_vacio.dart';
import '../widgets/suscripcion_card.dart';

/// Dashboard (pantalla 07 del diseño): gasto del mes, próximos 7 días, el
/// resto ordenado por fecha y el gasto por categoría.
class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.authService,
    required this.suscripcionService,
  });

  final AuthService authService;
  final SuscripcionService suscripcionService;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  static const int _ventanaDias = 7;

  Resumen? _resumen;
  List<Suscripcion>? _suscripciones;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final resultados = await Future.wait([
        widget.suscripcionService.resumen(),
        widget.suscripcionService.listar(estados: const [
          EstadoSuscripcion.activa,
          EstadoSuscripcion.marcadaParaCancelar,
        ]),
      ]);
      if (!mounted) return;
      setState(() {
        _resumen = resultados[0] as Resumen;
        _suscripciones = resultados[1] as List<Suscripcion>;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    }
  }

  /// Abre otra pantalla y al volver recarga, por si algo cambió.
  Future<void> _abrir(String ruta) async {
    await context.push(ruta);
    if (mounted) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final hoy = DateUtils.dateOnly(DateTime.now());
    final suscripciones = [...?_suscripciones]
      ..sort((a, b) => a.fechaClave.compareTo(b.fechaClave));
    final pronto = suscripciones.where((s) => s.diasHasta(hoy) <= _ventanaDias).toList();
    final despues = suscripciones.where((s) => s.diasHasta(hoy) > _ventanaDias).toList();
    final diasGlobales = _resumen?.diasAnticipacion ?? 3;

    Widget tarjeta(Suscripcion s) => Padding(
          padding: const EdgeInsets.only(bottom: 11),
          child: SuscripcionCard(
            suscripcion: s,
            hoy: hoy,
            diasGlobales: diasGlobales,
            onVerDetalle: () => _abrir(Routers.detalle(s.id!)),
          ),
        );

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          // Permite "jalar para recargar" aunque la lista sea corta.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            _Encabezado(
              resumen: _resumen,
              iniciales: widget.authService.usuario?.iniciales,
              proximo: suscripciones.isEmpty ? null : suscripciones.first.fechaClave,
              onPerfil: () => context.go(Routers.perfil),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
              child: _cuerpo(pronto, despues, tarjeta, diasGlobales),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cuerpo(
    List<Suscripcion> pronto,
    List<Suscripcion> despues,
    Widget Function(Suscripcion) tarjeta,
    int diasGlobales,
  ) {
    if (_error != null && _suscripciones == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BannerError(_error!),
          const SizedBox(height: 12),
          AppBotonSecundario(
            texto: 'Reintentar',
            onPressed: () {
              setState(() => _error = null);
              _cargar();
            },
          ),
        ],
      );
    }
    if (_suscripciones == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_suscripciones!.isEmpty) {
      return EstadoVacio(
        titulo: 'Aún no tienes suscripciones',
        texto: 'Agrega la primera con su monto y la fecha del próximo cobro. '
            'Te avisaremos $diasGlobales días antes.',
        boton: 'Agregar suscripción',
        onPressed: () => _abrir(Routers.nuevaSuscripcion),
      );
    }

    final categorias = _resumen?.porCategoria ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[BannerError(_error!), const SizedBox(height: 14)],
        if (pronto.isNotEmpty) ...[
          _TituloSeccion(
            titulo: 'Próximos 7 días',
            cantidad: pronto.length,
            nota: _porCobrar(pronto),
          ),
          ...pronto.map(tarjeta),
          const SizedBox(height: 11),
        ],
        if (despues.isNotEmpty) ...[
          _TituloSeccion(
            titulo: 'Más adelante',
            cantidad: despues.length,
            nota: 'Ordenadas por cobro',
          ),
          ...despues.map(tarjeta),
          const SizedBox(height: 11),
        ],
        if (categorias.any((c) => c.categoria != null)) ...[
          _GastoPorCategoria(categorias),
          const SizedBox(height: 22),
        ],
        AppBotonPunteado(
          texto: '+ Agregar suscripción manualmente',
          onPressed: () => _abrir(Routers.nuevaSuscripcion),
        ),
      ],
    );
  }

  /// "$65.800 por cobrar" (las pruebas gratis no suman).
  String _porCobrar(List<Suscripcion> lista) {
    final porMoneda = <String, double>{};
    for (final s in lista.where((s) => !s.esPruebaGratis)) {
      porMoneda[s.moneda] = (porMoneda[s.moneda] ?? 0) + s.monto;
    }
    if (porMoneda.isEmpty) return '';
    final textos = porMoneda.entries.map((e) => Formato.moneda(e.value, e.key));
    return '${textos.join(' + ')} por cobrar';
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado({
    required this.resumen,
    required this.iniciales,
    required this.proximo,
    required this.onPerfil,
  });

  final Resumen? resumen;
  final String? iniciales;

  /// Fecha de la primera tarjeta (cobro o fin de prueba).
  final DateTime? proximo;
  final VoidCallback onPerfil;

  @override
  Widget build(BuildContext context) {
    final totales = resumen?.totales ?? const [];
    // La primera es COP si existe (el backend la ordena primero).
    final principal = totales.isEmpty ? null : totales.first;
    final otras = totales.skip(1);
    final pruebas = resumen?.pruebasPorTerminar ?? const [];
    final activas = resumen?.cantidadActivas ?? 0;
    final proyeccion = totales.isEmpty
        ? Formato.moneda(0, 'COP')
        : totales.map((t) => Formato.moneda(t.proyeccionAnual, t.moneda)).join(' + ');

    return AppHeader(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _MarcaPequena(),
              const Spacer(),
              Semantics(
                button: true,
                label: 'Perfil',
                child: InkWell(
                  onTap: onPerfil,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.avatar,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.lineStrong),
                    ),
                    child: iniciales == null || iniciales!.isEmpty
                        ? const Icon(Icons.person_outline, size: 18, color: Color(0xFFCFE0FF))
                        : Text(
                            iniciales!,
                            style: const TextStyle(
                              color: Color(0xFFCFE0FF),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Glass(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppEtiqueta('Gasto en suscripciones · mes', color: AppColors.mutedOnGradient),
                const SizedBox(height: 7),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    Formato.moneda(principal?.gastoMensual ?? 0, principal?.moneda ?? 'COP'),
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 38,
                      height: 1.05,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.95,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                for (final t in otras)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '+ ${Formato.moneda(t.gastoMensual, t.moneda)} al mes',
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const SizedBox(height: 3),
                Text(
                  '$activas ${activas == 1 ? 'activa' : 'activas'} · proyección anual $proyeccion',
                  style: const TextStyle(
                    color: AppColors.mutedOnGradient,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (activas > 0 && proximo != null) ...[
                  const SizedBox(height: 13),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      if (pruebas.isNotEmpty) _ChipPrueba(pruebas: pruebas),
                      _Chip(texto: 'Próximo cobro: ${Formato.fechaCorta(proximo!)}'),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta translúcida con desenfoque ("glass") del diseño.
class _Glass extends StatelessWidget {
  const _Glass({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radio = BorderRadius.circular(22);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radio,
        boxShadow: const [
          BoxShadow(color: Color(0x29000000), blurRadius: 26, offset: Offset(0, 12)),
        ],
      ),
      child: ClipRRect(
        borderRadius: radio,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: radio,
              border: Border.all(color: Colors.white.withValues(alpha: 0.36)),
              // Brillo interior en el borde superior.
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: const Alignment(0, -0.85),
                colors: [Colors.white.withValues(alpha: 0.12), Colors.transparent],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _MarcaPequena extends StatelessWidget {
  const _MarcaPequena();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Text(
            'S',
            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(width: 9),
        const Text(
          'SubTrack',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 16.5,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.chip,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.lineStrong),
      ),
      child: Text(
        texto,
        style: const TextStyle(color: AppColors.textSoft, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// "1 prueba gratis termina en 2 días" en ámbar.
class _ChipPrueba extends StatelessWidget {
  const _ChipPrueba({required this.pruebas});

  final List<Suscripcion> pruebas;

  @override
  Widget build(BuildContext context) {
    final hoy = DateUtils.dateOnly(DateTime.now());
    final String texto;
    if (pruebas.length == 1) {
      final dias = pruebas.first.diasHasta(hoy);
      texto = '1 prueba gratis termina ${switch (dias) {
        0 => 'hoy',
        1 => 'en 1 día',
        _ => 'en $dias días',
      }}';
    } else {
      texto = '${pruebas.length} pruebas gratis terminan esta semana';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x24FBBF24), // rgba(251,191,36,.14)
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x6BFBBF24)), // rgba(251,191,36,.42)
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline, size: 13, color: AppColors.amberStrong),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              texto,
              style: const TextStyle(
                color: AppColors.amberStrong,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TituloSeccion extends StatelessWidget {
  const _TituloSeccion({required this.titulo, required this.cantidad, required this.nota});

  final String titulo;
  final int cantidad;
  final String nota;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 11),
      child: Row(
        children: [
          Text(
            titulo,
            style: const TextStyle(color: AppColors.text, fontSize: 14.5, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$cantidad',
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              nota,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Gasto mensual por categoría (GET /api/resumen → por_categoria), con una
/// barra proporcional al mayor gasto de la misma moneda.
class _GastoPorCategoria extends StatelessWidget {
  const _GastoPorCategoria(this.categorias);

  final List<TotalCategoria> categorias;

  @override
  Widget build(BuildContext context) {
    final maximo = <String, double>{};
    for (final c in categorias) {
      if (c.gastoMensual > (maximo[c.moneda] ?? 0)) maximo[c.moneda] = c.gastoMensual;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(2, 0, 2, 9),
          child: Text(
            'Gasto por categoría',
            style: TextStyle(color: AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w800),
          ),
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(
            children: [
              for (final (i, c) in categorias.indexed)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    border: i == categorias.length - 1
                        ? null
                        : const Border(bottom: BorderSide(color: AppColors.divider)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${c.categoria ?? 'Sin categoría'} · ${c.cantidad}',
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            '${Formato.moneda(c.gastoMensual, c.moneda)}/mes',
                            style: const TextStyle(
                              color: AppColors.text,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: (maximo[c.moneda] ?? 0) == 0 ? 0 : c.gastoMensual / maximo[c.moneda]!,
                          minHeight: 5,
                          backgroundColor: AppColors.bg,
                          color: c.categoria == null ? AppColors.lineStrong : AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
