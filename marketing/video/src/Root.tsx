import { useEffect, useState } from "react";
import { Composition, continueRender, delayRender } from "remotion";
import { HeroLoop, type HeroProps } from "./HeroLoop";
import { fontFaces } from "./theme";
import { DURATION, FPS } from "./timeline";

const defaults: HeroProps = { layout: "vertical", date: "2026-11-26" };

const FontGate: React.FC<HeroProps> = (props) => {
  const [handle] = useState(() => delayRender("fonts"));
  useEffect(() => {
    Promise.all(fontFaces.map((face) => document.fonts.load(face)))
      .then(() => document.fonts.ready)
      .then(() => continueRender(handle));
  }, [handle]);
  return <HeroLoop {...props} />;
};

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
  </>
);
