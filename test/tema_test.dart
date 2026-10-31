import 'package:flutter/services.dart';
import 'package:flutter_suscripciones/Common/AppTheme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('el tema usa la fuente Inter', () {
    expect(AppTheme.dark.textTheme.bodyMedium?.fontFamily, 'Inter');
    expect(AppTheme.dark.textTheme.titleLarge?.fontFamily, 'Inter');
  });

  test('Inter va incluida en la app (sin internet) con sus 5 pesos y la licencia', () async {
    for (final archivo in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      final datos = await rootBundle.load('assets/fonts/Inter-$archivo.ttf');
      expect(datos.lengthInBytes, greaterThan(100000), reason: archivo);
    }
    final licencia = await rootBundle.loadString('assets/fonts/OFL.txt');
    expect(licencia, contains('SIL Open Font License'));
  });
}
