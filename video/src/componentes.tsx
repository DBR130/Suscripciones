import React from 'react';
import {AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {C, fontFamily} from './tema';

// Fondo oscuro con dos resplandores suaves (como los "orbs" de la simulación).
export const Fondo: React.FC<{children: React.ReactNode}> = ({children}) => {
  const frame = useCurrentFrame();
  const deriva = Math.sin(frame / 40) * 30;
  return (
    <AbsoluteFill style={{backgroundColor: C.bg, fontFamily, color: C.text}}>
      <div
        style={{
          position: 'absolute',
          width: 1100,
          height: 1100,
          left: -300 + deriva,
          top: -500,
          borderRadius: '50%',
          background: 'radial-gradient(circle, rgba(37,99,235,.22), transparent 65%)',
        }}
      />
      <div
        style={{
          position: 'absolute',
          width: 900,
          height: 900,
          right: -250 - deriva,
          bottom: -450,
          borderRadius: '50%',
          background: 'radial-gradient(circle, rgba(96,165,250,.14), transparent 65%)',
        }}
      />
      {children}
    </AbsoluteFill>
  );
};

// Entrada y salida suaves de cada escena.
export const Escena: React.FC<{duracion: number; children: React.ReactNode; sinSalida?: boolean}> = ({
  duracion,
  children,
  sinSalida,
}) => {
  const frame = useCurrentFrame();
  const entrada = interpolate(frame, [0, 8], [0, 1], {extrapolateRight: 'clamp'});
  const salida = sinSalida
    ? 1
    : interpolate(frame, [duracion - 8, duracion], [1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  return <AbsoluteFill style={{opacity: Math.min(entrada, salida)}}>{children}</AbsoluteFill>;
};

// Valor 0→1 con resorte que arranca en `desde` (frames).
export const useResorte = (desde: number, damping = 14) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  return spring({frame: frame - desde, fps, config: {damping, mass: 0.8}});
};

// Titular que sube y aparece.
export const Titular: React.FC<{
  desde: number;
  size?: number;
  children: React.ReactNode;
  style?: React.CSSProperties;
}> = ({desde, size = 76, children, style}) => {
  const t = useResorte(desde, 18);
  return (
    <div
      style={{
        fontSize: size,
        fontWeight: 800,
        letterSpacing: '-0.025em',
        lineHeight: 1.12,
        opacity: t,
        transform: `translateY(${(1 - t) * 30}px)`,
        ...style,
      }}
    >
      {children}
    </div>
  );
};

// Cuadro de color con iniciales (LogoServicio de la app).
export const LogoServicio: React.FC<{ini: string; color: string; size: number}> = ({ini, color, size}) => (
  <div
    style={{
      width: size,
      height: size,
      borderRadius: size * 0.27,
      background: color,
      color: '#fff',
      display: 'grid',
      placeItems: 'center',
      fontWeight: 800,
      fontSize: size * 0.36,
      letterSpacing: '-0.02em',
      flex: 'none',
    }}
  >
    {ini}
  </div>
);

export const tarjeta: React.CSSProperties = {
  background: C.surface,
  border: `2px solid ${C.line}`,
  borderRadius: 28,
  boxShadow: '0 24px 60px rgba(0,0,0,.35)',
};

// Notificación del sistema (estilo .push de la simulación, sobre fondo oscuro).
export const Notificacion: React.FC<{
  icono: React.ReactNode;
  app: string;
  titulo: string;
  cuerpo: string;
  escala?: number;
  vidrio?: boolean;
}> = ({icono, app, titulo, cuerpo, escala = 1, vidrio}) => (
  <div
    style={{
      display: 'flex',
      gap: 16 * escala,
      alignItems: 'flex-start',
      padding: `${20 * escala}px ${22 * escala}px`,
      borderRadius: 28 * escala,
      background: vidrio ? 'rgba(38,54,88,.97)' : 'rgba(20,29,47,.94)',
      border: `${1.5 * escala}px solid ${vidrio ? 'rgba(255,255,255,.36)' : C.line2}`,
      boxShadow: vidrio
        ? 'inset 0 1px 0 rgba(255,255,255,.5), 0 18px 40px rgba(0,0,0,.45)'
        : '0 12px 30px rgba(0,0,0,.35)',
      color: '#F2F6FD',
    }}
  >
    {icono}
    <div style={{minWidth: 0, flex: 1}}>
      <div style={{fontSize: 15 * escala, fontWeight: 600, color: C.mutedHero, marginBottom: 4 * escala}}>{app}</div>
      <div style={{fontSize: 21 * escala, fontWeight: 800, letterSpacing: '-0.015em', lineHeight: 1.25}}>{titulo}</div>
      <div style={{fontSize: 17 * escala, fontWeight: 500, color: C.text2, marginTop: 5 * escala, lineHeight: 1.4}}>
        {cuerpo}
      </div>
    </div>
  </div>
);
