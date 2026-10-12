import React from 'react';
import { AbsoluteFill, Audio, Sequence, staticFile, useCurrentFrame } from 'remotion';
import { Stage, Words, ramp, useSpring, useT } from '../anim';
import { CompactEars, EarIndicator, Notch } from '../notch';
import { Palette } from '../theme';

/** Black screen; the hardware notch wakes up, grows ears and opens its eyes. */
export const Hook: React.FC = () => {
  const frame = useCurrentFrame();
  const t = useT();
  const grow = useSpring(14, { damping: 15, stiffness: 120 });
  const awake = frame >= 30;
  const helloP = (frame - 30) / 18;
  // Look around, then down at the headline.
  const gx = frame < 52 ? 0 : frame < 70 ? -ramp(frame, 52, 58) : frame < 92 ? -1 + 2 * ramp(frame, 70, 76) : 1 - ramp(frame, 92, 98);
  const gy = frame < 92 ? 0 : ramp(frame, 92, 98);
  const zoom = 5.2 - 0.25 * ramp(frame, 0, 120);
  return (
    <Stage bg={frame < 12 ? '#000' : '#1b1b1e'}>
      <AbsoluteFill style={{ alignItems: 'center' }}>
        <div style={{ zoom, marginTop: 0 }}>
          <Notch
            grow={grow}
            compact={
              <CompactEars
                style="livingNotch"
                mood={awake ? 'idle' : 'asleep'}
                t={t + 2.3}
                reaction={awake && helloP < 1 ? { kind: 'hello', progress: helloP } : undefined}
                gaze={{ x: gx, y: gy }}
                right={awake ? <EarIndicator mood="idle" t={t} sessions={5} /> : null}
              />
            }
          />
        </div>
      </AbsoluteFill>
      <AbsoluteFill style={{ justifyContent: 'center', alignItems: 'center', paddingTop: 220 }}>
        <Words text="Your notch" delay={40} size={150} exitAt={112} />
        <Words
          text="has eyes."
          delay={56}
          size={150}
          exitAt={112}
          highlight={{ eyes: Palette.cyan }}
        />
      </AbsoluteFill>
      <Sequence from={30}>
        <Audio src={staticFile('audio/pop.wav')} volume={0.8} />
      </Sequence>
    </Stage>
  );
};
