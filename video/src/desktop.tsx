import React from 'react';
import { AbsoluteFill } from 'remotion';
import { mono, sans } from './theme';

/** A flat wallpaper: one colour with a few large, hard-edged shapes. */
export const Wallpaper: React.FC<{ shift?: number }> = ({ shift = 0 }) => (
  <AbsoluteFill style={{ background: '#2f3a4f', overflow: 'hidden' }}>
    <div style={{ position: 'absolute', width: 1400, height: 1400, borderRadius: '50%', background: '#36445c', left: -500 + shift * 20, top: 300 }} />
    <div style={{ position: 'absolute', width: 900, height: 900, borderRadius: '50%', background: '#3d4d68', right: -300 - shift * 20, top: -400 }} />
  </AbsoluteFill>
);

export const MenuBar: React.FC = () => (
  <div
    style={{
      position: 'absolute',
      top: 0,
      left: 0,
      right: 0,
      height: 32,
      display: 'flex',
      alignItems: 'center',
      padding: '0 18px',
      gap: 22,
      background: 'rgba(0, 0, 0, 0.25)',
      color: 'rgba(255,255,255,0.92)',
      font: `500 13.5px ${sans}`,
    }}
  >
    <span style={{ fontSize: 16 }}></span>
    <span style={{ fontWeight: 700 }}>Ghostty</span>
    <span>File</span>
    <span>Edit</span>
    <span>View</span>
    <span>Window</span>
    <span style={{ flex: 1 }} />
    <span>Mon 12 Oct  9:41</span>
  </div>
);

const codeLines: [string, string][] = [
  ['#c678dd', 'export function useTheme() {'],
  ['#e5c07b', "  const [theme, setTheme] = useState<'light' | 'dark'>('dark');"],
  ['#abb2bf', '  useEffect(() => {'],
  ['#98c379', "    document.documentElement.dataset.theme = theme;"],
  ['#abb2bf', '  }, [theme]);'],
  ['#61afef', '  return { theme, toggle: () => setTheme(flip) };'],
  ['#c678dd', '}'],
];

/** Editor and terminal windows, so the notch sits on a believable working desktop. */
export const DesktopWindows: React.FC<{ frame: number }> = ({ frame }) => (
  <>
    <div
      style={{
        position: 'absolute',
        left: 90,
        top: 110,
        width: 880,
        height: 620,
        borderRadius: 12,
        background: 'rgba(28, 30, 36, 0.96)',
        boxShadow: '0 40px 120px rgba(0,0,0,0.55)',
        overflow: 'hidden',
        border: '1px solid rgba(255,255,255,0.08)',
      }}
    >
      <div style={{ height: 36, display: 'flex', alignItems: 'center', gap: 8, padding: '0 14px', background: 'rgba(255,255,255,0.03)' }}>
        {['#ff5f57', '#febc2e', '#28c840'].map((c) => (
          <div key={c} style={{ width: 12, height: 12, borderRadius: 6, background: c }} />
        ))}
        <span style={{ marginLeft: 16, font: `13px ${sans}`, color: 'rgba(255,255,255,0.5)' }}>Theme.tsx — web-app</span>
      </div>
      <div style={{ padding: '22px 26px', font: `16px/1.9 ${mono}` }}>
        {codeLines.map(([c, l], i) => (
          <div key={i} style={{ color: c, whiteSpace: 'pre' }}>
            <span style={{ color: 'rgba(255,255,255,0.2)', marginRight: 22 }}>{String(i + 12).padStart(2, ' ')}</span>
            {l}
          </div>
        ))}
      </div>
    </div>
    <div
      style={{
        position: 'absolute',
        left: 1010,
        top: 300,
        width: 820,
        height: 560,
        borderRadius: 12,
        background: 'rgba(14, 14, 18, 0.95)',
        boxShadow: '0 40px 120px rgba(0,0,0,0.6)',
        overflow: 'hidden',
        border: '1px solid rgba(255,255,255,0.08)',
      }}
    >
      <div style={{ height: 36, display: 'flex', alignItems: 'center', gap: 8, padding: '0 14px' }}>
        {['#ff5f57', '#febc2e', '#28c840'].map((c) => (
          <div key={c} style={{ width: 12, height: 12, borderRadius: 6, background: c }} />
        ))}
        <span style={{ marginLeft: 16, font: `13px ${sans}`, color: 'rgba(255,255,255,0.5)' }}>claude — api-server</span>
      </div>
      <div style={{ padding: '18px 22px', font: `16px/1.8 ${mono}`, color: 'rgba(255,255,255,0.85)' }}>
        <div style={{ color: 'rgb(232,140,102)' }}>✻ Claude Code</div>
        <div>&gt; Fix the failing auth tests</div>
        <div style={{ color: 'rgba(255,255,255,0.55)' }}>⏺ Bash(npm test -- auth)</div>
        <div style={{ color: 'rgba(255,255,255,0.55)' }}>  ⎿ 2 failed, 31 passed</div>
        <div style={{ color: 'rgba(255,255,255,0.55)' }}>⏺ Update(src/auth/token.ts)</div>
        <div style={{ color: 'rgb(232,140,102)' }}>✶ {['Thinking', 'Thinking.', 'Thinking..', 'Thinking…'][Math.floor(frame / 6) % 4]}</div>
      </div>
    </div>
  </>
);
