import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { CAPTURE } from "../src/capture-layout.ts";
import { HOME, SCREEN } from "../src/layout.ts";
import { type RGB, type Raster, type Rect, findCard, findCommits, findProgressBar, measureCapture } from "../src/measure.ts";

const screens = new URL("../public/screens/", import.meta.url).pathname;

const contains = (outer: Rect, inner: Rect) =>
  inner.x >= outer.x && inner.y >= outer.y && inner.x + inner.w <= outer.x + outer.w && inner.y + inner.h <= outer.y + outer.h;

const containsPoint = (outer: Rect, p: { x: number; y: number }) =>
  p.x >= outer.x && p.x <= outer.x + outer.w && p.y >= outer.y && p.y <= outer.y + outer.h;

function raster(width: number, height: number, bg: RGB): Raster & { fill: (r: Rect, c: RGB) => void } {
  const data = new Uint8Array(width * height * 3);
  const fill = (r: Rect, c: RGB) => {
    for (let y = r.y; y < r.y + r.h; y++)
      for (let x = r.x; x < r.x + r.w; x++) data.set(c, (y * width + x) * 3);
  };
  fill({ x: 0, y: 0, w: width, h: height }, bg);
  return { width, height, data, fill };
}

const LIME: RGB = [164, 240, 58];
const TRACK: RGB = [139, 204, 49];
const BLACK: RGB = [0, 0, 0];
const BG: RGB = [10, 10, 10];

test("detector finds the lime card and the progress bar on a synthetic capture", () => {
  const img = raster(400, 600, BG);
  img.fill({ x: 20, y: 100, w: 360, h: 240 }, LIME);
  img.fill({ x: 30, y: 120, w: 100, h: 30 }, BLACK);
  img.fill({ x: 40, y: 260, w: 320, h: 3 }, TRACK);
  img.fill({ x: 40, y: 260, w: 128, h: 3 }, BLACK);
  const card = findCard(img);
  assert.deepEqual(card, { x: 20, y: 100, w: 360, h: 240 });
  const bar = findProgressBar(img, card);
  assert.deepEqual({ x: bar.x, y: bar.y, w: bar.w, h: bar.h }, { x: 40, y: 260, w: 320, h: 3 });
  assert.equal(bar.track, "rgb(139,204,49)");
  assert.equal(bar.bg, "rgb(164,240,58)");
});

test("detector splits the recent commits card at its dividers", () => {
  const img = raster(400, 600, BG);
  img.fill({ x: 20, y: 20, w: 360, h: 100 }, LIME);
  img.fill({ x: 22, y: 200, w: 356, h: 300 }, [20, 20, 20]);
  img.fill({ x: 60, y: 300, w: 300, h: 1 }, [37, 37, 37]);
  img.fill({ x: 60, y: 400, w: 300, h: 1 }, [37, 37, 37]);
  img.fill({ x: 80, y: 260, w: 60, h: 10 }, [250, 250, 250]);
  const { area, rows } = findCommits(img, findCard(img));
  assert.deepEqual({ x: area.x, y: area.y, w: area.w, h: area.h }, { x: 22, y: 200, w: 356, h: 300 });
  assert.deepEqual(rows.map((r) => [r.y, r.y + r.h]), [[200, 300], [300, 400], [400, 500]]);
});

test("press crop is the whole big button from the exported frames", () => {
  const pad = CAPTURE.topZone.x - CAPTURE.card.x;
  assert.equal(pad, Math.round(20 * (SCREEN.width / 402)));
  const fromFrames = {
    x: CAPTURE.topZone.x - pad,
    y: CAPTURE.topZone.y - pad,
    w: CAPTURE.topZone.w + 2 * pad,
    h: CAPTURE.chipRow.y + CAPTURE.chipRow.h + pad - (CAPTURE.topZone.y - pad),
  };
  for (const key of ["x", "y", "w", "h"] as const) {
    assert.ok(Math.abs(HOME.pressCrop[key] - fromFrames[key]) <= 2, `${key}: ${HOME.pressCrop[key]} vs ${fromFrames[key]}`);
  }
  assert.ok(contains(HOME.pressCrop, CAPTURE.chipRow));
  assert.ok(contains(HOME.pressCrop, CAPTURE.topZone));
});

test("progress overlay sits on the real bar inside the top zone", () => {
  const { x, y, w, h } = HOME.progressTrack;
  assert.deepEqual({ x, y, w, h }, { x: CAPTURE.bar.x, y: CAPTURE.bar.y, w: CAPTURE.bar.w, h: CAPTURE.bar.h });
  assert.ok(contains(CAPTURE.topZone, HOME.progressTrack));
  assert.ok(h <= 12, String(h));
  assert.ok(Math.abs(x - CAPTURE.topZone.x) <= 2 && Math.abs(w - CAPTURE.topZone.w) <= 2);
});

test("tap ripples land on their buttons", () => {
  assert.ok(containsPoint(CAPTURE.topZone, HOME.exportTap));
  assert.ok(containsPoint(CAPTURE.historyTab, HOME.historyTab));
});

test("commit rows tile the recent commits card below the button", () => {
  const area = HOME.commitsArea;
  assert.ok(area.y > HOME.card.y + HOME.card.h);
  assert.equal(HOME.commitRows.length, 4);
  assert.equal(HOME.commitRows[0][0], area.y);
  assert.equal(HOME.commitRows[HOME.commitRows.length - 1][1], area.y + area.h);
  for (let i = 1; i < HOME.commitRows.length; i++) assert.equal(HOME.commitRows[i][0], HOME.commitRows[i - 1][1]);
});

test("committed layout matches the current captures", { skip: !existsSync(join(screens, "frames.json")) }, async () => {
  const { decode } = await import("../scripts/decode.mjs");
  const measured = measureCapture(
    {
      idle: decode(join(screens, "01-home-idle.png")),
      running: decode(join(screens, "03-home-running-b.png")),
      done: decode(join(screens, "05-home-done.png")),
    },
    JSON.parse(readFileSync(join(screens, "frames.json"), "utf8")),
  );
  assert.deepEqual(measured, CAPTURE);
});
