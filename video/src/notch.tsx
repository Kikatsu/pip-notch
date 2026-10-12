// The notch UI rebuilt in HTML/SVG at the app's point sizes. Wrap in <Zoom> to blow it up crisply.
import React from 'react';
import { Character, CharacterStyle, largeSize, Reaction } from './characters';
import { Agent, Mood, Palette, mono, rounded, sans } from './theme';

export const NOTCH_W = 185;
export const NOTCH_H = 32;
export const EAR_W = 44;
export const EXPANDED_W = 500;

const lerp = (a: number, b: number, p: number) => a + (b - a) * p;

export const Zoom: React.FC<{ zoom: number; children: React.ReactNode; style?: React.CSSProperties }> = ({ zoom, children, style }) => (
  <div style={{ zoom, ...style }}>{children}</div>
);

export const notchPath = (W: number, H: number, tr: number, brIn: number) => {
  const br = Math.min(brIn, H / 2, (W - 2 * tr) / 2);
  return [
    `M0 0`,
    `Q${tr} 0 ${tr} ${tr}`,
    `L${tr} ${H - br}`,
    `Q${tr} ${H} ${tr + br} ${H}`,
    `L${W - tr - br} ${H}`,
    `Q${W - tr} ${H} ${W - tr} ${H - br}`,
    `L${W - tr} ${tr}`,
    `Q${W - tr} 0 ${W} 0`,
    'Z',
  ].join(' ');
};

export const compactWidth = (extraEar = 0) => NOTCH_W + 2 * (EAR_W + extraEar) + 12;

type NotchProps = {
  /** 0 = compact, 1 = open panel. */
  open?: number;
  openHeight?: number;
  /** 0 = the bare hardware notch (nothing running), 1 = ears out. */
  grow?: number;
  compact?: React.ReactNode;
  panel?: React.ReactNode;
  extraEar?: number;
};

/** The black notch silhouette, morphing from the compact ears to the open panel. */
export const Notch: React.FC<NotchProps> = ({ open = 0, openHeight = 200, compact, panel, extraEar = 0, grow = 1 }) => {
  const cw = lerp(NOTCH_W, compactWidth(extraEar), grow);
  const W = lerp(cw, EXPANDED_W + 24, open);
  const H = lerp(NOTCH_H, openHeight, open);
  const tr = lerp(6, 12, open);
  const br = lerp(10, 26, open);
  return (
    <div style={{ position: 'relative', width: W, height: H }}>
      <svg width={W} height={H} style={{ position: 'absolute', inset: 0, overflow: 'visible' }}>
        <path d={notchPath(W, H, tr, br)} fill="#000" />
      </svg>
      {open < 1 && compact && (
        <div
          style={{
            position: 'absolute',
            left: (W - compactWidth(extraEar)) / 2 + 6,
            top: 0,
            height: NOTCH_H,
            width: compactWidth(extraEar) - 12,
            opacity: (1 - Math.min(1, open * 3)) * Math.min(1, grow * 1.5),
            display: 'flex',
            clipPath: `inset(0 ${(compactWidth(extraEar) - cw) / 2}px)`,
          }}
        >
          {compact}
        </div>
      )}
      {open > 0 && panel && (
        <div
          style={{
            position: 'absolute',
            left: (W - EXPANDED_W) / 2,
            top: 0,
            width: EXPANDED_W,
            height: H,
            overflow: 'hidden',
            opacity: Math.max(0, (open - 0.35) / 0.65),
            transform: `scale(${lerp(0.96, 1, open)})`,
            transformOrigin: 'top center',
          }}
        >
          {panel}
        </div>
      )}
    </div>
  );
};

/** Left ear face, hardware gap, right ear indicator. */
export const CompactEars: React.FC<{ style: CharacterStyle; mood: Mood; t: number; right?: React.ReactNode; reaction?: Reaction; gaze?: { x: number; y: number }; extraEar?: number }> = ({
  style,
  mood,
  t,
  right,
  reaction,
  gaze,
  extraEar = 0,
}) => (
  <>
    <div style={{ width: EAR_W + extraEar, height: NOTCH_H, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      <Character style={style} mood={mood} t={t} reaction={reaction} gaze={gaze} />
    </div>
    <div style={{ width: NOTCH_W }} />
    <div style={{ width: EAR_W + extraEar, height: NOTCH_H, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 7 }}>{right}</div>
  </>
);

const pulse = (t: number, delay: number) => (Math.sin(((t - delay) * 2 * Math.PI) / 1.2) + 1) / 2;

export const EarIndicator: React.FC<{ mood: Mood; t: number; working?: number; sessions?: number }> = ({ mood, t, working = 1, sessions = 1 }) => {
  switch (mood) {
    case 'working':
      return (
        <div style={{ display: 'flex', alignItems: 'center', gap: 3 }}>
          {working > 1 && <span style={{ font: `600 11px ${rounded}`, color: '#fff', marginRight: 1 }}>{working}</span>}
          {[0, 1, 2].map((i) => (
            <div key={i} style={{ width: 4, height: 4, borderRadius: 2, background: '#fff', opacity: 0.25 + 0.75 * pulse(t, i * 0.2) }} />
          ))}
        </div>
      );
    case 'needsYou': {
      const p = (t * 0.85) % 1;
      return (
        <div style={{ position: 'relative', width: 7, height: 7 }}>
          <div style={{ position: 'absolute', inset: 0, borderRadius: 4, background: Palette.amber, transform: `scale(${1 + 1.6 * p})`, opacity: 1 - p }} />
          <div style={{ position: 'absolute', inset: 0, borderRadius: 4, background: Palette.amber }} />
        </div>
      );
    }
    case 'error':
      return <div style={{ width: 7, height: 7, borderRadius: 4, background: Palette.red }} />;
    case 'rateLimited':
      return <div style={{ width: 7, height: 7, borderRadius: 4, background: Palette.amber, opacity: 0.6 }} />;
    case 'finished':
      return (
        <Icon name="check" size={11} color={Palette.green} />
      );
    case 'idle':
      return <span style={{ font: `500 10px ${rounded}`, color: 'rgba(255,255,255,0.45)' }}>{sessions}</span>;
    default:
      return null;
  }
};

export const AgentBadge: React.FC<{ agent: Agent; scale?: number }> = ({ agent, scale = 1 }) => (
  <div
    style={{
      width: 20 * scale,
      height: 14 * scale,
      borderRadius: 4 * scale,
      background: agent.tint.replace('rgb', 'rgba').replace(')', ', 0.18)'),
      color: agent.tint,
      font: `800 ${8.5 * scale}px ${rounded}`,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      flexShrink: 0,
      letterSpacing: 0.2 * scale,
    }}
  >
    {agent.initials}
  </div>
);

export const stateColor = (state: 'working' | 'needsInput' | 'finished' | 'error' | 'idle') =>
  ({ working: '#fff', needsInput: Palette.amber, finished: Palette.green, error: Palette.red, idle: Palette.quiet })[state];

export const SessionRow: React.FC<{
  project: string;
  agent: Agent;
  agentLabel?: string;
  branch?: string;
  state: 'working' | 'needsInput' | 'finished' | 'error' | 'idle';
  status: string;
  elapsed?: string;
  highlight?: number;
}> = ({ project, agent, agentLabel, branch, state, status, elapsed, highlight = 0 }) => (
  <div style={{ display: 'flex', alignItems: 'center', padding: '7px 10px', borderRadius: 10, background: `rgba(255,255,255,${0.08 * highlight})` }}>
    <div style={{ width: 7, height: 7, borderRadius: 4, background: stateColor(state), marginRight: 10, flexShrink: 0 }} />
    <div style={{ flex: 1, minWidth: 0 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, whiteSpace: 'nowrap' }}>
        <span style={{ font: `600 13px ${sans}`, color: '#fff' }}>{project}</span>
        <AgentBadge agent={agent} />
        {branch && (
          <span style={{ font: `10.5px ${mono}`, color: Palette.quiet, display: 'flex', alignItems: 'center', gap: 3 }}>
            <Icon name="branch" size={10} /> {branch}
          </span>
        )}
        <span style={{ font: `11px ${sans}`, color: Palette.quiet }}>{agentLabel ?? agent.name}</span>
      </div>
      <div style={{ font: `11.5px ${sans}`, color: Palette.quiet, marginTop: 2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{status}</div>
    </div>
    {elapsed && <span style={{ font: `11px ${mono}`, color: Palette.quiet, marginLeft: 8 }}>{elapsed}</span>}
  </div>
);

export const PillButton: React.FC<{ title: string; shortcut?: string; prominent?: boolean; pressed?: number }> = ({ title, shortcut, prominent, pressed = 0 }) => (
  <div
    style={{
      flex: 1,
      height: 36,
      borderRadius: 18,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      gap: 6,
      background: prominent ? `rgba(255,255,255,${1 - 0.2 * pressed})` : `rgba(255,255,255,${0.13 + 0.1 * pressed})`,
      color: prominent ? '#000' : '#fff',
      transform: `scale(${1 - 0.05 * pressed})`,
      boxShadow: prominent && pressed > 0 ? `0 0 ${24 * pressed}px rgba(255,255,255,${0.5 * pressed})` : undefined,
    }}
  >
    <span style={{ font: `600 14px ${sans}` }}>{title}</span>
    {shortcut && <span style={{ font: `500 10.5px ${sans}`, opacity: 0.5 }}>{shortcut}</span>}
  </div>
);

export const PanelHeader: React.FC<{ summary: string }> = ({ summary }) => (
  <div style={{ height: NOTCH_H, display: 'flex', alignItems: 'center', padding: '0 14px' }}>
    <div style={{ flex: 1, font: `500 12px ${sans}`, color: Palette.quiet, whiteSpace: 'nowrap' }}>{summary}</div>
    <div style={{ width: NOTCH_W }} />
    <div style={{ flex: 1, display: 'flex', justifyContent: 'flex-end', alignItems: 'center', gap: 16, paddingRight: 8 }}>
      <svg width={14} height={12} viewBox="0 0 14 12">
        <path d="M1 4h2.5L7 1v10L3.5 8H1z" fill={Palette.quiet} />
        <path d="M9.5 3.5q1.6 2.5 0 5M11.5 2q2.8 4 0 8" stroke={Palette.quiet} strokeWidth={1.4} fill="none" strokeLinecap="round" />
      </svg>
      <svg width={13} height={13} viewBox="-7 -7 14 14">
        {[0, 45, 90, 135].map((a) => (
          <rect key={a} x={-1.6} y={-6.5} width={3.2} height={13} rx={1} fill={Palette.quiet} transform={`rotate(${a})`} />
        ))}
        <circle r={4.6} fill={Palette.quiet} />
        <circle r={2} fill="#000" />
      </svg>
    </div>
  </div>
);

/** The open panel's column: header, big face, then whatever the scene shows. */
export const PanelBody: React.FC<{ summary: string; style: CharacterStyle; mood: Mood; t: number; reaction?: Reaction; gaze?: { x: number; y: number }; children?: React.ReactNode }> = ({
  summary,
  style,
  mood,
  t,
  reaction,
  gaze,
  children,
}) => {
  const face = largeSize(style);
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'stretch' }}>
      <PanelHeader summary={summary} />
      {style !== 'minimal' && (
        <div style={{ display: 'flex', justifyContent: 'center', marginTop: 10 }}>
          <div style={{ width: face.w, height: face.h }}>
            <Character style={style} mood={mood} t={t} large reaction={reaction} gaze={gaze} />
          </div>
        </div>
      )}
      <div style={{ padding: '10px 14px 16px', display: 'flex', flexDirection: 'column', gap: 10 }}>{children}</div>
    </div>
  );
};

const ringTint = (p: number) => (p < 60 ? Palette.green : p < 85 ? Palette.amber : Palette.red);

export const LimitRing: React.FC<{ label: string; percent: number; reset: string; size?: number }> = ({ label, percent, reset, size = 30 }) => {
  const r = (size - 3.5) / 2;
  const c = 2 * Math.PI * r;
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 8, flex: 1 }}>
      <div style={{ position: 'relative', width: size, height: size }}>
        <svg width={size} height={size} style={{ transform: 'rotate(-90deg)' }}>
          <circle cx={size / 2} cy={size / 2} r={r} stroke="rgba(255,255,255,0.1)" strokeWidth={3.5} fill="none" />
          <circle
            cx={size / 2}
            cy={size / 2}
            r={r}
            stroke={ringTint(percent)}
            strokeWidth={3.5}
            fill="none"
            strokeLinecap="round"
            strokeDasharray={`${(c * Math.min(percent, 100)) / 100} ${c}`}
          />
        </svg>
        <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', font: `700 10.5px ${rounded}`, color: '#fff' }}>
          {Math.round(percent)}
        </div>
      </div>
      <div>
        <div style={{ font: `600 11px ${sans}`, color: '#fff', whiteSpace: 'nowrap' }}>{label}</div>
        <div style={{ font: `10px ${sans}`, color: Palette.quiet, whiteSpace: 'nowrap' }}>{reset}</div>
      </div>
    </div>
  );
};

export const MiniRing: React.FC<{ percent: number }> = ({ percent }) => {
  const r = 4.5;
  const c = 2 * Math.PI * r;
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
      <svg width={11} height={11} style={{ transform: 'rotate(-90deg)' }}>
        <circle cx={5.5} cy={5.5} r={r} stroke="rgba(255,255,255,0.15)" strokeWidth={2} fill="none" />
        <circle cx={5.5} cy={5.5} r={r} stroke={ringTint(percent)} strokeWidth={2} fill="none" strokeLinecap="round" strokeDasharray={`${(c * percent) / 100} ${c}`} />
      </svg>
      <span style={{ font: `600 10px ${rounded}`, color: 'rgba(255,255,255,0.9)' }}>{Math.round(percent)}%</span>
    </div>
  );
};

export const Keycap: React.FC<{ label: string; pressed?: number; size?: number; color?: string }> = ({ label, pressed = 0, size = 64, color = '#fff' }) => (
  <div
    style={{
      position: 'relative',
      width: size,
      height: size,
      borderRadius: size * 0.2,
      background: '#1a1a1c',
      border: '2px solid #3a3a3e',
      boxShadow: `0 ${8 * (1 - pressed)}px 0 #0c0c0d`,
      transform: `translateY(${8 * pressed}px)`,
      overflow: 'hidden',
    }}
  >
    <div style={{ position: 'absolute', inset: -2, background: color, opacity: pressed }} />
    <div
      style={{
        position: 'absolute',
        inset: 0,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        font: `600 ${size * 0.42}px ${sans}`,
        color: pressed > 0.5 ? (color === '#fff' ? '#000' : '#fff') : '#fff',
      }}
    >
      {label}
    </div>
  </div>
);

/** Small drawn icons, in place of emoji. */
export const Icon: React.FC<{ name: 'warning' | 'check' | 'bubble' | 'doc' | 'copy' | 'expand' | 'branch'; size?: number; color?: string }> = ({ name, size = 12, color = 'currentColor' }) => {
  const common = { fill: 'none', stroke: color, strokeWidth: 1.6, strokeLinecap: 'round' as const, strokeLinejoin: 'round' as const };
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" style={{ display: 'inline-block', flexShrink: 0, verticalAlign: 'middle' }}>
      {name === 'warning' && (
        <>
          <path d="M8 2L15 14H1Z" {...common} />
          <path d="M8 6.5V9.5M8 11.8V12" {...common} />
        </>
      )}
      {name === 'check' && <path d="M2.5 8.5L6.3 12L13.5 4" {...common} strokeWidth={2.2} />}
      {name === 'bubble' && <path d="M2 3.5h12v7.5H7l-3.5 3v-3H2Z" fill={color} stroke="none" />}
      {name === 'doc' && <path d="M4 1.5h5.5L12.5 4.5V14.5H4ZM6 7.5h4.5M6 10h4.5" {...common} />}
      {name === 'copy' && <path d="M5.5 5.5h8v8h-8ZM3 10.5V2.5h8" {...common} />}
      {name === 'expand' && <path d="M9.5 2.5h4v4M6.5 13.5h-4v-4M13.5 2.5L9 7M2.5 13.5L7 9" {...common} />}
      {name === 'branch' && <path d="M5 2.5v11M5 9.5c0-3 6-2 6-5M11 2.5v2" {...common} />}
    </svg>
  );
};
