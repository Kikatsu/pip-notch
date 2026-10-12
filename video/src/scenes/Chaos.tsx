import React from 'react';
import { AbsoluteFill, Audio, Easing, Sequence, spring, staticFile, useCurrentFrame, useVideoConfig } from 'remotion';
import { Stage, Words, ramp } from '../anim';
import { AgentBadge } from '../notch';
import { Palette, agent, mono, sans } from '../theme';

type Win = { x: number; y: number; r: number; at: number; agent: string; title: string; lines: string[]; asks?: boolean };

const WINDOWS: Win[] = [
  { x: 120, y: 90, r: -3, at: 0, agent: 'CC', title: 'api-server', lines: ['⏺ Running npm test -- auth', '  ✓ login.spec.ts (12)', '  ✗ refresh.spec.ts (2 failed)', '⏺ Reading src/auth/token.ts'] },
  { x: 1240, y: 120, r: 2.5, at: 7, agent: 'CX', title: 'web-app', lines: ['• Editing src/Theme.tsx', '• Added useTheme hook', '• Running pnpm lint', '  0 problems'] },
  { x: 640, y: 520, r: 1.5, at: 15, agent: 'CU', title: 'mobile', lines: ['Agent › Refactor navigation', '  ▸ app/routes.ts +42 −18', '  ▸ app/tabs.tsx +9 −3', 'Thinking…'] },
  { x: 60, y: 600, r: 2, at: 22, agent: 'GM', title: 'infra', lines: ['✦ terraform plan', '  + aws_s3_bucket.assets', '  ~ aws_lambda.resize', 'Plan: 1 to add, 1 to change'] },
  { x: 1300, y: 600, r: -2.5, at: 30, agent: 'CC', title: 'payments', asks: true, lines: ['⏺ Bash(rm -rf dist && npm run build)', '', ' Do you want to proceed?', ' ❯ 1. Yes   2. No'] },
  { x: 700, y: 60, r: -1.5, at: 37, agent: 'AG', title: 'docs', lines: ['▶ Generating API reference', '  42 / 118 pages', '▶ Writing guides/theming.md', ''] },
  { x: 380, y: 330, r: 3.5, at: 45, agent: 'WS', title: 'ml-pipeline', lines: ['Cascade › Fix flaky test', '  pytest -k loader', '  1 failed, 23 passed', 'Retrying…'] },
];

const TerminalWindow: React.FC<{ w: Win; frame: number; fps: number }> = ({ w, frame, fps }) => {
  const a = agent(w.agent);
  const p = spring({ frame: frame - w.at, fps, config: { damping: 12, stiffness: 180, mass: 0.6 } });
  // Everything gets sucked into the notch at the end.
  const suck = ramp(frame, 92 + (w.at % 4), 112, Easing.in(Easing.cubic));
  const cx = 960 - (w.x + 260);
  const cy = -60 - (w.y + 150);
  const shown = Math.floor(Math.max(0, frame - w.at) / 5);
  const alert = w.asks && frame > w.at + 10 ? 0.5 + 0.5 * Math.sin(frame * 0.5) : 0;
  return (
    <div
      style={{
        position: 'absolute',
        left: w.x,
        top: w.y,
        width: 520,
        height: 300,
        borderRadius: 14,
        background: 'rgba(22, 22, 26, 0.94)',
        border: alert ? `4px solid ${alert > 0.5 ? Palette.amber : 'rgba(245,158,10,0.35)'}` : '1.5px solid rgba(255,255,255,0.1)',
        boxShadow: '0 30px 80px rgba(0,0,0,0.6)',
        transform: `translate(${cx * suck}px, ${cy * suck}px) rotate(${w.r * (1 - suck)}deg) scale(${(0.6 + 0.4 * p) * (1 - 0.95 * suck)})`,
        opacity: Math.min(1, p * 2) * (1 - suck * 0.6),
        overflow: 'hidden',
        filter: `blur(${suck * 6}px)`,
      }}
    >
      <div style={{ height: 38, display: 'flex', alignItems: 'center', gap: 8, padding: '0 14px', borderBottom: '1px solid rgba(255,255,255,0.06)' }}>
        {['#ff5f57', '#febc2e', '#28c840'].map((c) => (
          <div key={c} style={{ width: 12, height: 12, borderRadius: 6, background: c }} />
        ))}
        <div style={{ flex: 1, display: 'flex', justifyContent: 'center', alignItems: 'center', gap: 8, marginRight: 50 }}>
          <AgentBadge agent={a} scale={1.2} />
          <span style={{ font: `600 15px ${sans}`, color: 'rgba(255,255,255,0.75)' }}>
            {a.name} — {w.title}
          </span>
        </div>
      </div>
      <div style={{ padding: '16px 18px', font: `17px/1.65 ${mono}`, color: 'rgba(255,255,255,0.82)' }}>
        {w.lines.slice(0, shown).map((l, i) => (
          <div key={i} style={{ color: l.includes('✗') || l.includes('failed') ? Palette.red : l.includes('✓') ? Palette.green : l.includes('proceed') || l.includes('❯') ? Palette.amber : undefined, whiteSpace: 'pre' }}>
            {l || ' '}
          </div>
        ))}
        {shown < w.lines.length + 1 && <span style={{ display: 'inline-block', width: 10, height: 20, background: 'rgba(255,255,255,0.7)', opacity: frame % 16 < 8 ? 1 : 0 }} />}
      </div>
    </div>
  );
};

export const Chaos: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const shake = frame > 30 && frame < 90 ? Math.sin(frame * 1.7) * 2 : 0;
  return (
    <Stage bg="#0e0e10">
      <AbsoluteFill style={{ transform: `translate(${shake}px, ${-shake}px)` }}>
        {WINDOWS.map((w, i) => (
          <TerminalWindow key={i} w={w} frame={frame} fps={fps} />
        ))}
      </AbsoluteFill>
      <AbsoluteFill
        style={{
          justifyContent: 'center',
          alignItems: 'center',
          background: `radial-gradient(45% 35% at 50% 50%, rgba(5,5,7,${0.85 * ramp(frame, 8, 20) * (1 - ramp(frame, 92, 104))}) 0%, transparent 100%)`,
        }}
      >
        {frame < 58 && <Words text="Seven agents. Seven terminals." delay={12} size={104} exitAt={50} style={{ maxWidth: 1300 }} />}
        {frame >= 52 && <Words text="Which one needs you?" delay={56} size={120} exitAt={94} highlight={{ needs: Palette.amber, you: Palette.amber }} />}
      </AbsoluteFill>
      {WINDOWS.map((w, i) => (
        <Sequence key={i} from={w.at} durationInFrames={10}>
          <Audio src={staticFile('audio/click.wav')} volume={0.5} />
        </Sequence>
      ))}
      <Sequence from={88}>
        <Audio src={staticFile('audio/whoosh.wav')} volume={0.9} />
      </Sequence>
    </Stage>
  );
};

