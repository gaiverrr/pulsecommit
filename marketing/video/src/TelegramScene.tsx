import { SCREEN } from "./layout";
import { color, font } from "./theme";
import { MARKS, PERIODS, REPLY_WORDS, clamp01, countUp, easeOut, formatInt, replyWordsShown } from "./timeline";

const tg = { bg: "#17212b", bubble: "#182533", link: "#6ab2f2", dim: "#708499" };
const AGENT = tg.link;

const appear = (frame: number, at: number, length = 16) => easeOut(clamp01((frame - at) / length));

const StatusBar: React.FC = () => (
  <div
    style={{
      position: "absolute",
      left: 0,
      top: 0,
      width: SCREEN.width,
      height: 160,
      display: "flex",
      alignItems: "center",
      justifyContent: "space-between",
      padding: "24px 110px 0 150px",
      boxSizing: "border-box",
      fontFamily: font.ui,
      fontWeight: 600,
      fontSize: 52,
      color: color.text,
    }}
  >
    <span>09:41</span>
    <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
      <div style={{ width: 78, height: 38, borderRadius: 11, border: `4px solid ${color.muted}`, padding: 4, boxSizing: "border-box" }}>
        <div style={{ width: "100%", height: "100%", borderRadius: 5, background: color.success }} />
      </div>
    </div>
  </div>
);

const Header: React.FC<{ typing: boolean }> = ({ typing }) => (
  <div
    style={{
      position: "absolute",
      left: 0,
      top: 160,
      width: SCREEN.width,
      height: 190,
      display: "flex",
      alignItems: "center",
      padding: "0 56px",
      boxSizing: "border-box",
      borderBottom: `3px solid ${color.divider}`,
      fontFamily: font.ui,
    }}
  >
    <span style={{ color: tg.link, fontSize: 50, width: 260 }}>‹ Chats</span>
    <div style={{ flex: 1, textAlign: "center" }}>
      <div style={{ color: color.text, fontSize: 50, fontWeight: 600 }}>Health log</div>
      <div style={{ color: typing ? AGENT : tg.dim, fontSize: 38, marginTop: 6 }}>
        {typing ? "Health agent is typing" : "3 members"}
      </div>
    </div>
    <div style={{ width: 260, display: "flex", justifyContent: "flex-end" }}>
      <div
        style={{
          width: 120,
          height: 120,
          borderRadius: 60,
          background: color.accent,
          color: "#000",
          fontFamily: font.mono,
          fontWeight: 600,
          fontSize: 46,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        HL
      </div>
    </div>
  </div>
);

const Avatar: React.FC<{ label: string; bg: string }> = ({ label, bg }) => (
  <div
    style={{
      width: 96,
      height: 96,
      borderRadius: 48,
      background: bg,
      color: "#000",
      fontFamily: font.mono,
      fontWeight: 600,
      fontSize: 38,
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      flexShrink: 0,
    }}
  >
    {label}
  </div>
);

const Bubble: React.FC<{
  sender: string;
  senderColor: string;
  avatar: React.ReactNode;
  progress: number;
  children: React.ReactNode;
}> = ({ sender, senderColor, avatar, progress, children }) => (
  <div
    style={{
      display: "flex",
      alignItems: "flex-end",
      gap: 22,
      opacity: progress,
      transform: `translateY(${(1 - progress) * 40}px) scale(${0.96 + 0.04 * progress})`,
      transformOrigin: "0 100%",
    }}
  >
    {avatar}
    <div
      style={{
        background: tg.bubble,
        border: `3px solid ${color.hairline}`,
        borderRadius: "44px 44px 44px 12px",
        padding: "30px 40px 26px",
        maxWidth: 1060,
        boxSizing: "border-box",
      }}
    >
      <div style={{ fontFamily: font.ui, fontWeight: 600, fontSize: 38, color: senderColor, marginBottom: 14 }}>{sender}</div>
      {children}
    </div>
  </div>
);

const Row: React.FC<{ label: string; value: string; indent?: boolean }> = ({ label, value, indent = true }) => (
  <div style={{ display: "flex", whiteSpace: "pre" }}>
    <span style={{ width: indent ? 500 : 546, paddingLeft: indent ? 46 : 0, color: color.muted }}>{label}</span>
    <span style={{ color: color.text }}>{value}</span>
  </div>
);

const Section: React.FC<{ title: string }> = ({ title }) => (
  <div style={{ color: color.text, fontWeight: 600, marginTop: 22 }}>{title}</div>
);

const Summary: React.FC<{ frame: number; date: string }> = ({ frame, date }) => {
  const n = (value: number) => formatInt(countUp(value, frame, MARKS.countFrom, MARKS.countTo));
  const sleep = countUp(451, frame, MARKS.countFrom, MARKS.countTo);
  return (
    <div style={{ fontFamily: font.mono, fontSize: 42, lineHeight: 1.42, width: 900 }}>
      <div style={{ color: color.accent, fontWeight: 600 }}>Pulse Commit · {date}</div>
      <Section title="Activity" />
      <Row label="Steps" value={n(12483)} />
      <Row label="Active energy" value={`${n(642)} kcal`} />
      <Section title="Heart" />
      <Row label="Heart rate" value={`${n(68)} bpm avg`} />
      <Row label="HRV (SDNN)" value={`${n(47)} ms`} />
      <Section title="Sleep" />
      <Row label="Duration" value={`${Math.floor(sleep / 60)}h ${String(sleep % 60).padStart(2, "0")}m`} />
      <div style={{ height: 22 }} />
      <Row label="Workouts" value={n(1)} indent={false} />
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 26,
          marginTop: 30,
          padding: 22,
          borderRadius: 24,
          background: color.surface,
          border: `3px solid ${color.hairline}`,
        }}
      >
        <div
          style={{
            width: 92,
            height: 92,
            borderRadius: 20,
            background: color.accentSoft,
            color: color.accent,
            fontWeight: 600,
            fontSize: 30,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          ZIP
        </div>
        <div>
          <div style={{ color: color.text, fontSize: 34 }}>pulse-{date}.zip</div>
          <div style={{ color: color.dim, fontSize: 30 }}>9 files · 38 KB</div>
        </div>
      </div>
      <div style={{ textAlign: "right", color: color.dim, fontSize: 30, marginTop: 14 }}>21:00</div>
    </div>
  );
};

const TypingDots: React.FC<{ frame: number }> = ({ frame }) => (
  <div style={{ display: "flex", gap: 16, padding: "10px 6px" }}>
    {[0, 1, 2].map((i) => {
      const phase = ((frame + i * 6) % PERIODS.typingDots) / PERIODS.typingDots;
      const lift = Math.sin(phase * Math.PI * 2);
      return (
        <div
          key={i}
          style={{
            width: 26,
            height: 26,
            borderRadius: 13,
            background: color.muted,
            opacity: 0.45 + 0.55 * Math.max(0, lift),
            transform: `translateY(${-Math.max(0, lift) * 10}px)`,
          }}
        />
      );
    })}
  </div>
);

const Reply: React.FC<{ frame: number }> = ({ frame }) => {
  const shown = replyWordsShown(frame);
  return (
    <div style={{ fontFamily: font.ui, fontSize: 46, lineHeight: 1.36, color: color.text, width: 880 }}>
      <div>
        {REPLY_WORDS.map((word, i) => (
          <span
            key={i}
            style={{
              ...(word.mono ? { fontFamily: font.mono, color: color.accent } : {}),
              opacity: i < shown ? 1 : 0,
            }}
          >
            {i > 0 ? " " : ""}
            {word.text}
          </span>
        ))}
      </div>
      <div style={{ textAlign: "right", color: tg.dim, fontSize: 30, marginTop: 10, fontFamily: font.mono }}>21:01</div>
    </div>
  );
};

export const TelegramScene: React.FC<{ frame: number; date: string }> = ({ frame, date }) => {
  const typing = frame >= MARKS.typingFrom && frame < MARKS.replyIn;
  const typingIn = appear(frame, MARKS.typingFrom, 10);
  const replyIn = appear(frame, MARKS.replyIn);
  return (
    <div style={{ position: "absolute", inset: 0, width: SCREEN.width, height: SCREEN.height, background: tg.bg }}>
      <StatusBar />
      <Header typing={typing} />
      <div
        style={{
          position: "absolute",
          top: 440,
          width: SCREEN.width,
          textAlign: "center",
          fontFamily: font.ui,
          fontSize: 34,
          color: color.dim,
        }}
      >
        Today
      </div>
      <div style={{ position: "absolute", left: 44, top: 520, display: "flex", flexDirection: "column", gap: 12 }}>
        <Bubble
          sender="pulse bot"
          senderColor={color.accent}
          avatar={<Avatar label="PC" bg={color.accent} />}
          progress={appear(frame, MARKS.summaryIn)}
        >
          <Summary frame={frame} date={date} />
        </Bubble>
        {typing && (
          <Bubble sender="Health agent" senderColor={AGENT} avatar={<Avatar label="AI" bg={AGENT} />} progress={typingIn}>
            <TypingDots frame={frame} />
          </Bubble>
        )}
        {frame >= MARKS.replyIn && (
          <Bubble sender="Health agent" senderColor={AGENT} avatar={<Avatar label="AI" bg={AGENT} />} progress={replyIn}>
            <Reply frame={frame} />
          </Bubble>
        )}
      </div>
      <div
        style={{
          position: "absolute",
          left: 44,
          right: 44,
          top: 2420,
          height: 120,
          borderRadius: 60,
          background: color.surface,
          border: `3px solid ${color.hairline}`,
          display: "flex",
          alignItems: "center",
          padding: "0 50px",
          fontFamily: font.ui,
          fontSize: 42,
          color: color.faint,
        }}
      >
        Message
      </div>
    </div>
  );
};
