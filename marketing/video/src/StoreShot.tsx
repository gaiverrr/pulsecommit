import { AbsoluteFill, Img, staticFile } from "remotion";
import { SCREEN } from "./layout";
import { Phone } from "./Phone";
import { STORE_CAPTURE, STORE_SHOTS, TELEGRAM_FRAME } from "./store";
import { TelegramScene } from "./TelegramScene";
import { color, font } from "./theme";

export type StoreShotProps = { index: number; date: string };

const PHONE_TOP = 700;
const PHONE_HEIGHT = 2060;

export const StoreShot: React.FC<StoreShotProps> = ({ index, date }) => {
  const shot = STORE_SHOTS[index];
  const telegram = shot.screen === "telegram";
  const screen = telegram ? SCREEN : STORE_CAPTURE;
  return (
    <AbsoluteFill style={{ background: color.bg, alignItems: "center" }}>
      <div
        style={{
          position: "absolute",
          top: 120,
          left: 90,
          right: 90,
          height: PHONE_TOP - 180,
          display: "flex",
          flexDirection: "column",
          justifyContent: "center",
          alignItems: "center",
          textAlign: "center",
        }}
      >
        <div style={{ fontFamily: font.mono, fontSize: 44, color: color.accent, marginBottom: 34 }}>{shot.kicker}</div>
        <div
          style={{
            fontFamily: font.ui,
            fontWeight: 800,
            fontSize: 104,
            lineHeight: 1.08,
            letterSpacing: -2,
            color: color.text,
            textWrap: "balance",
          }}
        >
          {shot.title}
        </div>
      </div>
      <div style={{ position: "absolute", top: PHONE_TOP }}>
        <Phone height={PHONE_HEIGHT} screen={screen}>
          {telegram ? (
            <TelegramScene frame={TELEGRAM_FRAME} date={date} />
          ) : (
            <Img
              src={staticFile(`store/${shot.screen}.png`)}
              style={{ position: "absolute", left: 0, top: 0, width: screen.width, height: screen.height }}
            />
          )}
        </Phone>
      </div>
    </AbsoluteFill>
  );
};
