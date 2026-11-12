import {loadFont} from '@remotion/google-fonts/Inter';

// Mismos tokens que design/subtrack-simulacion.html (:root).
export const C = {
  page: '#080D18',
  bg: '#0B1220',
  surface: '#141D2F',
  surface2: '#16273F',
  surface3: '#1C2942',
  line: '#243149',
  line2: '#2C3B58',
  text: '#E9EFFA',
  text2: '#D6E3FB',
  muted: '#9AAAC4',
  mutedHero: '#A6B6D0',
  primary: '#2563EB',
  accent: '#60A5FA',
  link: '#7DB3FF',
  accentSoft: '#A9CCFF',
  tramo: '#17367B',
  barra: '#1E2E4A',
};

export const {fontFamily} = loadFont('normal', {
  weights: ['500', '600', '700', '800'],
  subsets: ['latin'],
});

export const FPS = 30;

// $44.900 (pesos colombianos, sin decimales y con punto de miles).
export const pesos = (n: number) =>
  '$' + Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, '.');

// Misma regla que LogoServicio.iniciales (lib/widgets/logo_servicio.dart):
// una palabra → primera mayúscula + segunda minúscula ("Netflix" → "Ne");
// varias → primera letra de las dos primeras ("YouTube Premium" → "YP").
export const iniciales = (nombre: string) => {
  const palabras = nombre.trim().split(/\s+/).filter((p) => p.length > 0);
  if (palabras.length === 0) return '?';
  if (palabras.length === 1) {
    const p = palabras[0];
    return p.length >= 2 ? p[0].toUpperCase() + p[1].toLowerCase() : p.toUpperCase();
  }
  return (palabras[0][0] + palabras[1][0]).toUpperCase();
};

// Servicios con su color de marca (LogoServicio.coloresMarca).
export const SERVICIOS = [
  {nombre: 'Netflix', color: '#C1121F', monto: 44900},
  {nombre: 'Spotify', color: '#12833F', monto: 19900},
  {nombre: 'Disney+', color: '#113CCF', monto: 26900},
  {nombre: 'YouTube Premium', color: '#FF0000', monto: 13300},
  {nombre: 'Claude', color: '#D97757', monto: 65570}, // precio real detectado
].map((s) => ({...s, ini: iniciales(s.nombre)}));

export const TOTAL_MES = SERVICIOS.reduce((t, s) => t + s.monto, 0); // 170.570
