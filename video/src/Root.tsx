import React from 'react';
import {Composition, staticFile} from 'remotion';
import {Anuncio, DURACION, PropsAnuncio} from './Anuncio';

// Si public/musica.mp3 no existe, el video se renderiza sin audio.
const hayMusica = async () => {
  try {
    const r = await fetch(staticFile('musica.mp3'), {method: 'HEAD'});
    const tipo = r.headers.get('content-type') ?? '';
    return r.ok && !tipo.includes('text/html');
  } catch {
    return false;
  }
};

const props: PropsAnuncio = {conMusica: false};

export const Root: React.FC = () => (
  <Composition
    id="Anuncio"
    component={Anuncio}
    durationInFrames={DURACION}
    fps={30}
    width={1920}
    height={1080}
    defaultProps={props}
    calculateMetadata={async ({props: p}) => ({props: {...p, conMusica: await hayMusica()}})}
  />
);
