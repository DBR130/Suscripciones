# Video promocional de SubTrack

Anuncio de 15 s (1920x1080, 30 fps) hecho con [Remotion](https://www.remotion.dev/).
Proyecto aparte: no depende de la app Flutter ni del backend.

```powershell
cd video
npm install
npx remotion studio                                          # verlo y ajustarlo en vivo
npx remotion render Anuncio out/subtrack-anuncio.mp4         # renderizar el MP4
```

- Música: pon `public/musica.mp3` (fade in de 0,3 s y fade out de 1 s; no se
  sube a git por la licencia). Los cortes de escena van en los golpes de la
  canción (frames 87, 207 y 327). Si no
  está, el video sale sin audio.
- Escenas en `src/escenas.tsx`; logo animado (según
  `design/logo/4-cuenta-regresiva/animacion-inicio.md`) en `src/Logo.tsx`;
  colores y montos en `src/tema.ts`.
