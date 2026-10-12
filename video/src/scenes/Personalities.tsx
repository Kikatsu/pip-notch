import React from 'react';
import { AbsoluteFill, Audio, Easing, Sequence, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig } from 'remotion';
import { SMOOTH, Stage, Words, ramp } from '../anim';
import { CHARACTER_TITLES, Character, CharacterStyle, largeSize } from '../characters';
import { notchPath } from '../notch';
import { BEAT, Mood, Palette, mono, sans } from '../theme';

const INTRO = 2 * BEAT;
const EACH = 3 * BEAT;
const ORDER: CharacterStyle[] = ['livingNotch', 'blob', 'pixel', 'minimal'];
const GRID_AT = INTRO + EACH * ORDER.length;
/** Each switch spins the reel this many slots, so it reads as a slot machine and still lands on the next character. */
const SPIN = 5;

const LOOK: Record<CharacterStyle, { bg: string; ink: string; sound?: string }> = {
  livingNotch: { bg: Palette.cyan, ink: '#000', sound: 'pip-approval' },
  blob: { bg: 'rgb(240, 138, 74)', ink: '#000', sound: 'soft-finished' },
  pixel: { bg: 'rgb(166, 140, 250)', ink: '#000', sound: 'arcade-approval' },
  minimal: { bg: '#f2f2f0', ink: '#000' },
};

const SHOW_W = 980;
const SHOW_H = 400;

const zoomFor = (s: CharacterStyle, height: number) => (height * 0.62) / largeSize(s).h / (s === 'livingNotch' || s === 'minimal' ? 1.9 : 1);

/** Each character runs through a few moods while it's on screen, so you see its range. */
const moodFor = (local: number): Mood => (local < 15 ? 'working' : local < 30 ? 'needsYou' : 'finished');

export const Personalities: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const idx = Math.max(0, Math.min(ORDER.length - 1, Math.floor((frame - INTRO) / EACH)));
  const style = ORDER[idx];
  const inGrid = frame >= GRID_AT;
  const local = frame - INTRO - idx * EACH;

  // Reel position in slots. During the intro it free-spins; afterwards each switch springs SPIN slots on.
  const intro = frame < INTRO;
  const reel = intro
    ? (frame / INTRO) * 14 - 14
    : ORDER.reduce((acc, _, k) => (k === 0 ? acc : acc + SPIN * spring({ frame: frame - (INTRO + EACH * k), fps, config: { damping: 13, stiffness: 120, mass: 0.8 } })), 0);
  const settled = intro ? 0 : Math.abs(reel - Math.round(reel));

  const sel = ORDER.reduce((acc, _, k) => acc + (k === 0 ? 0 : spring({ frame: frame - (INTRO + EACH * k - 3), fps, config: { damping: 15, stiffness: 200 } })), 0);

  return (
    <Stage bg="#1b1b1e">
      {!intro &&
        !inGrid &&
        ORDER.map((s, k) => {
          const at = INTRO + EACH * k;
          if (frame < at) return null;
          const p = ramp(frame, at - 2, at + 14, SMOOTH);
          return <AbsoluteFill key={s} style={{ background: LOOK[s].bg, clipPath: `inset(0 ${(1 - p) * 100}% 0 0)` }} />;
        })}

      {!intro && !inGrid && <Marquee text={CHARACTER_TITLES[style].title} local={frame - INTRO} />}

      {!inGrid && (
        <AbsoluteFill style={{ alignItems: 'center' }}>
          <div style={{ position: 'relative', width: SHOW_W, height: SHOW_H }}>
            <svg width={SHOW_W} height={SHOW_H} style={{ position: 'absolute', inset: 0 }}>
              <path d={notchPath(SHOW_W, SHOW_H, 30, 100)} fill="#000" />
            </svg>
            <div style={{ position: 'absolute', left: 30, right: 30, top: 0, bottom: 0, overflow: 'hidden', borderRadius: '0 0 70px 70px' }}>
              {[-1, 0, 1].map((o) => {
                const n = Math.floor(reel) + o;
                const s = ORDER[((n % 4) + 4) % 4];
                const y = (n - reel) * SHOW_H;
                const speed = intro ? 1 : Math.min(1, settled * 4);
                return (
                  <div
                    key={n}
                    style={{
                      position: 'absolute',
                      inset: 0,
                      transform: `translateY(${y}px)`,
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      filter: speed > 0.05 ? `blur(${speed * 6}px)` : undefined,
                    }}
                  >
                    <Character style={s} mood={intro ? 'idle' : moodFor(local)} t={frame / fps} large zoom={zoomFor(s, SHOW_H)} />
                  </div>
                );
              })}
            </div>
          </div>
        </AbsoluteFill>
      )}

      {intro && (
        <AbsoluteFill style={{ justifyContent: 'flex-end', alignItems: 'center', paddingBottom: 200 }}>
          <Words text="Pick a personality." delay={0} size={150} exitAt={INTRO - 4} />
        </AbsoluteFill>
      )}

      {!intro && !inGrid && (
        <AbsoluteFill style={{ justifyContent: 'flex-end', padding: '0 120px 90px' }}>
          <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between' }}>
            <div key={style}>
              <div style={{ font: `700 22px ${mono}`, letterSpacing: 5, color: 'rgba(0,0,0,0.55)', marginBottom: 8 }}>0{idx + 1} / 04</div>
              <Words text={CHARACTER_TITLES[style].title} delay={INTRO + EACH * idx + 4} size={128} color="#000" align="left" />
              <div style={{ font: `600 34px ${sans}`, color: 'rgba(0,0,0,0.65)', marginTop: 8, opacity: ramp(local, 8, 14) }}>{CHARACTER_TITLES[style].subtitle}</div>
            </div>
            <Picker sel={sel} frame={frame} />
          </div>
        </AbsoluteFill>
      )}

      {inGrid && <Grid local={frame - GRID_AT} />}

      {ORDER.map((s, k) => (
        <React.Fragment key={s}>
          <Sequence from={INTRO + EACH * k - 3} durationInFrames={8}>
            <Audio src={staticFile('audio/click.wav')} volume={0.9} />
          </Sequence>
          <Sequence from={INTRO + EACH * k}>
            <Audio src={staticFile('audio/whoosh.wav')} volume={0.5} />
          </Sequence>
          {LOOK[s].sound && (
            <Sequence from={INTRO + EACH * k + 15}>
              <Audio src={staticFile(`audio/${LOOK[s].sound}.wav`)} volume={0.55} />
            </Sequence>
          )}
        </React.Fragment>
      ))}
      <Sequence from={GRID_AT}>
        <Audio src={staticFile('audio/whoosh.wav')} volume={0.7} />
      </Sequence>
    </Stage>
  );
};

/** The character's name, huge, scrolling across the background in two rows. */
const Marquee: React.FC<{ text: string; local: number }> = ({ text, local }) => {
  const row = (dir: number, top: number) => (
    <div
      style={{
        position: 'absolute',
        top,
        left: 0,
        whiteSpace: 'nowrap',
        font: `900 300px/1 ${sans}`,
        letterSpacing: -12,
        color: 'rgba(0,0,0,0.09)',
        transform: `translateX(${dir > 0 ? -1200 + local * 9 : -local * 9}px)`,
      }}
    >
      {Array.from({ length: 6 }, () => text.toUpperCase()).join('  ·  ')}
    </div>
  );
  return (
    <AbsoluteFill>
      {row(1, 300)}
      {row(-1, 600)}
    </AbsoluteFill>
  );
};

const SEG_W = 190;

/** The real setting: a segmented control, with a pointer clicking the next option. */
const Picker: React.FC<{ sel: number; frame: number }> = ({ sel, frame }) => {
  const targets = ORDER.map((_, k) => INTRO + EACH * k - 3);
  const xs = ORDER.map((_, k) => k * SEG_W + SEG_W * 0.55);
  const x = interpolate(frame, targets.flatMap((f) => [f - 10, f]), xs.flatMap((v, k) => [xs[Math.max(0, k - 1)], v]), {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.bezier(0.3, 0, 0.2, 1),
  });
  const pressed = targets.some((f) => frame >= f && frame < f + 4);
  return (
    <div style={{ position: 'relative', marginBottom: 10 }}>
      <div style={{ font: `700 18px ${mono}`, letterSpacing: 4, color: 'rgba(0,0,0,0.55)', marginBottom: 12 }}>SETTINGS · CHARACTER</div>
      <div style={{ position: 'relative', display: 'flex', background: '#000', borderRadius: 22, padding: 6 }}>
        <div style={{ position: 'absolute', top: 6, left: 6 + sel * SEG_W, width: SEG_W, height: 60, borderRadius: 16, background: '#fff' }} />
        {ORDER.map((s, k) => {
          const active = Math.round(sel) === k;
          return (
            <div key={s} style={{ position: 'relative', width: SEG_W, height: 60, display: 'flex', alignItems: 'center', justifyContent: 'center', font: `700 22px ${sans}`, color: active ? '#000' : 'rgba(255,255,255,0.6)' }}>
              {CHARACTER_TITLES[s].title}
            </div>
          );
        })}
      </div>
      <svg width={34} height={44} viewBox="0 0 17 22" style={{ position: 'absolute', left: x, top: 72, transform: `scale(${pressed ? 0.85 : 1})` }}>
        <path d="M1 1L1 17L5 13.2L7.8 19.5L10.4 18.4L7.7 12.3L13 12.3Z" fill="#000" stroke="#fff" strokeWidth={1.3} strokeLinejoin="round" />
      </svg>
    </div>
  );
};

const GRID_MOODS: Mood[] = ['working', 'needsYou', 'error', 'finished', 'finished', 'idle'];

/** Four colour columns drop in, each with its own notch, all reacting together on the beat. */
const Grid: React.FC<{ local: number }> = ({ local }) => {
  const { fps } = useVideoConfig();
  const mood = GRID_MOODS[Math.min(GRID_MOODS.length - 1, Math.floor(local / BEAT))];
  const slab = ramp(local, 12, 26, SMOOTH);
  return (
    <AbsoluteFill>
      <div style={{ display: 'flex', height: '100%' }}>
        {ORDER.map((s, k) => {
          const p = spring({ frame: local - k * 3, fps, config: { damping: 15, stiffness: 160 } });
          const beatPop = spring({ frame: local % BEAT, fps, config: { damping: 9, stiffness: 300, mass: 0.4 } });
          return (
            <div key={s} style={{ position: 'relative', flex: 1, background: LOOK[s].bg, transform: `translateY(${(1 - p) * -1100}px)`, display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
              <div style={{ position: 'relative', width: 400, height: 250, transform: `scale(${0.97 + 0.03 * beatPop})`, transformOrigin: '50% 0%' }}>
                <svg width={400} height={250} style={{ position: 'absolute', left: 0, top: 0 }}>
                  <path d={notchPath(400, 250, 20, 60)} fill="#000" />
                </svg>
                <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                  <Character style={s} mood={mood} t={local / fps + k * 0.3} large zoom={zoomFor(s, 250)} />
                </div>
              </div>
              <div style={{ position: 'absolute', bottom: 80, font: `800 46px ${sans}`, letterSpacing: -1.5, color: LOOK[s].ink }}>{CHARACTER_TITLES[s].title}</div>
            </div>
          );
        })}
      </div>
      <AbsoluteFill style={{ justifyContent: 'center', alignItems: 'center', paddingTop: 120 }}>
        <div style={{ background: '#000', padding: '34px 70px', transform: `scaleX(${slab})` }}>
          <div style={{ opacity: slab }}>
            <Words text="Four personalities. Switch anytime." delay={18} size={92} />
          </div>
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
