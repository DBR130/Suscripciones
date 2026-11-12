import React from 'react';
import {Audio, Sequence, interpolate, staticFile} from 'remotion';
import {Fondo} from './componentes';
import {EscenaAviso, EscenaCierre, EscenaDeteccion, EscenaTarjetas} from './escenas';

export const DURACION = 450; // 15 s a 30 fps

// Los golpes "de los segundos 3, 7 y 11" de musica.mp3 arrancan en realidad en
// 2,885 s, 6,885 s y 10,880 s (medido en la forma de onda): los cortes van en
// el frame del ataque (87, 207 y 327), no en el segundo redondo, que caería
// 3–4 frames tarde, en medio del golpe.
const ESCENAS = [
  {desde: 0, dur: 87, C: EscenaTarjetas},
  {desde: 87, dur: 120, C: EscenaDeteccion},
  {desde: 207, dur: 120, C: EscenaAviso},
  {desde: 327, dur: 123, C: EscenaCierre}, // el logo arranca con el golpe
];

export type PropsAnuncio = {conMusica: boolean};

// Escenas en los golpes de la canción (3, 7 y 11 s). Música desde el segundo 0,
// con fade in de 0,3 s (9 frames) y fade out de 1 s (30 frames) al final.
const volumen = (f: number) =>
  interpolate(f, [0, 9, DURACION - 30, DURACION], [0, 1, 1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

export const Anuncio: React.FC<PropsAnuncio> = ({conMusica}) => (
  <Fondo>
    {ESCENAS.map(({desde, dur, C}) => (
      <Sequence key={desde} from={desde} durationInFrames={dur}>
        <C />
      </Sequence>
    ))}
    {conMusica && <Audio src={staticFile('musica.mp3')} volume={volumen} />}
  </Fondo>
);
