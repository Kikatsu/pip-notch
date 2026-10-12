import { BAR } from './theme';

/** Scene lengths in bars (2 s each at 120 BPM). The music in scripts/synth.mjs follows these cuts. */
export const SCENES = [
  { id: 'hook', bars: 2 },
  { id: 'chaos', bars: 2 },
  { id: 'reveal', bars: 2 }, // the drop lands here (bar 4)
  { id: 'states', bars: 2 },
  { id: 'approve', bars: 3 },
  { id: 'review', bars: 3 },
  { id: 'personalities', bars: 5 },
  { id: 'agents', bars: 2 },
  { id: 'limits', bars: 2 },
  { id: 'outro', bars: 3 },
] as const;

export type SceneId = (typeof SCENES)[number]['id'];

export const sceneFrames = SCENES.reduce<Record<string, { from: number; duration: number }>>((acc, s, i) => {
  const from = SCENES.slice(0, i).reduce((sum, x) => sum + x.bars * BAR, 0);
  acc[s.id] = { from, duration: s.bars * BAR };
  return acc;
}, {});

export const TOTAL_FRAMES = SCENES.reduce((sum, s) => sum + s.bars * BAR, 0);
