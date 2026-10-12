import React from 'react';
import { AbsoluteFill, Audio, Sequence, interpolate, staticFile } from 'remotion';
import { Camera } from './anim';
import { Agents } from './scenes/Agents';
import { Approve } from './scenes/Approve';
import { Chaos } from './scenes/Chaos';
import { Hook } from './scenes/Hook';
import { Limits } from './scenes/Limits';
import { Outro } from './scenes/Outro';
import { Personalities } from './scenes/Personalities';
import { Reveal } from './scenes/Reveal';
import { Review } from './scenes/Review';
import { States } from './scenes/States';
import { SceneId, sceneFrames, TOTAL_FRAMES } from './timeline';

const SCENE: Record<SceneId, { component: React.FC; exit?: 'zoom' | 'whipLeft' | 'whipUp' | 'none'; punch?: number; origin?: string }> = {
  hook: { component: Hook, exit: 'zoom', punch: 0, origin: '50% 10%' },
  chaos: { component: Chaos, punch: 0.06 },
  reveal: { component: Reveal, exit: 'whipUp', punch: 0 },
  states: { component: States, exit: 'zoom', punch: 0.1 },
  approve: { component: Approve, exit: 'whipLeft' },
  review: { component: Review, exit: 'whipUp' },
  personalities: { component: Personalities, exit: 'zoom' },
  agents: { component: Agents, exit: 'whipUp' },
  limits: { component: Limits, exit: 'zoom' },
  outro: { component: Outro, punch: 0.04 },
};

export const PipHero: React.FC = () => (
  <AbsoluteFill style={{ background: '#000' }}>
    {(Object.keys(SCENE) as SceneId[]).map((id) => {
      const { from, duration } = sceneFrames[id];
      const { component: C, exit, punch, origin } = SCENE[id];
      return (
        <Sequence key={id} from={from} durationInFrames={duration} name={id}>
          <Camera duration={duration} exit={exit} punch={punch} origin={origin}>
            <C />
          </Camera>
        </Sequence>
      );
    })}
    <Audio
      src={staticFile('audio/music.wav')}
      volume={(f) => interpolate(f, [0, 10, TOTAL_FRAMES - 20, TOTAL_FRAMES], [0, 0.85, 0.85, 0], { extrapolateRight: 'clamp' })}
    />
  </AbsoluteFill>
);
