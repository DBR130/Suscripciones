import React from 'react';
import {Audio, Sequence, interpolate, staticFile} from 'remotion';
import {Fondo} from './componentes';
import {EscenaAviso, EscenaCierre, EscenaDeteccion, EscenaTarjetas} from './escenas';

export const DURACION = 450; // 15 s a 30 fps

const ESCENAS = [
  {desde: 0, dur: 90, C: EscenaTarjetas}, // 0–3 s
  {desde: 90, dur: 120, C: EscenaDeteccion}, // 3–7 s
  {desde: 210, dur: 120, C: EscenaAviso}, // 7–11 s
  {desde: 330, dur: 120, C: EscenaCierre}, // 11–15 s
];

export type PropsAnuncio = {conMusica: boolean};

// Música con fade in (1 s) y fade out (1,5 s).
const volumen = (f: number) =>
  interpolate(f, [0, 30, DURACION - 45, DURACION - 1], [0, 0.8, 0.8, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

export const Anuncio: React.FC<PropsAnuncio> = ({conMusica}) => (
  <Fondo>
    {ESCENAS.map(({desde, dur, C}) => (
      <Sequence key={desde} from={desde} durationInFrames={dur}>
        <C duracion={dur} />
      </Sequence>
    ))}
    {conMusica && <Audio src={staticFile('musica.mp3')} volume={volumen} />}
  </Fondo>
);
