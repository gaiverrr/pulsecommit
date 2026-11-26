import { AbsoluteFill, useCurrentFrame } from "remotion";
import { AppScene } from "./AppScene";
import { Phone, phoneWidth } from "./Phone";
import { color, font } from "./theme";
import { CAPTIONS, captionAt } from "./timeline";

export type HeroProps = { layout: "vertical" | "wide"; date: string };

const Caption: React.FC<{ frame: number; align: "center" | "left"; titleSize: number; width: number }> = ({
  frame,
  align,
  titleSize,
  width,
}) => {
  const { index, opacity } = captionAt(frame);
  const caption = CAPTIONS[index];
  return (
    <div style={{ width, textAlign: align, opacity, transform: `translateY(${(1 - opacity) * 16}px)` }}>
      <div style={{ fontFamily: font.mono, fontSize: titleSize * 0.48, color: color.accent, marginBottom: titleSize * 0.32 }}>
        {caption.kicker}
      </div>
      <div style={{ fontFamily: font.ui, fontWeight: 700, fontSize: titleSize, lineHeight: 1.12, color: color.text, letterSpacing: -1 }}>
        {caption.title}
      </div>
    </div>
  );
};

export const HeroLoop: React.FC<HeroProps> = ({ layout, date }) => {
  const frame = useCurrentFrame();
  if (layout === "wide") {
    const phoneH = 980;
    return (
      <AbsoluteFill style={{ background: color.bg, flexDirection: "row", alignItems: "center", padding: "0 110px", gap: 110 }}>
        <div style={{ flex: 1 }}>
          <Caption frame={frame} align="left" titleSize={64} width={760} />
        </div>
        <div style={{ width: phoneWidth(phoneH) }}>
          <Phone height={phoneH}>
            <AppScene frame={frame} date={date} />
          </Phone>
        </div>
      </AbsoluteFill>
    );
  }
  const phoneH = 1480;
  return (
    <AbsoluteFill style={{ background: color.bg, alignItems: "center" }}>
      <div style={{ position: "absolute", top: 110, left: 90, right: 90, display: "flex", justifyContent: "center" }}>
        <Caption frame={frame} align="center" titleSize={62} width={900} />
      </div>
      <div style={{ position: "absolute", top: 390 }}>
        <Phone height={phoneH}>
          <AppScene frame={frame} date={date} />
        </Phone>
      </div>
    </AbsoluteFill>
  );
};
