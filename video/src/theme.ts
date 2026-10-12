export const FPS = 30;
/** 120 BPM: one beat is 15 frames, one bar 60. Scene cuts land on beats so they hit the music. */
export const BEAT = 15;
export const BAR = BEAT * 4;

export const Palette = {
  amber: 'rgb(245, 158, 10)',
  red: 'rgb(240, 69, 69)',
  green: 'rgb(33, 196, 94)',
  quiet: 'rgb(163, 163, 163)',
  faint: 'rgba(255, 255, 255, 0.08)',
  cyan: 'rgb(56, 212, 245)',
  darkCard: 'rgb(13, 28, 36)',
  darkCardBorder: 'rgb(31, 61, 74)',
  badgeBg: 'rgb(13, 56, 69)',
};

export type Mood = 'idle' | 'working' | 'needsYou' | 'error' | 'rateLimited' | 'finished' | 'asleep';

export const moodColor: Record<Mood, string> = {
  idle: '#ffffff',
  working: '#ffffff',
  needsYou: Palette.amber,
  error: Palette.red,
  rateLimited: Palette.amber,
  finished: Palette.green,
  asleep: '#ffffff',
};

export const sans = '-apple-system, "SF Pro Display", "SF Pro Text", "Helvetica Neue", Helvetica, Arial, sans-serif';
export const rounded = '"SF Pro Rounded", -apple-system, "SF Pro Display", sans-serif';
export const mono = '"SF Mono", ui-monospace, Menlo, monospace';

export type Agent = { name: string; initials: string; tint: string; tested?: boolean };

const rgb = (r: number, g: number, b: number) => `rgb(${Math.round(r * 255)}, ${Math.round(g * 255)}, ${Math.round(b * 255)})`;

/** Every agent Pip supports, with the badge colours from AgentBadge.swift. */
export const AGENTS: Agent[] = [
  { name: 'Claude Code', initials: 'CC', tint: rgb(0.91, 0.55, 0.4), tested: true },
  { name: 'Codex', initials: 'CX', tint: rgb(0.45, 0.8, 0.7), tested: true },
  { name: 'Cursor', initials: 'CU', tint: rgb(0.72, 0.85, 1.0), tested: true },
  { name: 'Antigravity', initials: 'AG', tint: rgb(0.4, 0.78, 1.0), tested: true },
  { name: 'Gemini CLI', initials: 'GM', tint: rgb(0.49, 0.62, 1.0) },
  { name: 'Copilot CLI', initials: 'CP', tint: rgb(0.8, 0.8, 0.86) },
  { name: 'Windsurf', initials: 'WS', tint: rgb(0.35, 0.85, 0.75) },
  { name: 'OpenCode', initials: 'OC', tint: rgb(0.95, 0.95, 0.95) },
  { name: 'Droid', initials: 'DR', tint: rgb(0.98, 0.69, 0.3) },
  { name: 'Devin', initials: 'DV', tint: rgb(0.25, 0.78, 0.62) },
  { name: 'Amp', initials: 'AM', tint: rgb(0.95, 0.35, 0.25) },
  { name: 'Kiro', initials: 'KR', tint: rgb(0.62, 0.5, 1.0) },
  { name: 'Grok Build', initials: 'GK', tint: rgb(0.88, 0.88, 0.92) },
  { name: 'Kimi Code', initials: 'KM', tint: rgb(0.45, 0.62, 1.0) },
  { name: 'Mistral Vibe', initials: 'MV', tint: rgb(1.0, 0.55, 0.25) },
  { name: 'Qwen', initials: 'QW', tint: rgb(0.55, 0.45, 1.0) },
  { name: 'DeepSeek', initials: 'DS', tint: rgb(0.3, 0.55, 1.0) },
  { name: 'Trae', initials: 'TR', tint: rgb(0.2, 0.85, 0.65) },
  { name: 'Goose', initials: 'GS', tint: rgb(0.98, 0.8, 0.4) },
  { name: 'Augment', initials: 'AU', tint: rgb(0.95, 0.95, 0.95) },
  { name: 'ZCode', initials: 'ZC', tint: rgb(0.35, 0.65, 0.95) },
  { name: 'MiMoCode', initials: 'MC', tint: rgb(1.0, 0.45, 0.15) },
  { name: 'Qoder', initials: 'QD', tint: rgb(0.36, 0.82, 0.55) },
  { name: 'QoderWork', initials: 'QO', tint: rgb(1.0, 0.6, 0.2) },
  { name: 'QwenWork', initials: 'QN', tint: rgb(0.45, 0.4, 0.95) },
  { name: 'DeepSeek Harness', initials: 'DH', tint: rgb(0.25, 0.7, 0.95) },
  { name: 'CodeBuddy', initials: 'CB', tint: rgb(0.2, 0.6, 0.95) },
  { name: 'WorkBuddy', initials: 'WB', tint: rgb(0.35, 0.5, 0.9) },
  { name: 'Hermes', initials: 'HM', tint: rgb(0.95, 0.75, 0.2) },
  { name: 'Pi Agent', initials: 'PI', tint: rgb(0.86, 0.52, 0.96) },
  { name: 'Oh My Pi', initials: 'OP', tint: rgb(0.8, 0.4, 0.9) },
  { name: 'Gajae Code', initials: 'GC', tint: rgb(0.92, 0.4, 0.45) },
];

export const agent = (initials: string) => AGENTS.find((a) => a.initials === initials)!;
