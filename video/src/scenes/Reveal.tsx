import React from 'react';
import { AbsoluteFill, Easing, OffthreadVideo, staticFile, useCurrentFrame } from 'remotion';
import { Caption, Flash, SMOOTH, Words, ramp, useSpring, useT } from '../anim';
import { REAL_FOOTAGE, REAL_FOOTAGE_START } from '../config';
import { DesktopWindows, MenuBar, Wallpaper } from '../desktop';
import { PipLogo } from '../logo';
import { CompactEars, EarIndicator, Notch } from '../notch';
import { Palette } from '../theme';

const SLAB_AT = 44;

/** On the drop: the camera pulls out of the notch onto a working desktop, then a slab slams in: "Meet Pip." */
export const Reveal: React.FC = () => {
  const frame = useCurrentFrame();
  const t = useT(4);
  const pull = useSpring(0, { damping: 20, stiffness: 70, mass: 1 });
  const scale = 4.2 - 3.2 * pull;
  const slab = ramp(frame, SLAB_AT, SLAB_AT + 16, SMOOTH);
  const logo = useSpring(SLAB_AT + 6, { damping: 10, stiffness: 170 });
  return (
    <AbsoluteFill style={{ background: '#000' }}>
      <AbsoluteFill style={{ transform: `scale(${scale}) translateX(${-slab * 60}px)`, transformOrigin: '50% 0%' }}>
        {REAL_FOOTAGE ? (
          <OffthreadVideo src={staticFile(REAL_FOOTAGE)} startFrom={Math.round(REAL_FOOTAGE_START * 30)} muted style={{ width: '100%', height: '100%', objectFit: 'cover', objectPosition: 'top' }} />
        ) : (
          <>
            <Wallpaper shift={frame / 120} />
            <DesktopWindows frame={frame} />
            <MenuBar />
            <AbsoluteFill style={{ alignItems: 'center' }}>
              <div style={{ zoom: 1.27 }}>
                <Notch compact={<CompactEars style="livingNotch" mood="working" t={t} right={<EarIndicator mood="working" t={t} working={3} />} />} />
              </div>
            </AbsoluteFill>
          </>
        )}
      </AbsoluteFill>
      <div
        style={{
          position: 'absolute',
          left: 0,
          right: 0,
          top: 520,
          height: 420,
          background: '#000',
          transform: `translateX(${(1 - slab) * -2000}px)`,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          gap: 56,
        }}
      >
        {frame >= SLAB_AT && (
          <>
            <div style={{ transform: `scale(${logo}) rotate(${(1 - logo) * -20}deg)` }}>
              <PipLogo size={250} t={t} gaze={{ x: frame < 80 ? 1 : 0, y: 0 }} />
            </div>
            <div>
              <Words text="Meet Pip." delay={SLAB_AT + 4} size={180} align="left" highlight={{ Pip: Palette.cyan }} />
              <Caption text="The notch companion for your AI coding agents." delay={SLAB_AT + 16} size={38} style={{ marginTop: 14 }} />
            </div>
          </>
        )}
      </div>
      <Flash at={0} strength={0.7} />
    </AbsoluteFill>
  );
};
