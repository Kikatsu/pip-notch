# Pip promo video

The [Remotion](https://www.remotion.dev) source for Pip's 52-second promo video. The README screenshots in `docs/images/` are frames from it. You don't need any of this to build or use Pip.

```sh
cd video
npm install
npm run audio     # synthesize the sound effects and music into public/audio
npm run studio    # preview and edit in the browser
npm run render    # render out/pip-hero.mp4
```

Scene lengths live in `src/timeline.ts`, and the music in `scripts/synth.mjs` follows the same cuts.

To use a real screen recording for the reveal shot, run `npm run record` (it records your whole main display for 20 seconds, so tidy up first), then set `REAL_FOOTAGE` in `src/config.ts`.
