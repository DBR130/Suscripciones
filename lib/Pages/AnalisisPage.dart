import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Common/AppTheme.dart';
import '../Common/Routers.dart';
import '../models/ahorro.dart';
import '../models/analisis.dart';
import '../models/resumen.dart';
import '../services/api_client.dart';
import '../services/suscripcion_service.dart';
import '../utils/formato.dart';
import '../widgets/app_botones.dart';
import '../widgets/app_card.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_header.dart';
import '../widgets/app_shell.dart';
import '../widgets/campana_avisos.dart';
import '../widgets/estado_vacio.dart';
import '../widgets/logo_servicio.dart';
import '../widgets/movimiento.dart';
import '../widgets/presionable.dart';

/// Colores de las categorías en la dona: azules del logo primero, luego
/// tonos que contrastan sobre el fondo oscuro. "Sin categoría" va en gris.
const List<Color> coloresCategorias = [
  Color(0xFF60A5FA),
  Color(0xFF2563EB),
  Color(0xFFA9CCFF),
  Color(0xFFFBD167),
  Color(0xFF34D399),
  Color(0xFFF472B6),
  Color(0xFFA78BFA),
  Color(0xFFFB923C),
];
const Color colorSinCategoria = Color(0xFF5B6B86);

/// Pestaña Análisis: gasto de los últimos 6 meses, gasto por categoría,
/// cobros de los próximos 30 días, ahorro por cancelaciones, proyección
/// anual y las 3 más caras. Todo sale de GET /api/analisis.
class AnalisisPage extends StatefulWidget {
  const AnalisisPage({super.key, required this.suscripcionService});

  final SuscripcionService suscripcionService;

  @override
  State<AnalisisPage> createState() => _AnalisisPageState();
}

class _AnalisisPageState extends State<AnalisisPage> {
  Analisis? _analisis;
  String? _error;
  String _moneda = 'COP';

  @override
  void initState() {
    super.initState();
    _cargar();
    AppShell.cambios.addListener(_cargar);
  }

  @override
  void dispose() {
    AppShell.cambios.removeListener(_cargar);
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final analisis = await widget.suscripcionService.analisis();
      if (!mounted) return;
      setState(() {
        _analisis = analisis;
        _error = null;
        if (!analisis.monedas.contains(_moneda)) _moneda = analisis.monedas.first;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    }
  }

  Future<void> _abrir(String ruta) async {
    await context.push(ruta);
    if (mounted) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: AppShell.rellenoInferior(context),
          children: [
            AppHeader(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Análisis',
                          style: TextStyle(
                            color: AppColors.text,
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _analisis == null
                              ? ' '
                              : '${_analisis!.cantidadActivas} activas · gasto, cobros y ahorro',
                          style: const TextStyle(
                            color: AppColors.mutedOnGradient,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const CampanaAvisos(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: _cuerpo(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cuerpo() {
    final a = _analisis;
    if (_error != null && a == null) {
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
    if (a == null) return const _EsqueletoAnalisis();
    if (a.vacio) {
      return EstadoVacio(
        titulo: 'Aún no hay nada que analizar',
        texto: 'Cuando agregues suscripciones verás aquí cuánto gastas cada mes, '
            'en qué categorías y qué se cobra pronto.',
        boton: 'Agregar suscripción',
        onPressed: () => _abrir(Routers.nuevaSuscripcion),
      );
    }

    final secciones = <Widget>[
      if (_error != null) BannerError(_error!),
      _Proyeccion(totales: a.totales),
      if (a.masCaras.isNotEmpty)
        _MasCaras(caras: a.masCaras, onAbrir: (id) => _abrir(Routers.detalle(id))),
      if (a.monedas.length > 1)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppEtiqueta('Gráficas en'),
            const SizedBox(height: 8),
            AppPills<String>(
              opciones: [for (final m in a.monedas) (m, m)],
              seleccion: _moneda,
              onChanged: (m) => setState(() => _moneda = m),
            ),
          ],
        ),
      _GastoSeisMeses(
        serie: a.gastoMensual.firstWhere(
          (s) => s.moneda == _moneda,
          orElse: () => EvolucionMoneda(moneda: _moneda, meses: const []),
        ),
        proximo: a.proximosCobros.where((c) => c.moneda == _moneda).firstOrNull,
      ),
      _GastoPorCategoria(
        moneda: _moneda,
        categorias: a.porCategoria.where((c) => c.moneda == _moneda && c.gastoMensual > 0).toList(),
      ),
      _ProximosCobros(cobros: a.proximosCobros, onAbrir: (id) => _abrir(Routers.detalle(id))),
      _AhorroCancelaciones(totales: a.ahorroTotales, canceladas: a.canceladas),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, s) in secciones.indexed) ...[
          if (i > 0) const SizedBox(height: 16),
          AparicionEscalonada(indice: i, child: s),
        ],
      ],
    );
  }
}

/// Título de cada tarjeta con una nota opcional a la derecha.
class _Titulo extends StatelessWidget {
  const _Titulo(this.texto, {this.nota});

  final String texto;
  final String? nota;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(color: AppColors.text, fontSize: 14.5, fontWeight: FontWeight.w800),
            ),
          ),
          if (nota != null) ...[
            const SizedBox(width: 8),
            // La nota es corta: el título se lleva el resto del ancho.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: Text(
                nota!,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

const TextStyle _cifras = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

/// Tarjeta de la proyección anual (y el gasto mensual), por moneda.
class _Proyeccion extends StatelessWidget {
  const _Proyeccion({required this.totales});

  final List<TotalMoneda> totales;

  @override
  Widget build(BuildContext context) {
    final principal = totales.isEmpty ? null : totales.first;
    final moneda = principal?.moneda ?? 'COP';
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppEtiqueta('Proyección anual'),
          const SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: NumeroAnimado(
              valor: principal?.proyeccionAnual ?? 0,
              formato: (v) => Formato.moneda(v, moneda),
              style: _cifras.copyWith(
                color: AppColors.text,
                fontSize: 30,
                height: 1.1,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.7,
              ),
            ),
          ),
          for (final t in totales.skip(1))
            Text(
              '+ ${Formato.moneda(t.proyeccionAnual, t.moneda)} al año',
              style: _cifras.copyWith(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w700),
            ),
          const SizedBox(height: 4),
          Text(
            totales.isEmpty
                ? 'Sin suscripciones activas'
                : 'Si nada cambia · ${totales.map((t) => '${Formato.moneda(t.gastoMensual, t.moneda)}/mes').join(' + ')}',
            style: const TextStyle(color: AppColors.muted, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Las 3 suscripciones más caras, con una barra relativa a la primera.
class _MasCaras extends StatelessWidget {
  const _MasCaras({required this.caras, required this.onAbrir});

  final List<SuscripcionCara> caras;
  final ValueChanged<int> onAbrir;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Titulo('Las más caras', nota: 'Gasto al mes'),
          for (final (i, s) in caras.indexed) ...[
            if (i > 0) const SizedBox(height: 12),
            Presionable(
              onTap: () => onAbrir(s.id),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w800),
                    ),
                  ),
                  LogoServicio(s.nombreServicio, size: 36),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                s.nombreServicio,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.text,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              Formato.moneda(s.gastoMensual, s.moneda),
                              style: _cifras.copyWith(
                                color: AppColors.text,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _BarraRelativa(
                          valor: caras.first.moneda == s.moneda && caras.first.gastoMensual > 0
                              ? s.gastoMensual / caras.first.gastoMensual
                              : 1,
                          color: i == 0 ? AppColors.accent : AppColors.primary,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Barra horizontal que crece hasta [valor] (0 a 1).
class _BarraRelativa extends StatelessWidget {
  const _BarraRelativa({required this.valor, required this.color});

  final double valor;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: Container(
        height: 5,
        color: AppColors.bg,
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: valor.clamp(0, 1)),
          duration: animacionesReducidas(context) ? Duration.zero : const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => FractionallySizedBox(
            widthFactor: v,
            child: Container(color: color),
          ),
        ),
      ),
    );
  }
}

/// Barras del gasto pagado en los últimos 6 meses; el mes actual resaltado.
class _GastoSeisMeses extends StatefulWidget {
  const _GastoSeisMeses({required this.serie, this.proximo});

  final EvolucionMoneda serie;

  /// Próximo cobro en la moneda de la gráfica (para el mes actual sin cobros).
  final CobroProximo? proximo;

  @override
  State<_GastoSeisMeses> createState() => _GastoSeisMesesState();
}

class _GastoSeisMesesState extends State<_GastoSeisMeses> {
  int? _tocado;

  static const _meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

  @override
  Widget build(BuildContext context) {
    final serie = widget.serie;
    final meses = serie.meses;
    final moneda = serie.moneda;
    final maximo = meses.fold<double>(0, (m, g) => math.max(m, g.total));
    final actual = meses.isEmpty ? null : meses.last;
    final elegido = _tocado == null || _tocado! >= meses.length ? actual : meses[_tocado!];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Titulo('Gasto de los últimos 6 meses', nota: moneda),
          if (!serie.tieneDatos)
            const _SinDatos('Aún no hay pagos registrados en estos meses. Aparecen al pasar cada fecha de cobro.')
          else ...[
            if (elegido == actual && actual != null && actual.total == 0) ...[
              // Mes actual aún sin cobros: en vez de "$0", cuándo viene el próximo.
              Text(
                'Aún sin cobros en ${Formato.mes(actual.mes)}',
                style: const TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w800),
              ),
              Text(
                widget.proximo == null
                    ? 'No hay cobros en los próximos 30 días'
                    : 'Próximo: ${widget.proximo!.nombreServicio} el ${Formato.fechaLarga(widget.proximo!.fecha)}',
                style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ] else ...[
              Text(
                elegido == null ? '' : Formato.moneda(elegido.total, moneda),
                style: _cifras.copyWith(color: AppColors.text, fontSize: 22, fontWeight: FontWeight.w800),
              ),
              Text(
                elegido == null
                    ? ''
                    : elegido == actual
                        ? 'Pagado este mes'
                        : 'Pagado en ${Formato.mesAnio(elegido.mes)}',
                style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              height: 150,
              child: BarChart(
                BarChartData(
                  maxY: maximo == 0 ? 1 : maximo * 1.15,
                  alignment: BarChartAlignment.spaceAround,
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    horizontalInterval: maximo == 0 ? 1 : maximo * 1.15 / 3,
                    getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.divider, strokeWidth: 1),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    topTitles: const AxisTitles(),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        getTitlesWidget: (valor, meta) {
                          final i = valor.toInt();
                          if (i < 0 || i >= meses.length) return const SizedBox.shrink();
                          return SideTitleWidget(
                            meta: meta,
                            child: Text(
                              _meses[meses[i].mes.month - 1],
                              style: TextStyle(
                                color: i == meses.length - 1 ? AppColors.text : AppColors.muted,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    enabled: true,
                    handleBuiltInTouches: false,
                    touchCallback: (evento, respuesta) {
                      final i = respuesta?.spot?.touchedBarGroupIndex;
                      if (evento.isInterestedForInteractions && i != null && i != _tocado) {
                        setState(() => _tocado = i);
                      }
                    },
                  ),
                  barGroups: [
                    for (final (i, m) in meses.indexed)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: m.total,
                            width: 22,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                            color: i == meses.length - 1
                                ? AppColors.accent
                                : (i == _tocado ? AppColors.flagBlueText : AppColors.primary.withValues(alpha: 0.55)),
                            backDrawRodData: BackgroundBarChartRodData(
                              show: true,
                              toY: maximo == 0 ? 1 : maximo * 1.15,
                              color: AppColors.bg.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                duration: animacionesReducidas(context) ? Duration.zero : const Duration(milliseconds: 450),
                curve: Curves.easeOutCubic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Dona del gasto mensual por categoría con leyenda y porcentajes.
class _GastoPorCategoria extends StatefulWidget {
  const _GastoPorCategoria({required this.moneda, required this.categorias});

  final String moneda;
  final List<TotalCategoria> categorias;

  @override
  State<_GastoPorCategoria> createState() => _GastoPorCategoriaState();
}

class _GastoPorCategoriaState extends State<_GastoPorCategoria> {
  int? _tocada;

  Color _color(int i, TotalCategoria c) =>
      c.categoria == null ? colorSinCategoria : coloresCategorias[i % coloresCategorias.length];

  @override
  Widget build(BuildContext context) {
    final categorias = widget.categorias;
    final total = categorias.fold<double>(0, (t, c) => t + c.gastoMensual);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Titulo('Gasto mensual por categoría', nota: widget.moneda),
          if (categorias.isEmpty || total == 0)
            const _SinDatos('Agrega una categoría a tus suscripciones para ver en qué se va tu dinero.')
          else
            LayoutBuilder(builder: (context, restricciones) {
              // En pantallas angostas la leyenda va debajo de la dona.
              final angosta = restricciones.maxWidth < 330;
              final dona = SizedBox.square(
                dimension: 150,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 46,
                        startDegreeOffset: -90,
                        pieTouchData: PieTouchData(
                          touchCallback: (evento, respuesta) {
                            if (!evento.isInterestedForInteractions) return;
                            final i = respuesta?.touchedSection?.touchedSectionIndex;
                            setState(() => _tocada = (i == null || i < 0) ? null : i);
                          },
                        ),
                        sections: [
                          for (final (i, c) in categorias.indexed)
                            PieChartSectionData(
                              value: c.gastoMensual,
                              color: _color(i, c),
                              radius: i == _tocada ? 26 : 22,
                              showTitle: false,
                            ),
                        ],
                      ),
                      duration: animacionesReducidas(context) ? Duration.zero : const Duration(milliseconds: 300),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 52),
                            child: Text(
                              Formato.moneda(
                                _tocada == null ? total : categorias[_tocada!].gastoMensual,
                                widget.moneda,
                              ),
                              style: _cifras.copyWith(
                                color: AppColors.text,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const Text(
                          'al mes',
                          style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              );
              final leyenda = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, c) in categorias.indexed)
                    _FilaLeyenda(
                      color: _color(i, c),
                      nombre: c.categoria ?? 'Sin categoría',
                      porcentaje: c.gastoMensual / total * 100,
                      monto: Formato.moneda(c.gastoMensual, c.moneda),
                      resaltada: i == _tocada,
                    ),
                ],
              );
              if (angosta) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [Center(child: dona), const SizedBox(height: 14), leyenda],
                );
              }
              return Row(
                children: [dona, const SizedBox(width: 16), Expanded(child: leyenda)],
              );
            }),
        ],
      ),
    );
  }
}

class _FilaLeyenda extends StatelessWidget {
  const _FilaLeyenda({
    required this.color,
    required this.nombre,
    required this.porcentaje,
    required this.monto,
    required this.resaltada,
  });

  final Color color;
  final String nombre;
  final double porcentaje;
  final String monto;
  final bool resaltada;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: resaltada ? AppColors.text : AppColors.textSoft,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  monto,
                  style: _cifras.copyWith(color: AppColors.muted, fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Text(
            '${porcentaje.round()} %',
            style: _cifras.copyWith(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

/// Línea de tiempo con los cobros de los próximos 30 días.
class _ProximosCobros extends StatelessWidget {
  const _ProximosCobros({required this.cobros, required this.onAbrir});

  final List<CobroProximo> cobros;
  final ValueChanged<int> onAbrir;

  String _cuando(CobroProximo c) => switch (c.diasRestantes) {
        0 => 'Hoy',
        1 => 'Mañana',
        _ => Formato.fechaCorta(c.fecha),
      };

  @override
  Widget build(BuildContext context) {
    final porMoneda = <String, double>{};
    for (final c in cobros) {
      porMoneda[c.moneda] = (porMoneda[c.moneda] ?? 0) + c.monto;
    }
    final total = porMoneda.entries.map((e) => Formato.moneda(e.value, e.key)).join(' + ');
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Titulo('Próximos 30 días', nota: cobros.isEmpty ? null : total),
          if (cobros.isEmpty)
            const _SinDatos('No hay cobros en los próximos 30 días.')
          else
            for (final (i, c) in cobros.indexed)
              _PasoLinea(
                primero: i == 0,
                ultimo: i == cobros.length - 1,
                resaltado: c.diasRestantes <= 3,
                child: Presionable(
                  onTap: () => onAbrir(c.suscripcionId),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 58,
                          child: Text(
                            _cuando(c),
                            style: TextStyle(
                              color: c.diasRestantes <= 3 ? AppColors.text : AppColors.muted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        LogoServicio(c.nombreServicio, size: 30),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.nombreServicio,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.text,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (c.finDePrueba)
                                const Text(
                                  'Termina la prueba gratis',
                                  style: TextStyle(color: AppColors.amber, fontSize: 11.5, fontWeight: FontWeight.w700),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          Formato.moneda(c.monto, c.moneda),
                          style: _cifras.copyWith(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// Un paso de la línea de tiempo: el punto y el tramo de línea a la izquierda.
class _PasoLinea extends StatelessWidget {
  const _PasoLinea({
    required this.primero,
    required this.ultimo,
    required this.resaltado,
    required this.child,
  });

  final bool primero;
  final bool ultimo;
  final bool resaltado;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 18,
            child: Column(
              children: [
                Expanded(child: Container(width: 2, color: primero ? Colors.transparent : AppColors.line)),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: resaltado ? AppColors.accent : AppColors.bg,
                    shape: BoxShape.circle,
                    border: Border.all(color: resaltado ? AppColors.accent : AppColors.lineStrong, width: 2),
                  ),
                ),
                Expanded(child: Container(width: 2, color: ultimo ? Colors.transparent : AppColors.line)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Ahorro por cancelaciones: total anual y lista de canceladas (antes en
/// Perfil › Historial y ahorro).
class _AhorroCancelaciones extends StatelessWidget {
  const _AhorroCancelaciones({required this.totales, required this.canceladas});

  final List<TotalAhorro> totales;
  final List<Cancelada> canceladas;

  @override
  Widget build(BuildContext context) {
    final principal = totales.isEmpty ? null : totales.first;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Titulo(
            'Ahorro por cancelaciones',
            nota: canceladas.isEmpty ? null : '${canceladas.length} ${canceladas.length == 1 ? 'cancelada' : 'canceladas'}',
          ),
          if (canceladas.isEmpty)
            const _SinDatos('Cuando canceles una suscripción, aquí verás cuánto te ahorras al año.')
          else ...[
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: NumeroAnimado(
                valor: principal!.anual,
                formato: (v) => '+${Formato.moneda(v, principal.moneda)}',
                style: _cifras.copyWith(color: AppColors.link, fontSize: 26, fontWeight: FontWeight.w800),
              ),
            ),
            for (final t in totales.skip(1))
              Text(
                '+${Formato.moneda(t.anual, t.moneda)}',
                style: _cifras.copyWith(color: AppColors.link, fontSize: 15, fontWeight: FontWeight.w800),
              ),
            const Text(
              'al año, si no vuelves a suscribirte',
              style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (final c in canceladas)
              FilaDato(
                '${c.nombreServicio} · ${Formato.fechaCorta(c.fecha)}',
                '+${Formato.moneda(c.ahorroAnual, c.moneda)}/año',
                ultima: c == canceladas.last,
              ),
          ],
        ],
      ),
    );
  }
}

class _SinDatos extends StatelessWidget {
  const _SinDatos(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        texto,
        style: const TextStyle(color: AppColors.muted, fontSize: 12.5, fontWeight: FontWeight.w500, height: 1.45),
      ),
    );
  }
}

/// Esqueleto mientras carga: tarjetas con la forma de la pantalla.
class _EsqueletoAnalisis extends StatelessWidget {
  const _EsqueletoAnalisis();

  @override
  Widget build(BuildContext context) {
    Widget tarjeta(List<Widget> hijos) => Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: hijos),
        );
    return Esqueleto(
      child: Column(
        children: [
          tarjeta(const [
            CajaEsqueleto(alto: 11, ancho: 110),
            SizedBox(height: 10),
            CajaEsqueleto(alto: 28, ancho: 190),
            SizedBox(height: 8),
            CajaEsqueleto(alto: 11, ancho: 150),
          ]),
          tarjeta([
            const CajaEsqueleto(alto: 14, ancho: 170),
            const SizedBox(height: 18),
            SizedBox(
              height: 130,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (final alto in const [60.0, 90.0, 75.0, 110.0, 85.0, 120.0])
                    CajaEsqueleto(alto: alto, ancho: 22, radio: 7),
                ],
              ),
            ),
          ]),
          tarjeta(const [
            CajaEsqueleto(alto: 14, ancho: 190),
            SizedBox(height: 16),
            Row(
              children: [
                CajaEsqueleto(alto: 120, ancho: 120, radio: 60),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: [
                      CajaEsqueleto(alto: 12),
                      SizedBox(height: 12),
                      CajaEsqueleto(alto: 12),
                      SizedBox(height: 12),
                      CajaEsqueleto(alto: 12),
                    ],
                  ),
                ),
              ],
            ),
          ]),
        ],
      ),
    );
  }
}
