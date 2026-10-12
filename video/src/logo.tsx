import React from 'react';
import { Character, CharacterStyle, Eyes, largeSize } from './characters';
import { notchPath } from './notch';
import { Mood, Palette } from './theme';

/**
 * The app icon drawn live: a dark tile with the notch hanging from its top edge.
 * The notch holds cyan eyes by default, or any character.
 */
export const PipLogo: React.FC<{ size: number; t: number; character?: CharacterStyle | 'brand'; mood?: Mood; gaze?: { x: number; y: number }; squash?: number }> = ({
  size,
  t,
  character = 'brand',
  mood = 'idle',
  gaze = { x: 0, y: 0 },
  squash = 0,
}) => {
  // Notch occupies the top half of a 100 x 100 tile.
  const nx = 20;
  const nw = 60;
  const nh = 46;
  return (
    <svg width={size} height={size} viewBox="0 0 100 100" style={{ display: 'block', overflow: 'visible', transform: `scale(${1 + squash * 0.12}, ${1 - squash * 0.1})` }}>
      <rect x={1} y={1} width={98} height={98} rx={23} fill="#111214" />
      <rect x={1} y={1} width={98} height={98} rx={23} fill="none" stroke="#2a2c30" strokeWidth={1.2} />
      <g transform={`translate(${nx} 1)`}>
        <path d={notchPath(nw, nh, 0.01, 15)} fill="#000" />
        {character === 'brand' ? (
          <g transform={`translate(${gaze.x * 3} ${gaze.y * 2})`}>
            <BrandEyes t={t} mood={mood} w={nw} h={nh} />
          </g>
        ) : (
          <foreignObject x={0} y={0} width={nw} height={nh}>
            <div style={{ width: nw, height: nh, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <Character style={character} mood={mood} t={t} large zoom={(character === 'livingNotch' || character === 'minimal' ? 46 : 40) / largeSize(character).w} gaze={gaze} />
            </div>
          </foreignObject>
        )}
      </g>
    </svg>
  );
};

/** The icon's tall capsule eyes, with a blink every few seconds. */
const BrandEyes: React.FC<{ t: number; mood: Mood; w: number; h: number }> = ({ t, mood, w, h }) => {
  if (mood !== 'idle') return <Eyes mood={mood} t={t} W={w} H={h} w={9} color={Palette.cyan} pupil="#000" />;
  const phase = t % 3.2;
  const blink = phase < 0.12 ? 0.15 : 1;
  const ew = 9.5;
  const eh = 16 * blink;
  return (
    <g>
      {[w / 2 - 10.5, w / 2 + 10.5].map((cx) => (
        <g key={cx}>
          <rect x={cx - ew / 2} y={h / 2 - eh / 2} width={ew} height={eh} rx={ew / 2} fill={Palette.cyan} />
          {blink === 1 && <circle cx={cx + 1.2} cy={h / 2 - 4.2} r={1.9} fill="#e8fbff" />}
        </g>
      ))}
    </g>
  );
};
