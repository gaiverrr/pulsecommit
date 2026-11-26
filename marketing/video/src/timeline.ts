export const FPS = 60;
export const DURATION = 600;

export type SceneName =
  | "home-idle"
  | "press"
  | "running"
  | "done"
  | "history"
  | "telegram"
  | "return"
  | "home-hold";

export const SCENES: { name: SceneName; from: number; to: number }[] = [
  { name: "home-idle", from: 0, to: 54 },
  { name: "press", from: 54, to: 72 },
  { name: "running", from: 72, to: 250 },
  { name: "done", from: 250, to: 330 },
  { name: "history", from: 330, to: 404 },
  { name: "telegram", from: 404, to: 562 },
  { name: "return", from: 562, to: 584 },
  { name: "home-hold", from: 584, to: 600 },
];

export const PERIODS = {
  typingDots: 30,
  statusPulse: 60,
};

export const MARKS = {
  exportTap: 54,
  runningShots: [72, 132, 192],
  rowsIn: 258,
  historyTap: 318,
  historyIn: 334,
  telegramIn: 404,
  summaryIn: 414,
  countFrom: 420,
  countTo: 456,
  typingFrom: 448,
  replyIn: 470,
  returnFrom: 562,
  returnTo: 584,
};

export const CAPTIONS = [
  { kicker: "$ pulse commit --since=today", title: "Reads only the categories you picked" },
  { kicker: "$ git log --oneline", title: "Telegram, GitHub or your webhook" },
  { kicker: "> telegram", title: "A summary your agent can read" },
];

export const REPLY_WORDS: { text: string; mono?: boolean }[] = [
  { text: "Steps" },
  { text: "18%", mono: true },
  { text: "above" },
  { text: "your" },
  { text: "7-day" },
  { text: "average." },
  { text: "Good" },
  { text: "day" },
  { text: "for" },
  { text: "intervals." },
];

const REPLY_WORD_FRAMES = 2;

export function replyWordsShown(frame: number): number {
  if (frame < MARKS.replyIn) return 0;
  return Math.min(REPLY_WORDS.length, Math.floor((frame - MARKS.replyIn) / REPLY_WORD_FRAMES) + 1);
}

export function replyTypedAt(): number {
  return MARKS.replyIn + (REPLY_WORDS.length - 1) * REPLY_WORD_FRAMES;
}

const CAPTION_SWITCHES = [
  { at: 250, to: 1 },
  { at: 404, to: 2 },
  { at: 562, to: 0 },
];
const CAPTION_FADE = 14;

export function sceneAt(frame: number): SceneName {
  const f = ((frame % DURATION) + DURATION) % DURATION;
  const scene = SCENES.find((s) => f >= s.from && f < s.to);
  if (!scene) return "home-idle";
  return scene.name === "home-hold" ? "home-idle" : scene.name;
}

export function captionAt(frame: number): { index: number; opacity: number } {
  let index = 0;
  for (const s of CAPTION_SWITCHES) {
    if (frame >= s.at) index = s.to;
  }
  const switchFrame = [...CAPTION_SWITCHES].reverse().find((s) => frame >= s.at)?.at;
  if (switchFrame === undefined) return { index, opacity: 1 };
  const t = (frame - switchFrame) / CAPTION_FADE;
  return { index, opacity: clamp01(t) };
}

export function progressAt(frame: number): number {
  const running = SCENES.find((s) => s.name === "running")!;
  const t = clamp01((frame - running.from) / (running.to - running.from));
  return easeInOut(t);
}

export function countUp(final: number, frame: number, from: number, to: number): number {
  const t = clamp01((frame - from) / (to - from));
  return Math.round(final * easeOut(t));
}

export function formatInt(value: number): string {
  return Math.round(value)
    .toString()
    .replace(/\B(?=(\d{3})+(?!\d))/g, " ");
}

export function clamp01(t: number): number {
  return Math.min(1, Math.max(0, t));
}

export function easeOut(t: number): number {
  return 1 - Math.pow(1 - t, 3);
}

export function easeInOut(t: number): number {
  return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
}
