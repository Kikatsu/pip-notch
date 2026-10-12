import React from 'react';
import { Composition } from 'remotion';
import { FPS } from './theme';
import { TOTAL_FRAMES } from './timeline';
import { PipHero } from './Video';

export const Root: React.FC = () => (
  <Composition id="PipHero" component={PipHero} durationInFrames={TOTAL_FRAMES} fps={FPS} width={1920} height={1080} />
);
