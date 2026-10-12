import React from 'react';
import { AbsoluteFill, Audio, Sequence, staticFile, useCurrentFrame } from 'remotion';
import { Caption, Stage, Wipe, Words, bump, ramp, useSpring, useT } from '../anim';
import { Icon, Notch, PanelBody, PillButton } from '../notch';
import { Palette, mono, sans } from '../theme';

const HALF = 90;
const CHIP_AT = 40;
const PICK_AT = HALF + 52;

const Chip: React.FC<{ label: string; active?: number }> = ({ label, active = 0 }) => (
  <div
    style={{
      padding: '3.5px 8px',
      borderRadius: 6,
      font: `500 11px ${sans}`,
      color: Palette.cyan,
      background: Palette.badgeBg,
      border: `1px solid ${active ? Palette.cyan : Palette.darkCardBorder}`,
      transform: `scale(${1 + 0.12 * active})`,
      whiteSpace: 'nowrap',
    }}
  >
    {label}
  </div>
);

const PlanCard: React.FC<{ frame: number }> = ({ frame }) => {
  const typed = '+ Add tests'.slice(0, Math.max(0, Math.floor((frame - CHIP_AT) / 1.5)));
  const hasFeedback = typed.length > 0;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
      <div style={{ font: `600 15px ${sans}`, color: '#fff' }}>Review the plan</div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        <span style={{ font: `500 11px ${mono}`, color: Palette.quiet }}>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5 }}>
            <Icon name="doc" size={11} color={Palette.cyan} /> Markdown Plan Preview
          </span>
        </span>
        <span style={{ flex: 1 }} />
        <span style={{ font: `500 10.5px ${sans}`, color: Palette.quiet, padding: '3px 7px', borderRadius: 5, background: 'rgba(255,255,255,0.06)', display: 'flex', alignItems: 'center', gap: 4 }}>
          <Icon name="copy" size={10} /> Copy
        </span>
        <span style={{ font: `500 10.5px ${sans}`, color: Palette.cyan, padding: '3px 7px', borderRadius: 5, background: Palette.badgeBg, display: 'flex', alignItems: 'center', gap: 4 }}>
          <Icon name="expand" size={10} /> Expand
        </span>
      </div>
      <div
        style={{
          padding: 11,
          borderRadius: 10,
          background: 'rgb(10, 15, 20)',
          border: '1px solid rgba(255,255,255,0.12)',
          color: 'rgba(255,255,255,0.9)',
          font: `12.5px/1.5 ${sans}`,
          height: 168,
          overflow: 'hidden',
        }}
      >
        <div style={{ font: `700 16px ${sans}`, marginBottom: 6 }}>Dark Mode &amp; Theming</div>
        {[
          [true, 'Configure theme color tokens'],
          [false, 'Add dark mode toggle in the header'],
          [false, 'Save the preference to local storage'],
        ].map(([done, label], i) => (
          <div key={i} style={{ display: 'flex', gap: 7, alignItems: 'center' }}>
            <span
              style={{
                width: 12,
                height: 12,
                borderRadius: 3,
                border: `1.5px solid ${done ? Palette.green : 'rgba(255,255,255,0.35)'}`,
                background: done ? Palette.green : 'transparent',
                color: '#000',
                fontSize: 9,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
              }}
            >
              {done ? <Icon name="check" size={9} color="#000" /> : null}
            </span>
            <span style={{ opacity: done ? 0.6 : 1, textDecoration: done ? 'line-through' : undefined }}>{label as string}</span>
          </div>
        ))}
        <div style={{ marginTop: 8, padding: '7px 9px', borderRadius: 6, background: 'rgba(255,255,255,0.05)', font: `11px/1.55 ${mono}` }}>
          <div>
            <span style={{ color: '#c678dd' }}>export function</span> <span style={{ color: '#61afef' }}>useTheme</span>() {'{'}
          </div>
          <div>
            {'  '}
            <span style={{ color: '#c678dd' }}>const</span> [theme, setTheme] = <span style={{ color: '#61afef' }}>useState</span>(<span style={{ color: '#98c379' }}>'dark'</span>);
          </div>
        </div>
      </div>
      <div style={{ display: 'flex', gap: 6 }}>
        <Chip label="+ Add tests" active={bump(frame, CHIP_AT - 2, CHIP_AT + 8)} />
        <Chip label="Simplify approach" />
        <Chip label="Security & edge cases" />
        <Chip label="+ Add docs" />
      </div>
      <div
        style={{
          padding: '8px 11px',
          borderRadius: 10,
          border: `1px solid ${hasFeedback ? 'rgba(56,212,245,0.6)' : 'rgba(255,255,255,0.15)'}`,
          font: `12.5px ${sans}`,
          color: hasFeedback ? '#fff' : 'rgba(255,255,255,0.35)',
        }}
      >
        {hasFeedback ? typed : 'What should change? (type to revise without leaving notch)'}
      </div>
      <div style={{ display: 'flex', gap: 8 }}>
        {hasFeedback ? <PillButton title="Send Feedback" shortcut="⌘↩" prominent pressed={bump(frame, 70, 80)} /> : <PillButton title="Keep planning" shortcut="⌃⌥⌫" />}
        <PillButton title="Approve plan" shortcut="⌃⌥↩" prominent={!hasFeedback} />
      </div>
    </div>
  );
};

const QuestionCard: React.FC<{ frame: number }> = ({ frame }) => {
  const options = [
    ['Vercel', 'Preview deploys for every pull request'],
    ['Fly.io', 'Close to the database, one region'],
    ['Docker on a VPS', 'Full control, more to maintain'],
  ];
  const picked = frame >= PICK_AT ? 1 : -1;
  const press = bump(frame, PICK_AT - 2, PICK_AT + 8);
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 9 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, font: `600 12.5px ${sans}`, color: Palette.cyan }}>
        <Icon name="bubble" size={13} color={Palette.cyan} />
        <span>Claude Code asks</span>
        <span style={{ flex: 1 }} />
        <span style={{ font: `11px ${mono}`, color: Palette.quiet }}>api-server</span>
      </div>
      <div style={{ font: `600 15px ${sans}`, color: '#fff' }}>Which deployment target?</div>
      {options.map(([title, detail], i) => {
        const sel = picked === i;
        return (
          <div
            key={i}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: 10,
              padding: '9px 11px',
              borderRadius: 10,
              background: sel ? 'rgba(56,212,245,0.14)' : Palette.darkCard,
              border: `1px solid ${sel ? Palette.cyan : Palette.darkCardBorder}`,
              transform: `scale(${sel ? 1 + 0.03 * press : 1})`,
            }}
          >
            <div
              style={{
                width: 20,
                height: 20,
                borderRadius: 6,
                background: sel ? Palette.cyan : Palette.badgeBg,
                color: sel ? '#000' : Palette.cyan,
                font: `700 11px ${sans}`,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
              }}
            >
              {i + 1}
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ font: `600 13px ${sans}`, color: '#fff' }}>{title}</div>
              <div style={{ font: `11px ${sans}`, color: Palette.quiet }}>{detail}</div>
            </div>
            <span style={{ font: `500 10.5px ${sans}`, color: Palette.quiet }}>⌘{i + 1}</span>
          </div>
        );
      })}
      <div style={{ padding: '8px 11px', borderRadius: 10, border: '1px solid rgba(255,255,255,0.15)', font: `12.5px ${sans}`, color: 'rgba(255,255,255,0.35)' }}>Or type your own answer…</div>
    </div>
  );
};

const FLOOD_AT = HALF - 6;

/** Plans with real Markdown and one-click feedback, then a question answered with ⌘2. */
export const Review: React.FC = () => {
  const frame = useCurrentFrame();
  const t = useT(14);
  const second = frame >= HALF;
  const enter = useSpring(0, { damping: 16 });
  const swap = useSpring(HALF - 4, { damping: 18, stiffness: 120 });
  const planOut = ramp(frame, HALF - 8, HALF + 4);
  return (
    <Stage bg="#1b1b1e">
      <Copy frame={frame} dark={false} />
      <Wipe at={FLOOD_AT} color={Palette.cyan} x="25%" y="0%" length={26}>
        <Copy frame={frame} dark />
      </Wipe>
      <AbsoluteFill style={{ right: 860, left: 0, width: 'auto', alignItems: 'center', transform: `translateY(${(1 - enter) * -60}px)` }}>
        <div style={{ zoom: 1.68 }}>
          <Notch
            open={1}
            openHeight={502 - 114 * swap}
            panel={
              <PanelBody summary={second ? '1 question · 2 working' : '1 plan to review · 2 working'} style="blob" mood="needsYou" t={t}>
                <div style={{ position: 'relative' }}>
                  {frame < HALF + 6 && (
                    <div style={{ position: second ? 'absolute' : 'relative', inset: 0, opacity: 1 - planOut, transform: `translateY(${-planOut * 24}px)` }}>
                      <PlanCard frame={frame} />
                    </div>
                  )}
                  {frame >= HALF - 4 && (
                    <div style={{ position: second ? 'relative' : 'absolute', inset: 0, opacity: swap, transform: `translateY(${(1 - swap) * 24}px)` }}>
                      <QuestionCard frame={frame} />
                    </div>
                  )}
                </div>
              </PanelBody>
            }
          />
        </div>
      </AbsoluteFill>
      <Sequence from={CHIP_AT} durationInFrames={10}>
        <Audio src={staticFile('audio/click.wav')} />
      </Sequence>
      <Sequence from={FLOOD_AT}>
        <Audio src={staticFile('audio/whoosh.wav')} volume={0.6} />
      </Sequence>
      <Sequence from={PICK_AT} durationInFrames={10}>
        <Audio src={staticFile('audio/click.wav')} />
      </Sequence>
      <Sequence from={PICK_AT + 2}>
        <Audio src={staticFile('audio/pop.wav')} volume={0.7} />
      </Sequence>
    </Stage>
  );
};

/** The headlines on the right. Rendered twice: light on the dark stage, dark inside the cyan flood. */
const Copy: React.FC<{ frame: number; dark: boolean }> = ({ frame, dark }) => (
  <AbsoluteFill style={{ left: 1100, right: 80, width: 'auto', justifyContent: 'center' }}>
    {frame < HALF ? (
      <>
        <Words text="Review plans." delay={6} size={104} align="left" exitAt={HALF - 10} color={dark ? '#000' : '#fff'} highlight={{ plans: dark ? '#000' : Palette.cyan }} />
        <Caption
          text="Full Markdown, one-click feedback chips, approve with ⌃⌥↩."
          delay={16}
          size={34}
          color={dark ? 'rgba(0,0,0,0.7)' : 'rgba(255,255,255,0.6)'}
          style={{ marginTop: 22, opacity: 1 - ramp(frame, HALF - 12, HALF - 2) }}
        />
      </>
    ) : (
      <>
        <Words text="Answer questions." delay={HALF + 6} size={104} align="left" color={dark ? '#000' : '#fff'} />
        <Caption text="Pick an option with ⌘1 ⌘2 ⌘3, or type your own." delay={HALF + 16} size={34} color={dark ? 'rgba(0,0,0,0.7)' : 'rgba(255,255,255,0.6)'} style={{ marginTop: 22 }} />
      </>
    )}
  </AbsoluteFill>
);
