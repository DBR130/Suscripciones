import 'package:flutter/material.dart';
import 'package:flutter_suscripciones/widgets/movimiento.dart';
import 'package:flutter_test/flutter_test.dart';

/// Animaciones de la app: cuentan, aparecen y respetan "reducir animaciones".
void main() {
  Widget app(Widget hijo, {bool reducir = false}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reducir),
          child: Scaffold(body: hijo),
        ),
      );

  final numero = NumeroAnimado(valor: 1000, formato: (v) => v.round().toString());

  testWidgets('el número cuenta desde 0 hasta su valor', (tester) async {
    await tester.pumpWidget(app(numero));
    expect(find.text('0'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('1000'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('1000'), findsOneWidget);
  });

  testWidgets('con animaciones reducidas todo aparece en su estado final', (tester) async {
    await tester.pumpWidget(app(
      Column(children: [numero, const AparicionEscalonada(indice: 5, child: Text('Tarjeta'))]),
      reducir: true,
    ));
    expect(find.text('1000'), findsOneWidget);
    final opacidad = tester.widget<Opacity>(find.ancestor(of: find.text('Tarjeta'), matching: find.byType(Opacity)));
    expect(opacidad.opacity, 1);
    // El esqueleto queda quieto: no hay animaciones pendientes.
    await tester.pumpWidget(app(const EsqueletoTarjetas(), reducir: true));
    expect(tester.hasRunningAnimations, isFalse);
  });
}
