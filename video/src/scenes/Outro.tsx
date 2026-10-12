import React from 'react';
import { AbsoluteFill, Audio, Easing, Sequence, spring, staticFile, useCurrentFrame, useVideoConfig } from 'remotion';
import { Caption, SMOOTH, Stage, Words, ramp, useT } from '../anim';
import { CharacterStyle } from '../characters';
import { CTA_URL } from '../config';
import { PipLogo } from '../logo';
import { Palette, mono, sans } from '../theme';

const CYCLE: (CharacterStyle | 'brand')[] = ['livingNotch', 'blob', 'pixel', 'minimal', 'livingNotch', 'blob', 'pixel', 'minimal'];
const STEP = 5;
const LAND = 12 + CYCLE.length * STEP;
const SLIDE = LAND + 12;

/** The icon flips through every character, lands on its own eyes, and the name arrives beside it. */
export const Outro: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const t = useT(40);
  const pop = spring({ frame, fps, config: { damping: 12, stiffness: 180, mass: 0.6 } });
  const i = Math.floor((frame - 12) / STEP);
  const character = frame < 12 || i >= CYCLE.length ? 'brand' : CYCLE[i];
  const stepAge = frame >= LAND ? frame - LAND : (frame - 12) % STEP;
  const squash = frame >= 12 ? Math.max(0, 1 - stepAge / (frame >= LAND ? 10 : STEP)) * (frame >= LAND ? 1 : 0.5) : 0;
  const slide = ramp(frame, SLIDE, SLIDE + 18, SMOOTH);
  const gaze = { x: ramp(frame, SLIDE + 10, SLIDE + 18) * (1 - ramp(frame, 140, 148)), y: 0 };
  const fade = ramp(frame, 166, 178);
  return (
    <Stage bg="#1b1b1e">
      <AbsoluteFill style={{ justifyContent: 'center', alignItems: 'center' }}>
        <div style={{ display: 'flex', alignItems: 'center', transform: `translateX(${(1 - slide) * 330}px)` }}>
          <div style={{ transform: `scale(${pop * (1 - 0.35 * slide)})`, marginRight: 70 * slide }}>
            <PipLogo size={430} t={t} character={character} mood={character === 'brand' ? 'idle' : 'finished'} gaze={gaze} squash={squash} />
          </div>
          <div style={{ opacity: slide, width: 760 * slide, overflow: 'hidden', whiteSpace: 'nowrap' }}>
            {frame >= SLIDE && (
              <>
                <Words text="Pip" delay={SLIDE + 2} size={230} align="left" />
                <Caption text="Your AI agents, at a glance." delay={SLIDE + 10} size={50} color="#fff" style={{ fontWeight: 700, marginTop: -6 }} />
              </>
            )}
          </div>
        </div>
      </AbsoluteFill>
      <AbsoluteFill style={{ justifyContent: 'flex-end', alignItems: 'center', paddingBottom: 110 }}>
        <div style={{ display: 'flex', gap: 16, opacity: ramp(frame, SLIDE + 22, SLIDE + 30), transform: `translateY(${(1 - ramp(frame, SLIDE + 22, SLIDE + 32)) * 30}px)` }}>
          {['Free & open source', 'macOS 14+', '32 agents', '4 personalities'].map((s, k) => (
            <div key={s} style={{ padding: '14px 26px', borderRadius: 14, background: k === 0 ? Palette.cyan : '#0b0b0c', border: `2px solid ${k === 0 ? Palette.cyan : '#2a2a2e'}`, font: `700 26px ${sans}`, color: k === 0 ? '#000' : '#fff' }}>
              {s}
            </div>
          ))}
        </div>
        {CTA_URL && <div style={{ marginTop: 28, font: `600 30px ${mono}`, color: Palette.cyan, opacity: ramp(frame, SLIDE + 30, SLIDE + 38) }}>{CTA_URL}</div>}
      </AbsoluteFill>
      {CYCLE.map((_, k) => (
        <Sequence key={k} from={12 + k * STEP} durationInFrames={6}>
          <Audio src={staticFile('audio/click.wav')} volume={0.6} />
        </Sequence>
      ))}
      <Sequence from={LAND}>
        <Audio src={staticFile('audio/pop.wav')} volume={0.9} />
      </Sequence>
      <AbsoluteFill style={{ background: '#000', opacity: fade }} />
    </Stage>
  );
};
