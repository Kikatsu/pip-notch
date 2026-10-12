import React from 'react';
import { AbsoluteFill, Easing, interpolate, spring, useCurrentFrame, useVideoConfig } from 'remotion';
import { sans } from './theme';

/** Seconds since the scene started, for the characters' clocks. */
export const useT = (offset = 0) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return frame / fps + offset;
};

export const useSpring = (delay = 0, config: Partial<{ damping: number; stiffness: number; mass: number }> = {}, durationInFrames?: number) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return spring({ frame: frame - delay, fps, config: { damping: 14, stiffness: 160, mass: 0.7, ...config }, durationInFrames });
};

export const ramp = (frame: number, from: number, to: number, ease = Easing.bezier(0.22, 1, 0.36, 1)) =>
  interpolate(frame, [from, to], [0, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: ease });

/** 0 → 1 → 0 over [from, to], for presses and flashes. */
export const bump = (frame: number, from: number, to: number) => {
  if (frame < from || frame > to) return 0;
  return Math.sin(((frame - from) / (to - from)) * Math.PI);
};

/** A headline that rises in word by word, with a little blur, then optionally leaves. */
export const Words: React.FC<{
  text: string;
  delay?: number;
  stagger?: number;
  size?: number;
  weight?: number;
  color?: string;
  exitAt?: number;
  highlight?: Record<string, string>;
  style?: React.CSSProperties;
  align?: 'center' | 'left';
}> = ({ text, delay = 0, stagger = 3, size = 110, weight = 800, color = '#fff', exitAt, highlight = {}, style, align = 'center' }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const words = text.split(' ');
  const exit = exitAt === undefined ? 0 : ramp(frame, exitAt, exitAt + 8, Easing.in(Easing.cubic));
  return (
    <div
      style={{
        display: 'flex',
        flexWrap: 'wrap',
        justifyContent: align === 'center' ? 'center' : 'flex-start',
        gap: `0 ${size * 0.26}px`,
        font: `${weight} ${size}px/1.02 ${sans}`,
        letterSpacing: -size * 0.035,
        color,
        ...style,
      }}
    >
      {words.map((w, i) => {
        const p = spring({ frame: frame - delay - i * stagger, fps, config: { damping: 13, stiffness: 170, mass: 0.6 } });
        const clean = w.replace(/[.,!?]/g, '');
        const hl = highlight[clean];
        return (
          <span
            key={i}
            style={{
              display: 'inline-block',
              opacity: Math.min(1, p * 1.4) * (1 - exit),
              transform: `translateY(${(1 - p) * size * 0.55 - exit * size * 0.4}px) scale(${0.92 + 0.08 * p})`,
              filter: `blur(${(1 - Math.min(1, p)) * 10 + exit * 12}px)`,
              ...(hl ? { color: hl } : {}),
            }}
          >
            {w}
          </span>
        );
      })}
    </div>
  );
};

/** Wraps a scene in a camera: a punch-in on the cut, slow drift, and an optional exit zoom. */
export const Camera: React.FC<{ children: React.ReactNode; punch?: number; drift?: number; duration: number; exit?: 'zoom' | 'whipLeft' | 'whipUp' | 'none'; origin?: string }> = ({
  children,
  punch = 0.08,
  drift = 0.04,
  duration,
  exit = 'none',
  origin = '50% 50%',
}) => {
  const frame = useCurrentFrame();
  const enter = ramp(frame, 0, 14);
  const out = ramp(frame, duration - 10, duration, Easing.in(Easing.quad));
  let scale = 1 + punch * (1 - enter) + drift * (frame / duration);
  let x = 0;
  let y = 0;
  let blur = 0;
  if (exit === 'zoom') {
    scale *= 1 + out * 0.3;
    blur = out * 8;
  } else if (exit === 'whipLeft') {
    x = -out * 420;
    blur = out * 16;
  } else if (exit === 'whipUp') {
    y = -out * 340;
    blur = out * 16;
  }
  return (
    <AbsoluteFill style={{ transform: `translate(${x}px, ${y}px) scale(${scale})`, transformOrigin: origin, filter: blur ? `blur(${blur}px)` : undefined }}>
      {children}
    </AbsoluteFill>
  );
};

/** A full-frame colour flash, used on the hardest cuts. */
export const Flash: React.FC<{ at: number; color?: string; length?: number; strength?: number }> = ({ at, color = '#fff', length = 6, strength = 0.55 }) => {
  const frame = useCurrentFrame();
  const o = frame < at || frame > at + length ? 0 : (1 - (frame - at) / length) * strength;
  return <AbsoluteFill style={{ background: color, opacity: o, pointerEvents: 'none', mixBlendMode: 'screen' }} />;
};

/** A flat, solid backdrop. */
export const Stage: React.FC<{ bg?: string; children?: React.ReactNode }> = ({ bg = '#000', children }) => (
  <AbsoluteFill style={{ background: bg, overflow: 'hidden' }}>{children}</AbsoluteFill>
);

export const SMOOTH = Easing.bezier(0.65, 0, 0.35, 1);

/**
 * A solid colour that floods out of a point (usually the notch) as a growing circle.
 * Anything passed as children is the "after" version of the layout, revealed inside the same circle,
 * so text changes colour exactly where the flood passes instead of all at once.
 */
export const Wipe: React.FC<{ at: number; color: string; x?: string; y?: string; length?: number; children?: React.ReactNode }> = ({
  at,
  color,
  x = '50%',
  y = '0%',
  length = 22,
  children,
}) => {
  const frame = useCurrentFrame();
  if (frame < at) return null;
  const p = ramp(frame, at, at + length, SMOOTH);
  return (
    <AbsoluteFill style={{ clipPath: `circle(${p * 150}% at ${x} ${y})` }}>
      <AbsoluteFill style={{ background: color }} />
      {children}
    </AbsoluteFill>
  );
};

/** A small caption under a headline. */
export const Caption: React.FC<{ text: string; delay?: number; size?: number; color?: string; style?: React.CSSProperties }> = ({ text, delay = 0, size = 34, color = 'rgba(255,255,255,0.6)', style }) => {
  const p = useSpring(delay, { damping: 18 });
  return (
    <div style={{ font: `500 ${size}px/1.3 ${sans}`, color, opacity: p, transform: `translateY(${(1 - p) * 20}px)`, letterSpacing: -0.3, ...style }}>{text}</div>
  );
};
