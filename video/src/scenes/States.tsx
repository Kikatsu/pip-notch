import React from 'react';
import { AbsoluteFill, Audio, Sequence, interpolateColors, staticFile, useCurrentFrame } from 'remotion';
import { Caption, Stage, Words, ramp, useSpring, useT } from '../anim';
import { CompactEars, EarIndicator, Notch } from '../notch';
import { BEAT, Mood, Palette, moodColor, mono } from '../theme';

/** Two beats per mood: four moods in two bars. */
const EACH = BEAT * 2;

const BEATS: { mood: Mood; word: string; caption: string; tint: string; sound?: string; from: 'left' | 'right' }[] = [
  { mood: 'working', word: 'Working.', caption: 'Eyes scan while your agents work.', tint: '#121318', from: 'left' },
  { mood: 'needsYou', word: 'Needs you.', caption: 'They widen when one wants approval.', tint: '#1f1606', sound: 'pip-approval', from: 'right' },
  { mood: 'error', word: 'Broke.', caption: 'Crossed out when something fails.', tint: '#200c0c', sound: 'pip-error', from: 'left' },
  { mood: 'finished', word: 'Shipped.', caption: 'A happy squint when it’s done.', tint: '#08190f', sound: 'pip-finished', from: 'right' },
];

/** The notch huge on screen, one word per mood, a quick cut on every other beat. */
export const States: React.FC = () => {
  const frame = useCurrentFrame();
  const i = Math.min(BEATS.length - 1, Math.floor(frame / EACH));
  const local = frame - i * EACH;
  // The background eases into each mood's tint instead of cutting.
  const bg = interpolateColors(
    frame,
    BEATS.flatMap((_, k) => [k * EACH, k * EACH + 8]),
    BEATS.flatMap((b, k) => [k === 0 ? b.tint : BEATS[k - 1].tint, b.tint]),
  );
  return (
    <Stage bg={bg}>
      {BEATS.map((beat, k) => (
        <Sequence key={k} from={k * EACH} durationInFrames={EACH}>
          <Beat beat={beat} index={k} />
          {beat.sound && <Audio src={staticFile(`audio/${beat.sound}.wav`)} volume={0.85} />}
        </Sequence>
      ))}
      <AbsoluteFill style={{ justifyContent: 'flex-end', alignItems: 'center', paddingBottom: 60 }}>
        <div style={{ display: 'flex', gap: 14 }}>
          {BEATS.map((beat, k) => {
            const on = k === i ? ramp(local, 0, 8) : k === i - 1 ? 1 - ramp(local, 0, 8) : 0;
            return <div key={k} style={{ width: 14 + 46 * on, height: 6, borderRadius: 3, background: on > 0.5 ? moodColor[beat.mood] : 'rgba(255,255,255,0.2)' }} />;
          })}
        </div>
      </AbsoluteFill>
    </Stage>
  );
};

const Beat: React.FC<{ beat: (typeof BEATS)[number]; index: number }> = ({ beat, index }) => {
  const frame = useCurrentFrame();
  const t = useT(index * 2 + 1);
  const pop = useSpring(0, { damping: 10, stiffness: 240, mass: 0.5 });
  const slide = useSpring(0, { damping: 16, stiffness: 190 });
  const dir = beat.from === 'left' ? -1 : 1;
  const zoom = 4.6 + 0.3 * pop - 0.15 * ramp(frame, 0, EACH);
  const color = moodColor[beat.mood] === '#ffffff' ? '#fff' : moodColor[beat.mood];
  return (
    <AbsoluteFill>
      <AbsoluteFill style={{ alignItems: 'center', transform: `translateY(${(1 - pop) * -24}px)` }}>
        <div style={{ zoom }}>
          <Notch compact={<CompactEars style="livingNotch" mood={beat.mood} t={t} right={<EarIndicator mood={beat.mood} t={t} working={3} />} />} />
        </div>
      </AbsoluteFill>
      <AbsoluteFill style={{ justifyContent: 'center', alignItems: 'center', paddingTop: 260 }}>
        <div style={{ font: `600 22px ${mono}`, letterSpacing: 4, textTransform: 'uppercase', color: color === '#fff' ? Palette.quiet : color, opacity: slide, marginBottom: 18 }}>
          0{index + 1} — {beat.mood === 'needsYou' ? 'needs you' : beat.mood === 'finished' ? 'done' : beat.mood}
        </div>
        <div style={{ transform: `translateX(${dir * (1 - slide) * 220}px)` }}>
          <Words text={beat.word} delay={0} stagger={2} size={200} exitAt={index === BEATS.length - 1 ? undefined : EACH - 8} color={color} />
        </div>
        <Caption text={beat.caption} delay={4} size={40} style={{ marginTop: 18 }} />
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
