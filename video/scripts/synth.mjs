// Renders the video's audio: Pip's own alert sounds (a port of SoundPlayer.swift's Synth)
// plus a 120 BPM music bed whose bars line up with the scene cuts in src/timeline.ts.
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const SR = 44100;
const OUT = join(dirname(fileURLToPath(import.meta.url)), '..', 'public', 'audio');
mkdirSync(OUT, { recursive: true });

// ---------- Pip's synthesizer, as in SoundPlayer.swift ----------

const TIMBRES = {
  bell: { partials: [[1, 1], [2, 0.45], [2.76, 0.28], [5.4, 0.1], [8.93, 0.04]], attack: 0.004 },
  marimba: { partials: [[1, 1], [4, 0.22], [9.9, 0.05]], attack: 0.004 },
  knock: { partials: [[1, 1], [2.3, 0.35], [3.9, 0.12]], attack: 0.004 },
  glass: { partials: [[1, 1], [2, 0.18], [3, 0.06]], attack: 0.02 },
  chip: { partials: [[1, 1], [3, 0.33], [5, 0.2], [7, 0.14], [9, 0.11]], attack: 0.002, sustains: true },
};

const note = (start, frequency, duration, amplitude, timbre) => ({ start, frequency, duration, amplitude, timbre });

const CUES = {
  'pip-approval': [note(0, 659.25, 1.0, 0.42, 'bell'), note(0.16, 987.77, 1.2, 0.38, 'bell')],
  'pip-finished': [
    ...[523.25, 659.25, 783.99, 1046.5].map((f, i) => note(i * 0.075, f, i === 3 ? 1.3 : 0.7, 0.3, 'marimba')),
    note(0.3, 2093.0, 1.1, 0.07, 'bell'),
  ],
  'pip-error': [note(0, 220, 0.35, 0.55, 'knock'), note(0.14, 174.61, 0.45, 0.5, 'knock')],
  'pip-ratelimit': [880, 739.99, 587.33].map((f, i) => note(i * 0.13, f, 0.9, 0.22, 'glass')),
  'soft-finished': [392, 493.88, 587.33].map((f, i) => note(i * 0.11, f, 0.8, 0.26, 'marimba')),
  'arcade-finished': [523.25, 659.25, 783.99, 1046.5, 1318.5].map((f, i) => note(i * 0.065, f, i === 4 ? 0.26 : 0.07, 0.15, 'chip')),
  'arcade-approval': [note(0, 1318.5, 0.09, 0.16, 'chip'), note(0.13, 1318.5, 0.09, 0.16, 'chip')],
};

function renderNotes(notes, into, offset = 0, gain = 1) {
  for (const n of notes) {
    const t0 = TIMBRES[n.timbre];
    const first = Math.round((n.start + offset) * SR);
    const length = Math.round(n.duration * SR);
    for (const [ratio, weight] of t0.partials) {
      const f = n.frequency * ratio;
      if (f >= SR / 2) continue;
      const tau = n.duration / 4 / Math.sqrt(ratio);
      const step = (2 * Math.PI * f) / SR;
      for (let i = 0; i < length && first + i < into.length; i++) {
        const t = i / SR;
        let env;
        if (t < t0.attack) env = t / t0.attack;
        else if (t0.sustains) env = Math.min(1, (n.duration - t) / 0.012);
        else env = Math.exp(-(t - t0.attack) / tau);
        into[first + i] += gain * n.amplitude * weight * env * Math.sin(step * i);
      }
    }
  }
}

function echo(buf, taps = [[0.083, 0.16], [0.149, 0.09]]) {
  const dry = Float64Array.from(buf);
  for (const [delay, g] of taps) {
    const o = Math.round(delay * SR);
    for (let i = o; i < buf.length; i++) buf[i] += dry[i - o] * g;
  }
}

function writeWav(name, samples, drive = 1.1) {
  const data = Buffer.alloc(samples.length * 2);
  for (let i = 0; i < samples.length; i++) {
    const s = Math.tanh(samples[i] * drive);
    data.writeInt16LE(Math.max(-32767, Math.min(32767, Math.round(s * 32767))), i * 2);
  }
  const h = Buffer.alloc(44);
  h.write('RIFF', 0); h.writeUInt32LE(36 + data.length, 4); h.write('WAVE', 8);
  h.write('fmt ', 12); h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22);
  h.writeUInt32LE(SR, 24); h.writeUInt32LE(SR * 2, 28); h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34);
  h.write('data', 36); h.writeUInt32LE(data.length, 40);
  writeFileSync(join(OUT, `${name}.wav`), Buffer.concat([h, data]));
}

for (const [name, notes] of Object.entries(CUES)) {
  const end = Math.max(...notes.map((n) => n.start + n.duration)) + 0.35;
  const buf = new Float64Array(Math.round(end * SR));
  renderNotes(notes, buf);
  echo(buf);
  writeWav(name, buf);
}

// ---------- Small UI effects ----------

let seed = 7;
const rand = () => ((seed = (seed * 16807) % 2147483647) / 2147483647) * 2 - 1;

function whoosh(dur = 0.45) {
  const buf = new Float64Array(Math.round(dur * SR));
  let lp = 0;
  for (let i = 0; i < buf.length; i++) {
    const p = i / buf.length;
    const cutoff = 0.02 + 0.25 * Math.sin(p * Math.PI);
    lp += cutoff * (rand() - lp);
    buf[i] = lp * Math.sin(p * Math.PI) ** 1.5 * 1.4;
  }
  return buf;
}

function pop() {
  const buf = new Float64Array(Math.round(0.12 * SR));
  let phase = 0;
  for (let i = 0; i < buf.length; i++) {
    const t = i / SR;
    phase += (2 * Math.PI * (380 + 900 * Math.exp(-t * 40))) / SR;
    buf[i] = Math.sin(phase) * Math.exp(-t * 32) * 0.5;
  }
  return buf;
}

function click() {
  const buf = new Float64Array(Math.round(0.05 * SR));
  let prev = 0;
  for (let i = 0; i < buf.length; i++) {
    const n = rand();
    buf[i] = (n - prev) * Math.exp(-(i / SR) * 160) * 0.5 + Math.sin((2 * Math.PI * 2200 * i) / SR) * Math.exp(-(i / SR) * 220) * 0.2;
    prev = n;
  }
  return buf;
}

writeWav('whoosh', whoosh());
writeWav('pop', pop());
writeWav('click', click());

// ---------- Music bed: 120 BPM, 4/4, one bar = 2 s = 60 frames at 30 fps ----------

const BPM = 120;
const BEAT = 60 / BPM;
const BAR = BEAT * 4;
const BARS = 26;
// Bar where the outro (logo) starts; keep in sync with src/timeline.ts.
const OUTRO_BAR = 23;
const LEN = BARS * BAR + 4;
const mix = new Float64Array(Math.round(LEN * SR));
const duck = new Float64Array(mix.length).fill(1);

const hz = (midi) => 440 * 2 ** ((midi - 69) / 12);
// IV - V - vi - I in C, one chord per bar.
const CHORDS = [
  [53, 57, 60, 64], // Fmaj7
  [55, 59, 62, 67], // G
  [57, 60, 64, 67], // Am7
  [48, 55, 60, 64], // C
];
const chordAt = (bar) => CHORDS[bar % 4];

function addKick(t) {
  const s0 = Math.round(t * SR);
  let phase = 0;
  for (let i = 0; i < 0.4 * SR && s0 + i < mix.length; i++) {
    const tt = i / SR;
    phase += (2 * Math.PI * (45 + 110 * Math.exp(-tt * 30))) / SR;
    mix[s0 + i] += Math.sin(phase) * Math.exp(-tt * 7) * 0.9;
  }
  for (let i = 0; i < 0.3 * SR && s0 + i < duck.length; i++) {
    const tt = i / SR;
    duck[s0 + i] = Math.min(duck[s0 + i], 1 - 0.65 * Math.exp(-tt * 14));
  }
}

function addNoise(t, dur, decay, gain, bright) {
  const s0 = Math.round(t * SR);
  let prev = 0, lp = 0;
  for (let i = 0; i < dur * SR && s0 + i < mix.length; i++) {
    const n = rand();
    const hp = n - prev; prev = n;
    lp += 0.3 * (n - lp);
    const v = bright ? hp : lp;
    mix[s0 + i] += v * Math.exp(-(i / SR) * decay) * gain;
  }
}

function addClap(t) {
  for (const d of [0, 0.011, 0.022]) addNoise(t + d, 0.18, d === 0.022 ? 18 : 90, 0.22, false);
}

const bed = new Float64Array(mix.length); // pad, bass and arp, ducked by the kick

function addPad(bar, gain) {
  const s0 = Math.round(bar * BAR * SR);
  const len = Math.round(BAR * SR);
  for (const m of chordAt(bar)) {
    for (const det of [-0.12, 0.12]) {
      const f = hz(m) * 2 ** (det / 12);
      for (let i = 0; i < len + SR * 0.4 && s0 + i < bed.length; i++) {
        const tt = i / SR;
        const env = Math.min(1, tt / 0.35) * (tt > BAR ? Math.exp(-(tt - BAR) * 8) : 1);
        bed[s0 + i] += Math.sin((2 * Math.PI * f * i) / SR) * env * gain * 0.05;
      }
    }
  }
}

function addBass(bar, gain) {
  const root = chordAt(bar)[0] - 12;
  for (let e = 0; e < 8; e++) {
    const t = bar * BAR + e * (BEAT / 2);
    const s0 = Math.round(t * SR);
    const f = hz(e === 7 ? root + 7 : root);
    for (let i = 0; i < (BEAT / 2) * SR * 0.95 && s0 + i < bed.length; i++) {
      const tt = i / SR;
      const env = Math.min(1, tt / 0.005) * Math.exp(-tt * 5);
      const w = 2 * Math.PI * f * tt;
      bed[s0 + i] += (Math.sin(w) + 0.3 * Math.sin(2 * w) + 0.1 * Math.sin(3 * w)) * env * gain * 0.32;
    }
  }
}

function addArp(bar, timbre, gain, sixteenths = true) {
  const notes = chordAt(bar).map((m) => m + 12);
  const pattern = [0, 1, 2, 3, 2, 1, 2, 3];
  const steps = sixteenths ? 16 : 8;
  const step = BAR / steps;
  const list = [];
  for (let s = 0; s < steps; s++) {
    const m = notes[pattern[s % 8]];
    list.push(note(bar * BAR + s * step, hz(m), timbre === 'chip' ? step * 0.7 : 0.35, 0.16 * gain, timbre));
  }
  renderNotes(list, bed);
}

// The timbre of the arp follows the character on screen in the personalities scene.
// Scene boundaries in beats (see src/timeline.ts): personalities start at beat 56, characters at 58.
const CHARACTERS_BEAT = 58;
function arpTimbreAt(beat) {
  const k = Math.floor((beat - CHARACTERS_BEAT) / 3);
  return beat >= CHARACTERS_BEAT && k < 4 ? ['bell', 'marimba', 'chip', 'glass'][k] : 'marimba';
}

for (let bar = 0; bar < BARS; bar++) {
  const intro = bar < 4;
  const outro = bar >= OUTRO_BAR;
  addPad(bar, intro ? 1.1 : outro ? 1.2 : 0.8);

  if (intro) {
    // Hook: sparse bells. Chaos (bars 2-3): ticking hats and a riser.
    if (bar < 2) renderNotes([note(bar * BAR, hz(chordAt(bar)[3] + 12), 1.6, 0.18, 'bell'), note(bar * BAR + BEAT * 2, hz(chordAt(bar)[2] + 12), 1.4, 0.14, 'bell')], bed);
    else {
      for (let s = 0; s < 16; s++) addNoise(bar * BAR + s * (BEAT / 4), 0.04, 120, 0.05 + (bar - 2) * 0.03 + s * 0.003, true);
      addArp(bar, 'marimba', 0.6 + (bar - 2) * 0.3, bar === 3);
    }
    continue;
  }
  if (outro) {
    if (bar === OUTRO_BAR) renderNotes(CUES['pip-finished'].map((n) => ({ ...n, start: n.start + bar * BAR, amplitude: n.amplitude * 0.9 })), bed);
    if (bar < OUTRO_BAR + 2) addArp(bar, 'bell', 0.5, false);
    continue;
  }

  for (let b = 0; b < 4; b++) {
    const t = bar * BAR + b * BEAT;
    addKick(t);
    if (b % 2 === 1) addClap(t);
    addNoise(t + BEAT / 2, 0.12, 30, 0.07, true); // open hat on the offbeat
    addNoise(t, 0.03, 160, 0.04, true);
  }
  addBass(bar, 1);
  for (let half = 0; half < 2; half++) {
    // Split each bar in two so the arp can change voice mid-bar.
    const beat = bar * 4 + half * 2;
    const tmp = new Float64Array(bed.length);
    const save = bed.slice();
    addArp(bar, arpTimbreAt(beat), arpTimbreAt(beat) === 'chip' ? 0.55 : 0.8);
    // Keep only the half of the bar we're on.
    const a = Math.round((bar * BAR + half * BAR / 2) * SR);
    const z = Math.round((bar * BAR + (half + 1) * BAR / 2) * SR);
    for (let i = 0; i < bed.length; i++) tmp[i] = bed[i] - save[i];
    bed.set(save);
    for (let i = a; i < Math.min(z + SR * 0.4, bed.length); i++) bed[i] += i < z ? tmp[i] : tmp[i] * Math.max(0, 1 - (i - z) / (SR * 0.05));
  }
}

// Riser into the drop at bar 4.
{
  const a = Math.round(3 * BAR * SR), z = Math.round(4 * BAR * SR);
  let lp = 0;
  for (let i = a; i < z; i++) {
    const p = (i - a) / (z - a);
    lp += (0.02 + 0.4 * p * p) * (rand() - lp);
    mix[i] += lp * p * p * 0.5;
  }
}
// Impact on the drop and on the final logo.
for (const bar of [4, OUTRO_BAR]) addKick(bar * BAR);

for (let i = 0; i < mix.length; i++) mix[i] += bed[i] * duck[i];
echo(mix, [[BEAT * 0.75, 0.12]]);
const fade = 3 * SR;
for (let i = mix.length - fade; i < mix.length; i++) mix[i] *= (mix.length - i) / fade;
writeWav('music', mix.map((s) => s * 0.7), 1.0);

console.log('Wrote audio to', OUT);
