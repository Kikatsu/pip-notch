// Renders a contact sheet of frames for quick review: node scripts/stills.mjs 75 160 300 ...
import { bundle } from '@remotion/bundler';
import { renderStill, selectComposition } from '@remotion/renderer';
import { execFileSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import path from 'node:path';

const frames = process.argv.slice(2).map(Number);
const out = path.resolve('out/stills');
mkdirSync(out, { recursive: true });
const serveUrl = await bundle({ entryPoint: path.resolve('src/index.ts') });
const composition = await selectComposition({ serveUrl, id: 'PipHero' });
const files = [];
for (const frame of frames) {
  const output = path.join(out, `f${frame}.jpg`);
  await renderStill({ composition, serveUrl, frame, output, scale: 0.5, imageFormat: 'jpeg' });
  files.push(output);
}
// 2-wide grid
const inputs = files.flatMap((f) => ['-i', f]);
const n = files.length;
const rows = Math.ceil(n / 2);
let filter = '';
const rowLabels = [];
for (let r = 0; r < rows; r++) {
  const a = r * 2, b = r * 2 + 1;
  if (b < n) { filter += `[${a}][${b}]hstack[r${r}];`; } else { filter += `[${a}]pad=iw*2:ih[r${r}];`; }
  rowLabels.push(`[r${r}]`);
}
filter += rows > 1 ? `${rowLabels.join('')}vstack=inputs=${rows}` : `[r0]null`;
execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', ...inputs, '-filter_complex', filter, path.join(out, 'sheet.jpg')]);
console.log('sheet: out/stills/sheet.jpg');
