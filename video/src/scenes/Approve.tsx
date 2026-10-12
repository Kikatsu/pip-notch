import React from 'react';
import { AbsoluteFill, Audio, Sequence, staticFile, useCurrentFrame } from 'remotion';
import { Caption, Stage, Wipe, Words, bump, ramp, useSpring, useT } from '../anim';
import { AgentBadge, CompactEars, EarIndicator, Icon, Keycap, Notch, PanelBody, PillButton, SessionRow } from '../notch';
import { Palette, agent, mono, sans } from '../theme';

const PRESS = { ctrl: 84, opt: 90, ret: 98 };
const APPROVED = 104;

export const ToolApproval: React.FC<{ allowPressed: number }> = ({ allowPressed }) => (
  <div style={{ display: 'flex', flexDirection: 'column', gap: 9 }}>
    <div style={{ display: 'flex', alignItems: 'center', gap: 7, font: `11px ${mono}`, color: Palette.quiet }}>
      <div style={{ width: 7, height: 7, borderRadius: 4, background: Palette.amber }} />
      <AgentBadge agent={agent('CC')} />
      <span>Claude Code · payments</span>
    </div>
    <div style={{ font: `600 15px ${sans}`, color: '#fff' }}>Bash</div>
    <div
      style={{
        padding: '7px 10px',
        borderRadius: 8,
        background: 'rgba(245,158,10,0.12)',
        border: `1px solid ${Palette.amber}`,
        font: `600 11.5px ${sans}`,
        color: Palette.amber,
        display: 'flex',
        alignItems: 'center',
        gap: 6,
      }}
    >
      <Icon name="warning" size={13} color={Palette.amber} /> Caution: Deletes files recursively
    </div>
    <div style={{ padding: '9px 11px', borderRadius: 10, background: Palette.faint, font: `12px ${mono}`, color: 'rgba(255,255,255,0.92)' }}>rm -rf dist &amp;&amp; npm run build</div>
    <div style={{ display: 'flex', gap: 8, marginTop: 2 }}>
      <PillButton title="Deny" shortcut="⌃⌥⌫" />
      <PillButton title="Allow" shortcut="⌃⌥↩" prominent pressed={allowPressed} />
    </div>
  </div>
);

/** An agent asks; you approve from the keyboard without leaving your editor. */
export const Approve: React.FC = () => {
  const frame = useCurrentFrame();
  const t = useT(9);
  const open = useSpring(8, { damping: 16, stiffness: 150 });
  const done = frame >= APPROVED;
  const swap = ramp(frame, APPROVED + 18, APPROVED + 30);
  const openHeight = 300 - 38 * swap;
  const allow = bump(frame, PRESS.ret, PRESS.ret + 10);
  const reactP = (frame - APPROVED) / 24;
  const mood = done ? 'working' : 'needsYou';
  const enter = useSpring(0, { damping: 18 });
  return (
    <Stage bg="#1b1b1e">
      <Copy frame={frame} dark={false} />
      <Wipe at={APPROVED} color={Palette.green} x="70%" y="0%" length={24}>
        <Copy frame={frame} dark />
      </Wipe>
      <AbsoluteFill style={{ left: 830, width: 'auto', alignItems: 'center', transform: `translateY(${(1 - enter) * -80}px)` }}>
        <div style={{ zoom: 2.05 }}>
          <Notch
            open={open}
            openHeight={openHeight}
            compact={<CompactEars style="pixel" mood="needsYou" t={t} right={<EarIndicator mood="needsYou" t={t} />} />}
            panel={
              <PanelBody
                summary={done ? '3 working' : '1 needs you · 2 working'}
                style="pixel"
                mood={mood}
                t={t}
                reaction={reactP >= 0 && reactP < 1 ? { kind: 'approve', progress: reactP } : undefined}
              >
                <div style={{ position: 'relative' }}>
                  <div style={{ opacity: 1 - swap, transform: `translateY(${-swap * 20}px)`, position: swap > 0 ? 'absolute' : 'relative', inset: 0 }}>
                    <ToolApproval allowPressed={allow} />
                  </div>
                  {swap > 0 && (
                    <div style={{ opacity: swap, transform: `translateY(${(1 - swap) * 20}px)` }}>
                      <SessionRow project="payments" agent={agent('CC')} state="working" status="Bash: npm run build" elapsed="0:03" highlight={0.6 * (1 - swap) + 0.4} />
                      <SessionRow project="web-app" agent={agent('CX')} branch="dark-mode" state="working" status="Edit: src/Theme.tsx" elapsed="2:41" />
                      <SessionRow project="api-server" agent={agent('CU')} state="working" status="Working on: Fix the failing auth tests" elapsed="5:12" />
                    </div>
                  )}
                </div>
              </PanelBody>
            }
          />
        </div>
      </AbsoluteFill>

      <Sequence from={4}>
        <Audio src={staticFile('audio/pip-approval.wav')} volume={0.8} />
      </Sequence>
      {Object.values(PRESS).map((f) => (
        <Sequence key={f} from={f} durationInFrames={8}>
          <Audio src={staticFile('audio/click.wav')} volume={0.9} />
        </Sequence>
      ))}
      <Sequence from={APPROVED}>
        <Audio src={staticFile('audio/pop.wav')} volume={0.8} />
      </Sequence>
    </Stage>
  );
};

/** The headline and keycaps. Rendered twice: light on the dark stage, and dark inside the green flood. */
const Copy: React.FC<{ frame: number; dark: boolean }> = ({ frame, dark }) => {
  const ink = dark ? '#000' : '#fff';
  const allowed = ramp(frame, APPROVED + 2, APPROVED + 14);
  return (
    <AbsoluteFill style={{ width: 900, padding: '0 0 0 120px', justifyContent: 'center' }}>
      <Words text="Approve it from the notch." delay={14} size={96} align="left" color={ink} highlight={{ notch: dark ? '#000' : Palette.amber }} />
      <Caption text="Allow or deny without leaving your editor. Risky commands are flagged." delay={26} size={34} color={dark ? 'rgba(0,0,0,0.7)' : 'rgba(255,255,255,0.6)'} style={{ marginTop: 26, maxWidth: 680 }} />
      <div style={{ display: 'flex', gap: 18, marginTop: 56, opacity: ramp(frame, 58, 72), transform: `translateY(${(1 - ramp(frame, 58, 74)) * 30}px)` }}>
        {(['ctrl', 'opt', 'ret'] as const).map((k) => (
          <Keycap key={k} label={{ ctrl: '⌃', opt: '⌥', ret: '↩' }[k]} pressed={bumpHold(frame, PRESS[k], APPROVED + 8)} size={92} color={dark ? '#000' : '#fff'} />
        ))}
        <div style={{ alignSelf: 'center', marginLeft: 18, font: `700 34px ${sans}`, color: ink, opacity: allowed, transform: `translateX(${(1 - allowed) * -20}px)`, display: 'flex', alignItems: 'center', gap: 10 }}>
          Allowed <Icon name="check" size={30} color={dark ? '#000' : Palette.green} />
        </div>
      </div>
    </AbsoluteFill>
  );
};

/** A key going down over 3 frames, held, then released over 5. */
const bumpHold = (frame: number, down: number, up: number) => ramp(frame, down, down + 3) * (1 - ramp(frame, up, up + 5));
