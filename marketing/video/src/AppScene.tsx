import { Img, staticFile } from "remotion";
import { HISTORY, HOME, SCREEN } from "./layout";
import { TelegramScene } from "./TelegramScene";
import { MARKS, clamp01, easeInOut, easeOut, progressAt } from "./timeline";

type ShotName =
  | "01-home-idle"
  | "02-home-running-a"
  | "03-home-running-b"
  | "04-home-running-c"
  | "05-home-done"
  | "06-history";

const shotSrc = (name: ShotName) => staticFile(`screens/${name}.png`);

const full: React.CSSProperties = {
  position: "absolute",
  left: 0,
  top: 0,
  width: SCREEN.width,
  height: SCREEN.height,
};

const Shot: React.FC<{ name: ShotName; opacity?: number }> = ({ name, opacity = 1 }) => (
  <Img src={shotSrc(name)} style={{ ...full, opacity }} />
);

const Crop: React.FC<{
  name: ShotName;
  x: number;
  y: number;
  w: number;
  h: number;
  style?: React.CSSProperties;
}> = ({ name, x, y, w, h, style }) => (
  <div style={{ position: "absolute", left: x, top: y, width: w, height: h, overflow: "hidden", ...style }}>
    <Img src={shotSrc(name)} style={{ ...full, left: -x, top: -y }} />
  </div>
);

const fade = (frame: number, from: number, length: number) => clamp01((frame - from) / length);

const Ripple: React.FC<{ frame: number; at: number; x: number; y: number }> = ({ frame, at, x, y }) => {
  const t = (frame - at) / 30;
  if (t < 0 || t > 1) return null;
  const r = 40 + easeOut(t) * 150;
  return (
    <div
      style={{
        position: "absolute",
        left: x - r,
        top: y - r,
        width: r * 2,
        height: r * 2,
        borderRadius: r,
        background: "rgba(255,255,255,0.35)",
        border: "4px solid rgba(255,255,255,0.6)",
        opacity: 1 - t,
        boxSizing: "border-box",
      }}
    />
  );
};

const StaggerRows: React.FC<{
  frame: number;
  name: ShotName;
  area: { x: number; y: number; w: number; h: number; bg: string };
  rows: number[][];
  start: number;
  step: number;
}> = ({ frame, name, area, rows, start, step }) => (
  <>
    <div style={{ position: "absolute", left: area.x, top: area.y, width: area.w, height: area.h, background: area.bg }} />
    {rows.map(([top, bottom], i) => {
      const t = easeOut(fade(frame, start + i * step, 16));
      return (
        <Crop
          key={top}
          name={name}
          x={area.x}
          y={top}
          w={area.w}
          h={bottom - top}
          style={{ opacity: t, transform: `translateY(${(1 - t) * 36}px)` }}
        />
      );
    })}
  </>
);

const PressedCard: React.FC<{ frame: number }> = ({ frame }) => {
  const t = clamp01((frame - MARKS.exportTap) / 18);
  if (t <= 0 || t >= 1) return null;
  const scale = 1 - 0.035 * Math.sin(Math.PI * t);
  const { x, y, w, h } = HOME.pressCrop;
  const r = HOME.cardRadius;
  return (
    <>
      <div style={{ position: "absolute", left: x - 1, top: y - 1, width: w + 2, height: h + 2, borderRadius: r + 1, background: HOME.cardHalo }} />
      <Crop
        name="01-home-idle"
        x={x}
        y={y}
        w={w}
        h={h}
        style={{
          transform: `scale(${scale})`,
          borderRadius: r,
          boxShadow: `0 0 ${HOME.glow}px ${HOME.cardHalo}`,
        }}
      />
    </>
  );
};

const ProgressBar: React.FC<{ frame: number }> = ({ frame }) => {
  const p = progressAt(frame);
  const { x, y, w, h, track, fill, bg } = HOME.progressTrack;
  return (
    <div style={{ position: "absolute", left: x - 1, top: y - 2, width: w + 2, height: h + 4, background: bg }}>
      <div style={{ position: "absolute", left: 1, top: 2, width: w, height: h, background: track, borderRadius: h / 2 }}>
        <div style={{ width: w * p, height: h, background: fill, borderRadius: h / 2 }} />
      </div>
    </div>
  );
};

const runningShot = (frame: number): { from: ShotName; to: ShotName; mix: number } => {
  const [, b, c] = MARKS.runningShots;
  if (frame < b) return { from: "02-home-running-a", to: "02-home-running-a", mix: 0 };
  if (frame < c) return { from: "02-home-running-a", to: "03-home-running-b", mix: fade(frame, b, 10) };
  return { from: "03-home-running-b", to: "04-home-running-c", mix: fade(frame, c, 10) };
};

const HomeFlow: React.FC<{ frame: number }> = ({ frame }) => {
  if (frame < 250) {
    const idle = frame < MARKS.runningShots[0] ? 1 : 0;
    const running = runningShot(frame);
    return (
      <>
        {frame >= 72 && (
          <>
            <Shot name={running.from} />
            {running.mix > 0 && <Shot name={running.to} opacity={running.mix} />}
            <ProgressBar frame={frame} />
          </>
        )}
        {idle > 0 && (
          <div style={{ ...full, opacity: idle }}>
            <Shot name="01-home-idle" />
            <PressedCard frame={frame} />
          </div>
        )}
        <Ripple frame={frame} at={MARKS.exportTap} x={HOME.exportTap.x} y={HOME.exportTap.y} />
      </>
    );
  }
  return (
    <>
      <Shot name="04-home-running-c" />
      <ProgressBar frame={frame} />
      <div style={{ ...full, opacity: fade(frame, 250, 8) }}>
        <Shot name="05-home-done" />
        <StaggerRows
          frame={frame}
          name="05-home-done"
          area={HOME.commitsArea}
          rows={HOME.commitRows}
          start={MARKS.rowsIn}
          step={7}
        />
      </div>
      <Ripple frame={frame} at={MARKS.historyTap} x={HOME.historyTab.x} y={HOME.historyTab.y} />
    </>
  );
};

const HistoryFlow: React.FC<{ frame: number }> = ({ frame }) => (
  <>
    <Shot name="06-history" />
    <StaggerRows
      frame={frame}
      name="06-history"
      area={HISTORY.rowsArea}
      rows={HISTORY.rows}
      start={MARKS.historyIn}
      step={6}
    />
  </>
);

export const AppScene: React.FC<{ frame: number; date: string }> = ({ frame, date }) => {
  const historyMix = fade(frame, 330, 8);
  const slide = easeInOut(fade(frame, MARKS.telegramIn, 18));
  const back = easeInOut(fade(frame, MARKS.returnFrom, MARKS.returnTo - MARKS.returnFrom));
  if (frame >= MARKS.returnTo) {
    return <Shot name="01-home-idle" />;
  }
  return (
    <>
      {back > 0 && (
        <div style={{ ...full, transform: `translateX(${-(1 - back) * 360}px)`, opacity: 0.4 + back * 0.6 }}>
          <Shot name="01-home-idle" />
        </div>
      )}
      {frame < MARKS.telegramIn + 18 && (
        <div style={{ ...full, transform: `translateX(${-slide * 360}px)`, opacity: 1 - slide * 0.6 }}>
          {historyMix < 1 && <HomeFlow frame={frame} />}
          {historyMix > 0 && (
            <div style={{ ...full, opacity: historyMix }}>
              <HistoryFlow frame={frame} />
            </div>
          )}
        </div>
      )}
      {frame >= MARKS.telegramIn && (
        <div style={{ ...full, transform: `translateX(${(1 - slide + back) * SCREEN.width}px)` }}>
          <TelegramScene frame={frame} date={date} />
        </div>
      )}
    </>
  );
};
