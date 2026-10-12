/**
 * Real screen recording of Pip for the reveal shot (the "hybrid" part of the video).
 * Record one with `npm run record` (see scripts/record-notch.sh), then set this to
 * 'footage/pip-demo.mov'. Leave it null to use the rebuilt desktop instead.
 */
export const REAL_FOOTAGE: string | null = null;
/** Seconds into the recording where the reveal should start. */
export const REAL_FOOTAGE_START = 2;

/** Shown under the logo at the end. Leave empty to hide. */
export const CTA_URL = '';
