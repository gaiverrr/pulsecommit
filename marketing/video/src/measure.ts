export type Rect = { x: number; y: number; w: number; h: number };
export type RGB = [number, number, number];
export type Raster = { width: number; height: number; data: Uint8Array };
export type ElementFrames = Record<string, number[][]>;

export type CaptureLayout = {
  screen: { width: number; height: number };
  card: Rect;
  cardHalo: string;
  topZone: Rect;
  chipRow: Rect;
  bar: ProgressBar;
  commitsArea: Rect & { bg: string };
  commitRows: Rect[];
  historyTab: Rect;
};

const pixel = (img: Raster, x: number, y: number): RGB => {
  const i = (y * img.width + x) * 3;
  return [img.data[i], img.data[i + 1], img.data[i + 2]];
};

const distance = (a: RGB, b: RGB) => Math.max(Math.abs(a[0] - b[0]), Math.abs(a[1] - b[1]), Math.abs(a[2] - b[2]));

const isLime = ([r, g, b]: RGB) => g > 190 && r > 110 && r < 210 && b < 120 && g - r > 40;

const isDark = ([r, g, b]: RGB) => r + g + b < 150;

const toRect = (frame: number[]): Rect => ({ x: frame[0], y: frame[1], w: frame[2], h: frame[3] });

export const rgbString = ([r, g, b]: RGB) => `rgb(${r},${g},${b})`;

export function findCard(img: Raster): Rect {
  const rows: number[] = [];
  for (let y = 0; y < img.height; y++) {
    let count = 0;
    for (let x = 0; x < img.width; x++) if (isLime(pixel(img, x, y))) count++;
    if (count > img.width * 0.5) rows.push(y);
  }
  if (rows.length === 0) throw new Error("lime card not found");
  const top = rows[0];
  let bottom = top;
  for (const y of rows) if (y - bottom <= 8) bottom = y;
  const mid = Math.round((top + bottom) / 2);
  let left = 0;
  while (left < img.width && !isLime(pixel(img, left, mid))) left++;
  let right = img.width - 1;
  while (right > left && !isLime(pixel(img, right, mid))) right--;
  return { x: left, y: top, w: right - left + 1, h: bottom - top + 1 };
}

function longestDarkRun(img: Raster, y: number, from: number, to: number): { start: number; length: number } {
  let best = { start: 0, length: 0 };
  let start = -1;
  for (let x = from; x <= to; x++) {
    if (isDark(pixel(img, x, y))) {
      if (start < 0) start = x;
      if (x - start + 1 > best.length) best = { start, length: x - start + 1 };
    } else {
      start = -1;
    }
  }
  return best;
}

export type ProgressBar = Rect & { track: string; bg: string };

export function findProgressBar(img: Raster, card: Rect): { bar: ProgressBar; fill: number } {
  const minRun = card.w * 0.2;
  const rows: { y: number; start: number; length: number }[] = [];
  for (let y = card.y; y < card.y + card.h; y++) {
    const run = longestDarkRun(img, y, card.x, card.x + card.w - 1);
    if (run.length >= minRun) rows.push({ y, ...run });
  }
  const bands: (typeof rows)[] = [];
  for (const row of rows) {
    const last = bands[bands.length - 1];
    if (last && last[last.length - 1].y === row.y - 1) last.push(row);
    else bands.push([row]);
  }
  const thin = bands.filter((b) => b.length <= 20);
  if (thin.length !== 1) throw new Error(`expected one progress bar inside the card, found ${thin.length}`);
  const band = thin[0];
  const top = band[0].y;
  const bottom = band[band.length - 1].y;
  const mid = Math.round((top + bottom) / 2);
  const start = Math.min(...band.map((r) => r.start));
  const background = pixel(img, Math.round(card.x + card.w / 2), Math.max(card.y, top - 12));
  const midRow = band.find((r) => r.y === mid)!;
  let end = midRow.start + midRow.length;
  while (end < card.x + card.w && distance(pixel(img, end, mid), background) > 12) end++;
  const track = pixel(img, Math.max(start, end - 12), mid);
  const bg = pixel(img, Math.round(start + (end - start) * 0.7), top - 5);
  return {
    bar: { x: start, y: top, w: end - start, h: bottom - top + 1, track: rgbString(track), bg: rgbString(bg) },
    fill: midRow.length,
  };
}

export function findWidestProgressBar(running: Raster[]): ProgressBar {
  const found = running.flatMap((img) => {
    try {
      return [findProgressBar(img, findCard(img))];
    } catch {
      return [];
    }
  });
  if (found.length === 0) throw new Error("no running capture shows the progress bar");
  return found.reduce((best, next) => (next.fill > best.fill ? next : best)).bar;
}

export const SURFACE: RGB = [20, 20, 20];

export function findCommits(img: Raster, anchors: Rect[]): { area: Rect & { bg: string }; rows: Rect[] } {
  if (anchors.length === 0) throw new Error("no recent commit rows to anchor to");
  const sorted = [...anchors].sort((a, b) => a.y - b.y);
  const first = sorted[0];
  const last = sorted[sorted.length - 1];
  const isSurface = (x: number, y: number) => distance(pixel(img, x, y), SURFACE) <= 2;
  const column = first.x;
  let top = first.y - 1;
  while (top > 0 && !isSurface(column, top)) top--;
  while (top > 0 && isSurface(column, top - 1)) top--;
  let bottom = last.y + last.h;
  while (bottom < img.height - 1 && !isSurface(column, bottom)) bottom++;
  while (bottom + 1 < img.height && isSurface(column, bottom + 1)) bottom++;
  const probe = Math.round((top + first.y) / 2);
  let left = column;
  while (left > 0 && isSurface(left - 1, probe)) left--;
  let right = column;
  while (right + 1 < img.width && isSurface(right + 1, probe)) right++;
  const area = { x: left, y: top, w: right - left + 1, h: bottom - top + 1, bg: rgbString(SURFACE) };
  const isDivider = (y: number) => {
    const from = Math.round(left + area.w * 0.2);
    const sample = pixel(img, from, y);
    if (distance(sample, SURFACE) <= 2) return false;
    for (let x = from; x <= left + area.w * 0.8; x += 4) if (distance(pixel(img, x, y), sample) > 2) return false;
    return true;
  };
  const edges = [top];
  for (let i = 1; i < sorted.length; i++) {
    let divider = -1;
    for (let y = sorted[i - 1].y + sorted[i - 1].h; y < sorted[i].y && divider < 0; y++) if (isDivider(y)) divider = y;
    if (divider < 0) throw new Error(`no divider between recent commit rows ${i} and ${i + 1}`);
    edges.push(divider);
  }
  edges.push(bottom + 1);
  const rows = edges.slice(0, -1).map((y, i) => ({ x: left, y, w: area.w, h: edges[i + 1] - y }));
  return { area, rows };
}

export function measureCapture(
  shots: { idle: Raster; running: Raster[]; done: Raster },
  frames: Record<string, ElementFrames>,
): CaptureLayout {
  const need = (shot: string, key: string) => {
    const list = frames[shot]?.[key];
    if (!list || list.length === 0) throw new Error(`frames.json has no ${key} in ${shot}`);
    return list.map(toRect);
  };
  const card = findCard(shots.idle);
  const bar = findWidestProgressBar(shots.running);
  const commits = findCommits(shots.done, need("05-home-done", "commitRows"));
  return {
    screen: { width: shots.idle.width, height: shots.idle.height },
    card,
    cardHalo: rgbString(pixel(shots.idle, Math.round(card.x + card.w / 2), card.y + card.h + 4)),
    topZone: need("01-home-idle", "topZone")[0],
    chipRow: need("01-home-idle", "chipRow")[0],
    bar,
    commitsArea: commits.area,
    commitRows: commits.rows,
    historyTab: need("05-home-done", "historyTab")[0],
  };
}
