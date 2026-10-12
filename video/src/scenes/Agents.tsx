import React from 'react';
import { AbsoluteFill, spring, useCurrentFrame, useVideoConfig } from 'remotion';
import { Stage, ramp } from '../anim';
import { AgentBadge } from '../notch';
import { AGENTS, Agent, Palette, mono, sans } from '../theme';

const ROWS = 4;
const SPEED = [7, -9, 8, -6];

const Chip: React.FC<{ a: Agent }> = ({ a }) => (
  <div
    style={{
      display: 'flex',
      alignItems: 'center',
      gap: 16,
      padding: '18px 30px 18px 20px',
      borderRadius: 22,
      background: a.tested ? '#fff' : '#0b0b0c',
      border: `2px solid ${a.tested ? '#fff' : '#2a2a2e'}`,
      flexShrink: 0,
    }}
  >
    <AgentBadge agent={a} scale={2.4} />
    <span style={{ font: `700 34px ${sans}`, color: a.tested ? '#000' : '#fff', letterSpacing: -0.5, whiteSpace: 'nowrap' }}>{a.name}</span>
    {a.tested && <span style={{ font: `700 15px ${mono}`, letterSpacing: 2, color: '#000', background: Palette.cyan, padding: '5px 9px', borderRadius: 8 }}>TESTED</span>}
  </div>
);

/** Four rows of agents streaming past in opposite directions, behind a counter that slams to 32. */
export const Agents: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const count = Math.round(32 * ramp(frame, 6, 40));
  const slam = spring({ frame: frame - 40, fps, config: { damping: 8, stiffness: 300, mass: 0.5 } });
  const rows = Array.from({ length: ROWS }, (_, r) => AGENTS.filter((_, i) => i % ROWS === r));
  return (
    <Stage bg="#1b1b1e">
      <AbsoluteFill style={{ justifyContent: 'center', gap: 26 }}>
        {rows.map((list, r) => {
          const enter = spring({ frame: frame - r * 3, fps, config: { damping: 16, stiffness: 140 } });
          const x = (SPEED[r] > 0 ? -1800 : 0) + frame * SPEED[r] + (1 - enter) * (SPEED[r] > 0 ? -900 : 900);
          return (
            <div key={r} style={{ display: 'flex', gap: 22, transform: `translateX(${x}px)` }}>
              {[...list, ...list, ...list].map((a, i) => (
                <Chip key={i} a={a} />
              ))}
            </div>
          );
        })}
      </AbsoluteFill>
      <AbsoluteFill style={{ justifyContent: 'center', alignItems: 'center' }}>
        <div style={{ background: Palette.cyan, padding: '30px 70px 38px', transform: `rotate(-2deg) scale(${0.9 + 0.1 * Math.min(1, slam)})`, display: 'flex', alignItems: 'baseline', gap: 28 }}>
          <span style={{ font: `900 200px/0.9 ${sans}`, letterSpacing: -10, color: '#000', fontVariantNumeric: 'tabular-nums', minWidth: 250, textAlign: 'right' }}>{count}</span>
          <span style={{ font: `800 84px/1 ${sans}`, letterSpacing: -3, color: '#000' }}>
            agents.
            <br />
            One notch.
          </span>
        </div>
      </AbsoluteFill>
    </Stage>
  );
};
