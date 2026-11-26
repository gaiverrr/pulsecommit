import { CAPTURE } from "./capture-layout.ts";
import type { Rect } from "./measure.ts";

export const SCREEN = CAPTURE.screen;

const POINT = SCREEN.width / 402;

const center = (r: Rect) => ({ x: Math.round(r.x + r.w / 2), y: Math.round(r.y + r.h / 2) });

export const HOME = {
  card: CAPTURE.card,
  pressCrop: CAPTURE.card,
  cardRadius: Math.round(22 * POINT),
  cardHalo: CAPTURE.cardHalo,
  glow: Math.round(24 * POINT),
  exportTap: center(CAPTURE.topZone),
  progressTrack: { ...CAPTURE.bar, fill: "#000" },
  commitsArea: CAPTURE.commitsArea,
  commitRows: CAPTURE.commitRows.map((r) => [r.y, r.y + r.h]),
  historyTab: center(CAPTURE.historyTab),
};

export const HISTORY = {
  rowsArea: { x: 62, y: 683, w: 1082, h: 1697, bg: "#141414" },
  rows: [
    [683, 1055],
    [1055, 1431],
    [1431, 1807],
    [1807, 2183],
    [2183, 2380],
  ],
};

export const ISLAND = { w: 375, h: 111, top: 33 };
