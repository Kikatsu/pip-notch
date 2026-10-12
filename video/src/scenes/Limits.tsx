import React from 'react';
import { AbsoluteFill, useCurrentFrame } from 'remotion';
import { Caption, Stage, Wipe, Words, ramp, useSpring, useT } from '../anim';
import { CompactEars, EarIndicator, LimitRing, MiniRing, Notch, PanelBody, SessionRow } from '../notch';
import { Palette, agent } from '../theme';

const LIMITS = [
  { label: 'Claude 5h', to: 62, reset: 'resets in 1h 48m' },
  { label: 'Claude week', to: 34, reset: 'resets in 3d 4h' },
  { label: 'Codex 5h', to: 88, reset: 'resets in 26m' },
  { label: 'Codex week', to: 21, reset: 'resets in 5d 2h' },
];

/** Plan limits as rings filling green → amber → red, then the fullest one in the closed notch. */
export const Limits: React.FC = () => {
  const frame = useCurrentFrame();
  const t = useT(30);
  const enter = useSpring(0, { damping: 16 });
  const close = useSpring(84, { damping: 16, stiffness: 140 });
  const fill = (k: number) => ramp(frame, 10 + k * 5, 52 + k * 5);
  return (
    <Stage bg="#1b1b1e">
      <Copy dark={false} />
      <Wipe at={84} color={Palette.red} y="0%" length={24}>
        <Copy dark />
      </Wipe>
      <AbsoluteFill style={{ alignItems: 'center', transform: `translateY(${(1 - enter) * -60}px)` }}>
        <div style={{ zoom: 2.05 - 0.3 * close + 1.6 * close }}>
          <Notch
            open={1 - close}
            openHeight={314}
            extraEar={40 * close}
            compact={
              <CompactEars style="pixel" mood="working" t={t} extraEar={40} right={<><MiniRing percent={88} /><EarIndicator mood="working" t={t} working={2} /></>} />
            }
            panel={
              <PanelBody summary="2 working" style="pixel" mood="working" t={t}>
                <div style={{ display: 'flex', gap: 12, padding: '9px 10px', borderRadius: 12, background: Palette.faint }}>
                  {LIMITS.map((l, k) => (
                    <LimitRing key={l.label} label={l.label} percent={l.to * fill(k)} reset={l.reset} />
                  ))}
                </div>
                <div>
                  <SessionRow project="web-app" agent={agent('CC')} state="working" status="Edit: src/Theme.tsx" elapsed="2:41" />
                  <SessionRow project="api-server" agent={agent('CX')} state="working" status="Bash: pnpm test" elapsed="0:58" />
                </div>
              </PanelBody>
            }
          />
        </div>
      </AbsoluteFill>
    </Stage>
  );
};

/** The headline, light on dark and again dark inside the red flood. */
const Copy: React.FC<{ dark: boolean }> = ({ dark }) => (
  <AbsoluteFill style={{ justifyContent: 'flex-end', alignItems: 'center', paddingBottom: 150 }}>
    <Words text="Know your limits." delay={20} size={120} color={dark ? '#000' : '#fff'} highlight={{ limits: dark ? '#000' : Palette.amber }} />
    <Caption text="Claude Code and Codex plan usage, with time until each resets." delay={30} size={36} color={dark ? 'rgba(0,0,0,0.7)' : 'rgba(255,255,255,0.6)'} style={{ marginTop: 18 }} />
  </AbsoluteFill>
);
