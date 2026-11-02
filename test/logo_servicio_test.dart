import 'package:flutter/material.dart';
import 'package:flutter_suscripciones/widgets/logo_servicio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Colores de marca del logo de cada servicio (design/subtrack-pantallas.md).
void main() {
  test('usa el color de marca del diseño', () {
    expect(LogoServicio.colorDe('Spotify'), const Color(0xFF12833F));
    expect(LogoServicio.colorDe('Netflix'), const Color(0xFFC1121F));
    expect(LogoServicio.colorDe('Disney+'), const Color(0xFF113CCF));
    expect(LogoServicio.colorDe('Paramount+'), const Color(0xFF0064FF));
    expect(LogoServicio.colorDe('Smart Fit'), const Color(0xFF8A7A00));
  });

  test('reconoce el servicio dentro de un nombre más largo, sin importar mayúsculas', () {
    expect(LogoServicio.colorDe('SPOTIFY P1A2B3'), const Color(0xFF12833F));
    expect(LogoServicio.colorDe('YouTube Premium'), const Color(0xFFFF0000));
    expect(LogoServicio.colorDe('DiDi'), const Color(0xFFFC6B21));
    expect(LogoServicio.colorDe('Claude'), const Color(0xFFD97757));
    // La clave más larga gana: Photoshop (diseño) antes que Adobe.
    expect(LogoServicio.colorDe('Adobe Photoshop'), const Color(0xFF0A2F52));
    expect(LogoServicio.colorDe('Adobe'), const Color(0xFFEB1000));
  });

  test('sin color de marca conocido usa el neutro', () {
    expect(LogoServicio.colorDe('Servicios Web Ebanx Co'), LogoServicio.colorNeutro);
    expect(LogoServicio.colorDe('Bodytech'), LogoServicio.colorNeutro);
    // Solo palabras completas: "Maxi" no es Max.
    expect(LogoServicio.colorDe('Maxi Ahorro'), LogoServicio.colorNeutro);
    expect(LogoServicio.colorNeutro, const Color(0xFF334155));
  });
}
