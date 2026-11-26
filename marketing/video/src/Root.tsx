import { useEffect, useState } from "react";
import { Composition, Still, continueRender, delayRender } from "remotion";
import { HeroLoop, type HeroProps } from "./HeroLoop";
import { STORE_SIZE } from "./store";
import { StoreShot, type StoreShotProps } from "./StoreShot";
import { fontFaces } from "./theme";
import { DURATION, FPS } from "./timeline";

const defaults: HeroProps = { layout: "vertical", date: "2026-11-26" };

const useFonts = () => {
  const [handle] = useState(() => delayRender("fonts"));
  useEffect(() => {
    Promise.all(fontFaces.map((face) => document.fonts.load(face)))
      .then(() => document.fonts.ready)
      .then(() => continueRender(handle));
  }, [handle]);
};

const FontGate: React.FC<HeroProps> = (props) => {
  useFonts();
  return <HeroLoop {...props} />;
};

const StoreFontGate: React.FC<StoreShotProps> = (props) => {
  useFonts();
  return <StoreShot {...props} />;
};

const storeDefaults: StoreShotProps = { index: 0, date: defaults.date };

export const Root: React.FC = () => (
  <>
    <Composition
      id="HeroLoop"
      component={FontGate}
      durationInFrames={DURATION}
      fps={FPS}
      width={1080}
      height={1920}
      defaultProps={defaults}
    />
    <Composition
      id="HeroLoopWide"
      component={FontGate}
      durationInFrames={DURATION}
      fps={FPS}
      width={1440}
      height={1080}
      defaultProps={{ ...defaults, layout: "wide" as const }}
    />
    <Still
      id="StoreShot"
      component={StoreFontGate}
      width={STORE_SIZE.width}
      height={STORE_SIZE.height}
      defaultProps={storeDefaults}
    />
  </>
);
