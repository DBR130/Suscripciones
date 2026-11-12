import React from 'react';
import {AbsoluteFill, Easing, interpolate, useCurrentFrame} from 'remotion';
import {Escena, LogoServicio, Notificacion, Titular, tarjeta, useResorte} from './componentes';
import {IconoApp, LogoConNombre} from './Logo';
import {C, FPS, SERVICIOS, TOTAL_MES, pesos} from './tema';

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;

/* ---------- 0–3 s: tarjetas en cascada y contador ---------- */
const TarjetaServicio: React.FC<{s: (typeof SERVICIOS)[number]; desde: number}> = ({s, desde}) => {
  const t = useResorte(desde, 13);
  return (
    <div
      style={{
        ...tarjeta,
        width: 300,
        padding: 28,
        display: 'flex',
        flexDirection: 'column',
        gap: 22,
        opacity: Math.min(1, t * 1.4),
        transform: `translateY(${(1 - t) * 140}px) scale(${0.9 + 0.1 * t})`,
      }}
    >
      <LogoServicio ini={s.ini} color={s.color} size={84} />
      <div>
        <div style={{fontSize: 27, fontWeight: 700, letterSpacing: '-0.015em', whiteSpace: 'nowrap'}}>{s.nombre}</div>
        <div style={{marginTop: 10, fontSize: 32, fontWeight: 800, fontVariantNumeric: 'tabular-nums'}}>
          {pesos(s.monto)}
          <span style={{fontSize: 20, color: C.muted, fontWeight: 600}}> /mes</span>
        </div>
      </div>
    </div>
  );
};

export const EscenaTarjetas: React.FC<{duracion: number}> = ({duracion}) => {
  const frame = useCurrentFrame();
  const total = interpolate(frame, [12, 72], [0, TOTAL_MES], {...clamp, easing: Easing.out(Easing.cubic)});
  const contador = useResorte(10, 18);
  return (
    <Escena duracion={duracion}>
      <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', gap: 70}}>
        <Titular desde={2}>¿Sabes cuánto pagas en suscripciones?</Titular>
        <div style={{display: 'flex', gap: 30}}>
          {SERVICIOS.map((s, i) => (
            <TarjetaServicio key={s.ini} s={s} desde={8 + i * 6} />
          ))}
        </div>
        <div style={{textAlign: 'center', opacity: contador}}>
          <div style={{fontSize: 26, fontWeight: 700, color: C.muted, letterSpacing: '.08em', textTransform: 'uppercase'}}>
            Total al mes
          </div>
          <div
            style={{
              fontSize: 110,
              fontWeight: 800,
              letterSpacing: '-0.03em',
              fontVariantNumeric: 'tabular-nums',
              lineHeight: 1.05,
            }}
          >
            {pesos(total)}
          </div>
        </div>
      </AbsoluteFill>
    </Escena>
  );
};

/* ---------- Celular estilizado ---------- */
const Celular: React.FC<{children: React.ReactNode}> = ({children}) => (
  <div
    style={{
      width: 460,
      height: 940,
      borderRadius: 64,
      padding: 14,
      background: C.surface3,
      boxShadow: `0 40px 90px rgba(0,0,0,.55), inset 0 0 0 2px ${C.line2}`,
      flex: 'none',
    }}
  >
    <div
      style={{
        position: 'relative',
        width: '100%',
        height: '100%',
        borderRadius: 52,
        overflow: 'hidden',
        background: 'linear-gradient(160deg,#0D1526 0%,#152443 55%,#1E3A6E 100%)',
      }}
    >
      <div
        style={{
          position: 'absolute',
          top: 16,
          left: '50%',
          width: 30,
          height: 30,
          marginLeft: -15,
          borderRadius: '50%',
          background: '#05080F',
        }}
      />
      <div style={{textAlign: 'center', paddingTop: 110}}>
        <div style={{fontSize: 96, fontWeight: 700, letterSpacing: '-0.03em', lineHeight: 1}}>8:15</div>
        <div style={{fontSize: 20, fontWeight: 600, color: C.mutedHero, marginTop: 10}}>miércoles, 11 de noviembre</div>
      </div>
      {children}
    </div>
  </div>
);

const IconoMensajes: React.FC<{size: number}> = ({size}) => (
  <div
    style={{
      width: size,
      height: size,
      borderRadius: size * 0.3,
      background: C.primary,
      display: 'grid',
      placeItems: 'center',
      flex: 'none',
    }}
  >
    <svg width={size * 0.58} height={size * 0.58} viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2.2" strokeLinejoin="round">
      <path d="M4 5h16v11H9l-5 4z" />
    </svg>
  </div>
);

/* ---------- 3–7 s: llega el SMS y SubTrack lo detecta ---------- */
export const EscenaDeteccion: React.FC<{duracion: number}> = ({duracion}) => {
  const celular = useResorte(0, 16);
  const sms = useResorte(14, 15);
  const push = useResorte(46, 13);
  return (
    <Escena duracion={duracion}>
      <AbsoluteFill style={{flexDirection: 'row', alignItems: 'center', padding: '0 170px', gap: 120}}>
        <div style={{flex: 1}}>
          <Titular desde={50} size={92}>
            SubTrack la detecta <span style={{color: C.accent}}>sola.</span>
          </Titular>
          <Titular desde={60} size={32} style={{fontWeight: 600, color: C.mutedHero, marginTop: 28, letterSpacing: '-0.01em'}}>
            Lee el aviso del banco en tu celular y te pregunta.
          </Titular>
        </div>
        <div style={{transform: `translateY(${(1 - celular) * 200}px)`, opacity: celular}}>
          <Celular>
            <div style={{position: 'absolute', left: 18, right: 18, top: 330}}>
              <div style={{opacity: sms, transform: `translateY(${(1 - sms) * 40}px)`}}>
                <Notificacion
                  icono={<IconoMensajes size={46} />}
                  app="Mensajes · ahora"
                  titulo="Bancolombia"
                  cuerpo="Bancolombia: Compraste $44.900,00 en NETFLIX con tu T.Deb *0000"
                />
              </div>
            </div>
            <div
              style={{
                position: 'absolute',
                left: 12,
                right: 12,
                top: 60,
                opacity: push,
                transform: `translateY(${(1 - push) * -120}px) scale(${0.94 + 0.06 * push})`,
              }}
            >
              <Notificacion
                vidrio
                icono={<IconoApp size={50} />}
                app="SubTrack · ahora"
                titulo="¿Tienes una suscripción a Netflix?"
                cuerpo="Detectamos un cobro de $44.900. Toca para confirmarla."
              />
            </div>
          </Celular>
        </div>
      </AbsoluteFill>
    </Escena>
  );
};

/* ---------- 7–11 s: aviso antes del cobro y gráfica ---------- */
const MESES = ['jun', 'jul', 'ago', 'sep', 'oct', 'nov'];
const GASTO = [128000, 141000, 141000, 163000, 176000, TOTAL_MES];

const Grafica: React.FC = () => {
  const frame = useCurrentFrame();
  const entrada = useResorte(36, 16);
  const max = Math.max(...GASTO);
  const etiqueta = interpolate(frame, [78, 90], [0, 1], clamp);
  return (
    <div
      style={{
        ...tarjeta,
        width: 820,
        padding: '36px 40px 30px',
        opacity: entrada,
        transform: `translateY(${(1 - entrada) * 60}px)`,
      }}
    >
      <div style={{fontSize: 22, fontWeight: 700, color: C.muted, letterSpacing: '.08em', textTransform: 'uppercase'}}>
        Gasto mensual
      </div>
      <div style={{fontSize: 30, fontWeight: 700, marginTop: 6, color: C.text2}}>Suscripciones activas</div>
      <div style={{display: 'flex', alignItems: 'flex-end', gap: 26, height: 380, marginTop: 30}}>
        {GASTO.map((v, i) => {
          const crece = interpolate(frame, [40 + i * 3, 66 + i * 3], [0, 1], {...clamp, easing: Easing.out(Easing.cubic)});
          const ultima = i === GASTO.length - 1;
          return (
            <div
              key={MESES[i]}
              style={{
                flex: 1,
                height: '100%',
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                justifyContent: 'flex-end',
                gap: 14,
              }}
            >
              {ultima && (
                <div style={{fontSize: 30, fontWeight: 800, color: C.link, opacity: etiqueta, fontVariantNumeric: 'tabular-nums'}}>
                  {pesos(v)}
                </div>
              )}
              <div
                style={{
                  width: '100%',
                  height: `${(v / max) * 76 * crece}%`,
                  borderRadius: '16px 16px 6px 6px',
                  background: ultima ? C.primary : C.barra,
                  border: ultima ? 'none' : `2px solid ${C.line}`,
                }}
              />
              <div style={{fontSize: 22, fontWeight: 700, color: ultima ? C.text : C.muted}}>{MESES[i]}</div>
            </div>
          );
        })}
      </div>
    </div>
  );
};

export const EscenaAviso: React.FC<{duracion: number}> = ({duracion}) => {
  const aviso = useResorte(4, 13);
  return (
    <Escena duracion={duracion}>
      <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', gap: 64}}>
        <Titular desde={2} size={64} style={{textAlign: 'center'}}>
          Te avisa antes de cada cobro
          <br />
          <span style={{color: C.accent}}>y te muestra en qué se va tu plata.</span>
        </Titular>
        <div style={{display: 'flex', alignItems: 'center', gap: 70}}>
          <div style={{width: 760, opacity: aviso, transform: `translateX(${(1 - aviso) * -80}px)`}}>
            <Notificacion
              vidrio
              escala={1.6}
              icono={<IconoApp size={80} />}
              app="SubTrack · Próximo cobro"
              titulo="Netflix te cobra $44.900 mañana"
              cuerpo="Si ya no la quieres, este es el momento."
            />
          </div>
          <Grafica />
        </div>
      </AbsoluteFill>
    </Escena>
  );
};

/* ---------- 11–15 s: logo y cierre ---------- */
export const EscenaCierre: React.FC<{duracion: number}> = ({duracion}) => {
  const frame = useCurrentFrame();
  const ms = ((frame - 6) / FPS) * 1000;
  const lema = useResorte(56, 18);
  const privacidad = interpolate(frame, [76, 90], [0, 1], clamp);
  return (
    <Escena duracion={duracion} sinSalida>
      <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center'}}>
        <LogoConNombre ms={ms} ancho={1100} />
        <div
          style={{
            marginTop: 40,
            fontSize: 58,
            fontWeight: 700,
            letterSpacing: '-0.02em',
            opacity: lema,
            transform: `translateY(${(1 - lema) * 24}px)`,
          }}
        >
          SubTrack. <span style={{color: C.accent}}>Que ningún cobro te tome por sorpresa.</span>
        </div>
        <div style={{marginTop: 34, fontSize: 28, fontWeight: 600, color: C.muted, opacity: privacidad}}>
          Tus mensajes nunca salen de tu celular.
        </div>
      </AbsoluteFill>
    </Escena>
  );
};
