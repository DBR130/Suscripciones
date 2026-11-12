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

// Servicios con iniciales y color de marca (design/subtrack-pantallas.md).
export const SERVICIOS = [
  {ini: 'NF', nombre: 'Netflix', color: '#C1121F', monto: 44900},
  {ini: 'SP', nombre: 'Spotify', color: '#12833F', monto: 19900},
  {ini: 'D+', nombre: 'Disney+', color: '#113CCF', monto: 26900},
  {ini: 'YP', nombre: 'YouTube Premium', color: '#FF0000', monto: 13300},
  {ini: 'CL', nombre: 'Claude', color: '#D97757', monto: 85000},
];

export const TOTAL_MES = SERVICIOS.reduce((t, s) => t + s.monto, 0); // 190.000
