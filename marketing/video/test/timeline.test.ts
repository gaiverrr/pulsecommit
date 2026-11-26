import { test } from "node:test";
import assert from "node:assert/strict";
import {
  DURATION,
  FPS,
  PERIODS,
  SCENES,
  captionAt,
  countUp,
  formatInt,
  progressAt,
  sceneAt,
} from "../src/timeline.ts";

test("loop is 10 seconds at 60 fps", () => {
  assert.equal(FPS, 60);
  assert.equal(DURATION, 600);
});

test("scenes cover the loop without gaps", () => {
  assert.equal(SCENES[0].from, 0);
  for (let i = 1; i < SCENES.length; i++) {
    assert.equal(SCENES[i].from, SCENES[i - 1].to, SCENES[i].name);
  }
  assert.equal(SCENES[SCENES.length - 1].to, DURATION);
});

test("first and last frame show the same scene and caption", () => {
  assert.equal(sceneAt(0), "home-idle");
  assert.equal(sceneAt(DURATION - 1), "home-idle");
  assert.equal(captionAt(0).index, captionAt(DURATION - 1).index);
  assert.equal(captionAt(DURATION - 1).opacity, 1);
});

test("every periodic motion divides the loop", () => {
  for (const period of Object.values(PERIODS)) {
    assert.equal(DURATION % period, 0, String(period));
  }
});

test("progress runs from empty to full across the running scene", () => {
  const running = SCENES.find((s) => s.name === "running")!;
  assert.equal(progressAt(running.from), 0);
  assert.equal(progressAt(running.to), 1);
  assert.ok(progressAt((running.from + running.to) / 2) > 0.3);
});

test("counters land on their final value", () => {
  assert.equal(countUp(12483, 0, 10, 40), 0);
  assert.equal(countUp(12483, 40, 10, 40), 12483);
  assert.equal(countUp(12483, 500, 10, 40), 12483);
});

test("integers group thousands with a space like the app", () => {
  assert.equal(formatInt(12483), "12 483");
  assert.equal(formatInt(642), "642");
});
