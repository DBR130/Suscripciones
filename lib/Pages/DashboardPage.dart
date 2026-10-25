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
import '../widgets/app_card.dart';
import '../widgets/app_header.dart';
import '../widgets/suscripcion_card.dart';

/// Dashboard (pantalla 07 del diseño): gasto del mes, próximos 7 días y el
/// resto de suscripciones ordenadas por fecha de cobro.
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
      if (!mounted) return;
      if (_suscripciones == null) {
        setState(() => _error = e.mensaje);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.mensaje)));
      }
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
              proximoCobro: _proximoCobro(suscripciones, hoy),
              onPerfil: () => _abrir(Routers.perfil),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
              child: _cuerpo(pronto, despues, tarjeta),
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
  ) {
    if (_error != null) {
      return _Mensaje(
        icono: Icons.cloud_off_outlined,
        titulo: 'No pudimos cargar tus suscripciones',
        texto: _error!,
        boton: 'Reintentar',
        onPressed: () {
          setState(() => _error = null);
          _cargar();
        },
      );
    }
    if (_suscripciones == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_suscripciones!.isEmpty) {
      return _Mensaje(
        icono: Icons.receipt_long_outlined,
        titulo: 'Aún no tienes suscripciones',
        texto: 'Agrega la primera para ver cuánto pagas al mes y recibir '
            'avisos antes de cada cobro.',
        boton: 'Agregar mi primera suscripción',
        onPressed: () => _abrir(Routers.nuevaSuscripcion),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pronto.isNotEmpty) ...[
          _TituloSeccion(
            titulo: 'Próximos 7 días',
            cantidad: pronto.length,
            detalle: _porCobrar(pronto),
          ),
          ...pronto.map(tarjeta),
          const SizedBox(height: 11),
        ],
        if (despues.isNotEmpty) ...[
          _TituloSeccion(
            titulo: 'Más adelante',
            cantidad: despues.length,
            detalle: 'Ordenadas por cobro',
          ),
          ...despues.map(tarjeta),
          const SizedBox(height: 11),
        ],
        OutlinedButton(
          onPressed: () => _abrir(Routers.nuevaSuscripcion),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textSoft,
            side: const BorderSide(color: AppColors.lineStrong),
            shape: const StadiumBorder(),
            minimumSize: const Size.fromHeight(48),
            textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          child: const Text('+ Agregar suscripción manualmente'),
        ),
      ],
    );
  }

  /// "$ 65.800 por cobrar" (las pruebas gratis no suman).
  String _porCobrar(List<Suscripcion> lista) {
    final porMoneda = <String, double>{};
    for (final s in lista.where((s) => !s.esPruebaGratis)) {
      porMoneda[s.moneda] = (porMoneda[s.moneda] ?? 0) + s.monto;
    }
    if (porMoneda.isEmpty) return '';
    final textos = porMoneda.entries.map((e) => Formato.moneda(e.value, e.key));
    return '${textos.join(' + ')} por cobrar';
  }

  DateTime? _proximoCobro(List<Suscripcion> lista, DateTime hoy) {
    final fechas = lista
        .where((s) => !s.esPruebaGratis && !s.fechaProximoCobro.isBefore(hoy))
        .map((s) => s.fechaProximoCobro)
        .toList()
      ..sort();
    return fechas.isEmpty ? null : fechas.first;
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado({
    required this.resumen,
    required this.iniciales,
    required this.proximoCobro,
    required this.onPerfil,
  });

  final Resumen? resumen;
  final String? iniciales;
  final DateTime? proximoCobro;
  final VoidCallback onPerfil;

  @override
  Widget build(BuildContext context) {
    final totales = resumen?.totales ?? const [];
    // La primera es COP si existe (el backend la ordena primero).
    final principal = totales.isEmpty ? null : totales.first;
    final otras = totales.skip(1);
    final pruebas = resumen?.pruebasPorTerminar ?? const [];

    final proyeccion = totales.isEmpty
        ? Formato.moneda(0, 'COP')
        : totales.map((t) => Formato.moneda(t.proyeccionAnual, t.moneda)).join(' + ');
    final activas = resumen?.cantidadActivas ?? 0;

    return AppHeader(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _MarcaPequena(),
              const Spacer(),
              Tooltip(
                message: 'Perfil y configuración',
                child: InkWell(
                  onTap: onPerfil,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 36,
                    height: 36,
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
          // Tarjeta translúcida ("glass") del diseño.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.36)),
            ),
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
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.9,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                for (final t in otras)
                  Text(
                    '+ ${Formato.moneda(t.gastoMensual, t.moneda)} al mes',
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
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
                if (pruebas.isNotEmpty || proximoCobro != null) ...[
                  const SizedBox(height: 13),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      if (pruebas.isNotEmpty) _ChipPrueba(pruebas: pruebas),
                      if (proximoCobro != null)
                        _Chip(texto: 'Próximo cobro: ${Formato.fecha(proximoCobro!)}'),
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
      final cuando = switch (dias) {
        0 => 'hoy',
        1 => 'mañana',
        _ => 'en $dias días',
      };
      texto = '1 prueba gratis termina $cuando';
    } else {
      texto = '${pruebas.length} pruebas gratis terminan esta semana';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.amberBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.42)),
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
  const _TituloSeccion({required this.titulo, required this.cantidad, required this.detalle});

  final String titulo;
  final int cantidad;
  final String detalle;

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
              detalle,
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

/// Estado vacío o de error, con un botón de acción.
class _Mensaje extends StatelessWidget {
  const _Mensaje({
    required this.icono,
    required this.titulo,
    required this.texto,
    required this.boton,
    required this.onPressed,
  });

  final IconData icono;
  final String titulo;
  final String texto;
  final String boton;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.flagBlueBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.lineStrong),
            ),
            child: Icon(icono, color: AppColors.link),
          ),
          const SizedBox(height: 16),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            texto,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 13.5, height: 1.45),
          ),
          const SizedBox(height: 18),
          FilledButton(onPressed: onPressed, child: Text(boton)),
        ],
      ),
    );
  }
}
