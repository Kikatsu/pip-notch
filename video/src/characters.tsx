// SVG ports of the renderers in CharacterView.swift and EyeRenderer.swift.
// Everything is a pure function of `t` (seconds), so a frame always renders the same.
import React, { useId } from 'react';
import { Mood, Palette } from './theme';

export type CharacterStyle = 'livingNotch' | 'blob' | 'pixel' | 'minimal';

export const CHARACTER_TITLES: Record<CharacterStyle, { title: string; subtitle: string }> = {
  livingNotch: { title: 'Living notch', subtitle: 'The notch itself has eyes' },
  blob: { title: 'Burrow blob', subtitle: 'A soft creature hanging from the notch' },
  pixel: { title: 'Pixel bit', subtitle: 'An 8-bit sprite for terminal people' },
  minimal: { title: 'Minimal', subtitle: 'No character, just a status dot' },
};

/** Frame for the character in the expanded panel (CharacterView.largeSize). */
export const largeSize = (style: CharacterStyle) =>
  style === 'livingNotch' || style === 'minimal' ? { w: 96, h: 30 } : { w: 96, h: 58 };

const fmod = (a: number, b: number) => ((a % b) + b) % b;

type EyeProps = { mood: Mood; t: number; W: number; H: number; w: number; color: string; pupil?: string };

export const Eyes: React.FC<EyeProps> = ({ mood, t, W, H, w, color, pupil = '#000' }) => {
  const id = useId();
  const h = w * 1.4;
  const cx = W / 2;
  const cy = H / 2;
  const spread = w * 1.15;
  const sw = Math.max(1.5, w * 0.32);
  const sides = [-1, 1];
  const stroke = { stroke: color, strokeWidth: sw, strokeLinecap: 'round' as const, strokeLinejoin: 'round' as const, fill: 'none' };
  const oval = (x: number, y: number, ow: number, oh: number, fill: string, key: React.Key) => (
    <ellipse key={key} cx={x} cy={y} rx={ow / 2} ry={Math.max(0.01, oh / 2)} fill={fill} />
  );

  switch (mood) {
    case 'idle': {
      const open = fmod(t, 4.6) < 0.14 ? 0.12 : 1;
      const look = Math.sin(t * 0.45) * w * 0.25;
      return <g>{sides.map((s) => oval(cx + s * spread + look, cy, w, h * open, color, s))}</g>;
    }
    case 'working': {
      const look = Math.sin(t * 2.6) * w * 0.55;
      return <g>{sides.map((s) => oval(cx + s * spread + look, cy + h * 0.05, w * 0.9, h * 0.8, color, s))}</g>;
    }
    case 'needsYou': {
      const bounce = -Math.abs(Math.sin(t * 4.2)) * h * 0.12;
      return (
        <g>
          {sides.map((s) => {
            const x = cx + s * spread * 1.1;
            return (
              <g key={s}>
                {oval(x, cy + bounce, w * 1.15, h * 1.15, color, 'o')}
                {oval(x, cy + bounce + h * 0.2, w * 0.5, w * 0.5, pupil, 'p')}
              </g>
            );
          })}
        </g>
      );
    }
    case 'error': {
      const jitter = fmod(t, 2.2) < 0.5 ? Math.sin(t * 48) * w * 0.15 : 0;
      const r = w * 0.5;
      return (
        <g>
          {sides.map((s) => {
            const x = cx + s * spread + jitter;
            return <path key={s} d={`M${x - r} ${cy - r}L${x + r} ${cy + r}M${x + r} ${cy - r}L${x - r} ${cy + r}`} {...stroke} />;
          })}
        </g>
      );
    }
    case 'rateLimited': {
      const sway = Math.sin(t * 0.8) * w * 0.15;
      return (
        <g>
          {sides.map((s) => {
            const x = cx + s * spread + sway;
            const clip = `${id}-${s}`;
            return (
              <g key={s}>
                <clipPath id={clip}>
                  <rect x={x - w} y={cy - h * 0.05} width={w * 2} height={h} />
                </clipPath>
                <g clipPath={`url(#${clip})`}>{oval(x, cy, w, h, color, 'o')}</g>
                <path d={`M${x - w * 0.6} ${cy - h * 0.05}L${x + w * 0.6} ${cy - h * 0.05}`} {...stroke} />
              </g>
            );
          })}
        </g>
      );
    }
    case 'finished': {
      const hop = -Math.abs(Math.sin(t * 5.0)) * h * 0.18;
      return (
        <g>
          {sides.map((s) => {
            const x = cx + s * spread;
            const y = cy + h * 0.18 + hop;
            return <path key={s} d={`M${x - w * 0.6} ${y}Q${x} ${cy - h * 0.55 + hop} ${x + w * 0.6} ${y}`} {...stroke} />;
          })}
        </g>
      );
    }
    case 'asleep': {
      const alpha = 0.35 + (0.35 * (Math.sin(t * 1.4) + 1)) / 2;
      return (
        <g opacity={alpha}>
          {sides.map((s) => {
            const x = cx + s * spread;
            return <path key={s} d={`M${x - w * 0.6} ${cy}Q${x} ${cy + h * 0.45} ${x + w * 0.6} ${cy}`} {...stroke} />;
          })}
        </g>
      );
    }
  }
};

const BLOB_BODY = 'rgb(240, 138, 74)';
const BLOB_INK = 'rgb(31, 28, 23)';

const Blob: React.FC<{ mood: Mood; t: number; W: number; H: number; large: boolean }> = ({ mood, t, W, H, large }) => {
  const scale = Math.min(H / 112, W / 120);
  const base = `translate(${W / 2 - 60 * scale} 0) scale(${scale})`;
  let motion = '';
  let opacity = 1;
  let shrink = 1;
  switch (mood) {
    case 'working':
      motion = `translate(60 0) scale(1 ${1 + 0.035 * Math.sin(t * 3)}) translate(-60 0)`;
      break;
    case 'needsYou':
      motion = `translate(60 0) rotate(${5 * Math.sin(t * 5.5)}) translate(-60 0)`;
      break;
    case 'finished':
      motion = `translate(0 ${Math.abs(Math.sin(t * 4.5)) * 9})`;
      break;
    case 'error':
      motion = `translate(${fmod(t, 2.2) < 0.5 ? Math.sin(t * 46) * 3 : 0} 0)`;
      opacity = 0.85;
      break;
    case 'rateLimited':
      motion = 'translate(60 0) scale(1.03 0.9) translate(-60 0)';
      break;
    case 'asleep':
      shrink = 0.78;
      opacity = 0.75;
      break;
  }
  const body = 'M20 0L20 48C20 82 38 98 60 98C82 98 100 82 100 48L100 0Z';
  const confetti = [
    [6, 60],
    [108, 50],
    [12, 96],
    [104, 92],
  ];
  return (
    <g transform={base}>
      <g transform={`${motion} translate(60 0) scale(${shrink}) translate(-60 0)`}>
        <path d={body} fill={BLOB_BODY} opacity={opacity} />
        {(large || mood !== 'asleep') &&
          [36, 84].map((x) => <ellipse key={x} cx={x} cy={70.5} rx={6} ry={4.5} fill="rgb(194, 64, 13)" opacity={0.3} />)}
        <g transform="translate(0 10)">
          <Eyes mood={mood} t={t} W={120} H={92} w={11} color={BLOB_INK} pupil="#fff" />
        </g>
      </g>
      {large && mood === 'finished' &&
        confetti.map(([x, y], i) => {
          const phase = fmod(t * 0.8 + i * 0.25, 1);
          return <rect key={i} x={x} y={y - phase * 14} width={6} height={9} rx={1} fill={i % 2 ? '#3b82f6' : Palette.amber} opacity={1 - phase} />;
        })}
      {large && mood === 'error' && (
        <circle cx={108} cy={86 - fmod(t * 0.6, 1) * 16} r={6} fill="gray" opacity={0.6 * (1 - fmod(t * 0.6, 1))} />
      )}
      {large && mood === 'needsYou' && <circle cx={112 + 3.5 / scale} cy={30 + 3.5 / scale} r={3.5 / scale} fill={Palette.amber} />}
    </g>
  );
};

const PIXEL_BODY = 'rgb(166, 140, 250)';
const PIXEL_INK = 'rgb(13, 18, 23)';
const PIXEL_GREEN = 'rgb(74, 222, 128)';

const Pixel: React.FC<{ mood: Mood; t: number; W: number; H: number; large: boolean }> = ({ mood, t, W, H, large }) => {
  const u = Math.floor(Math.min(H / 13, W / 12) * 2) / 2;
  const originX = (W - 12 * u) / 2;
  const step = Math.floor(t * 2.5);
  let dx = 0;
  let dy = 0;
  let rows = 7;
  let opacity = 1;
  switch (mood) {
    case 'working':
      dy = step % 2 === 0 ? 0 : 0.5;
      break;
    case 'error':
      dx = fmod(t, 2.2) < 0.6 ? (step % 2 === 0 ? -0.5 : 0.5) : 0;
      break;
    case 'finished':
      dy = Math.floor(t * 2) % 3 === 0 ? 1 : 0;
      break;
    case 'asleep':
      rows = 5;
      opacity = 0.7;
      break;
  }
  const rects: React.ReactNode[] = [];
  const px = (x: number, y: number, w: number, h: number, fill: string, o = 1) =>
    rects.push(<rect key={rects.length} x={originX + (x + dx) * u} y={(y + dy) * u} width={w * u} height={h * u} fill={fill} opacity={o} />);

  px(2, 0, 8, rows, PIXEL_BODY, opacity);
  for (const x of [2, 5, 8]) px(x, rows, 2, 1, PIXEL_BODY, opacity);
  px(9, 0, 1, rows, 'black', 0.2);

  const eyes = [4, 7];
  switch (mood) {
    case 'idle': {
      const blink = fmod(t, 4) < 0.15;
      for (const x of eyes) px(x, blink ? 3.5 : 3, 1, blink ? 0.5 : 2, PIXEL_INK);
      break;
    }
    case 'working': {
      const look = step % 4 < 2 ? -0.5 : 0.5;
      for (const x of eyes) px(x + look, 4, 1, 1, PIXEL_INK);
      if (large && step % 2 === 0) px(5, 9.5, 2, 1, PIXEL_GREEN);
      break;
    }
    case 'needsYou':
      for (const x of eyes) {
        px(x, 2.5, 1, 2.5, PIXEL_INK);
        px(x, 2.5, 0.5, 0.5, '#fff');
      }
      if (Math.floor(t * 3) % 2 === 0) {
        px(10.5, 2, 1, 2.5, Palette.amber);
        px(10.5, 5, 1, 1, Palette.amber);
      }
      break;
    case 'error':
      for (const x of eyes) {
        px(x - 0.5, 3, 0.5, 0.5, PIXEL_INK);
        px(x + 0.5, 3, 0.5, 0.5, PIXEL_INK);
        px(x, 3.5, 0.5, 0.5, PIXEL_INK);
        px(x - 0.5, 4, 0.5, 0.5, PIXEL_INK);
        px(x + 0.5, 4, 0.5, 0.5, PIXEL_INK);
      }
      if (large) px(10.5, 8 - (step % 3), 1, 1, 'gray');
      break;
    case 'rateLimited':
      for (const x of eyes) px(x - 0.5, 4, 2, 0.5, PIXEL_INK);
      px(10.5, 1, 1, 1, Palette.amber);
      break;
    case 'finished':
      for (const x of eyes) {
        px(x - 0.5, 4, 0.5, 0.5, PIXEL_INK);
        px(x, 3.5, 0.5, 0.5, PIXEL_INK);
        px(x + 0.5, 4, 0.5, 0.5, PIXEL_INK);
      }
      if (large && step % 2 === 0) {
        px(0, 4, 0.5, 1.5, PIXEL_GREEN);
        px(-0.5, 4.5, 1.5, 0.5, PIXEL_GREEN);
        px(11.5, 7, 0.5, 1.5, PIXEL_GREEN);
        px(11, 7.5, 1.5, 0.5, PIXEL_GREEN);
      }
      break;
    case 'asleep':
      for (const x of eyes) px(x - 0.5, 3, 1.5, 0.5, PIXEL_INK);
      break;
  }
  return <g shapeRendering="crispEdges">{rects}</g>;
};

const Minimal: React.FC<{ mood: Mood; t: number; W: number; H: number; large: boolean }> = ({ mood, t, W, H, large }) => {
  const r = large ? 5 : 3.5;
  const c = { cx: W / 2, cy: H / 2 };
  switch (mood) {
    case 'asleep':
      return null;
    case 'idle':
      return <circle {...c} r={r} fill="#fff" opacity={0.35} />;
    case 'working':
      return <circle {...c} r={r} fill="#fff" opacity={0.45 + (0.55 * (Math.sin(t * 3) + 1)) / 2} />;
    case 'needsYou': {
      const p = fmod(t * 0.85, 1);
      return (
        <g>
          <circle {...c} r={r * (1 + 1.6 * p)} fill={Palette.amber} opacity={(1 - p) * 0.8} />
          <circle {...c} r={r} fill={Palette.amber} />
        </g>
      );
    }
    case 'error':
      return <circle {...c} r={r} fill={Palette.red} />;
    case 'rateLimited':
      return <circle {...c} r={r} fill={Palette.amber} opacity={0.6} />;
    case 'finished':
      return <circle {...c} r={r} fill={Palette.green} />;
  }
};

export type Reaction = { kind: 'hello' | 'poke' | 'approve' | 'deny'; progress: number };

/** CharacterView.react: the mood to draw while a reaction plays, and how to stretch the face. */
export const react = (mood: Mood, reaction?: Reaction): { mood: Mood; sx: number; sy: number } => {
  if (!reaction || reaction.progress < 0 || reaction.progress >= 1) return { mood, sx: 1, sy: 1 };
  const p = reaction.progress;
  const swell = Math.sin(p * Math.PI);
  switch (reaction.kind) {
    case 'hello':
      return { mood: mood === 'asleep' ? 'idle' : mood, sx: 1 + 0.18 * swell, sy: 1 + 0.18 * swell };
    case 'poke': {
      const wobble = Math.sin(p * Math.PI * 3) * (1 - p);
      return { mood: 'finished', sx: 1 + 0.16 * wobble, sy: 1 - 0.2 * wobble };
    }
    case 'approve':
      return { mood: 'finished', sx: 1 + 0.08 * swell, sy: 1 + 0.08 * swell };
    case 'deny':
      return { mood: 'rateLimited', sx: 1 + 0.06 * swell, sy: 1 - 0.1 * swell };
  }
};

type CharacterProps = {
  style: CharacterStyle;
  mood: Mood;
  t: number;
  large?: boolean;
  /** Design size in points; defaults to the ear (44 x 32) or the large panel size. */
  width?: number;
  height?: number;
  /** Rendered pixels per point. */
  zoom?: number;
  gaze?: { x: number; y: number };
  reaction?: Reaction;
};

export const Character: React.FC<CharacterProps> = ({ style, mood: baseMood, t, large = false, width, height, zoom = 1, gaze = { x: 0, y: 0 }, reaction }) => {
  const size = large ? largeSize(style) : { w: 44, h: 32 };
  const W = width ?? size.w;
  const H = height ?? size.h;
  const { mood, sx, sy } = react(baseMood, reaction);
  const reach = large ? 5 : 1.6;
  const transform = `translate(${W / 2} ${H / 2}) scale(${sx} ${sy}) translate(${-W / 2} ${-H / 2}) translate(${gaze.x * reach} ${gaze.y * reach * 0.6})`;
  return (
    <svg width={W * zoom} height={H * zoom} viewBox={`0 0 ${W} ${H}`} style={{ overflow: 'visible', display: 'block' }}>
      <g transform={transform}>
        {style === 'livingNotch' && <Eyes mood={mood} t={t} W={W} H={H} w={large ? 13 : 6} color="#fff" />}
        {style === 'blob' && <Blob mood={mood} t={t} W={W} H={H} large={large} />}
        {style === 'pixel' && <Pixel mood={mood} t={t} W={W} H={H} large={large} />}
        {style === 'minimal' && <Minimal mood={mood} t={t} W={W} H={H} large={large} />}
      </g>
    </svg>
  );
};
