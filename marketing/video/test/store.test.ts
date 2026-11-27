import { test } from "node:test";
import assert from "node:assert/strict";
import { STORE_SHOTS, STORE_SIZE, storeFileName } from "../src/store.ts";

test("store stills use Apple's 6.9-inch portrait size", () => {
  assert.deepEqual(STORE_SIZE, { width: 1320, height: 2868 });
});

test("six stills in the 1.0.2 order with the canvas captions", () => {
  assert.deepEqual(
    STORE_SHOTS.map((s) => s.title),
    [
      "Apple Health, every evening, to your AI agent",
      "POST to any endpoint you own",
      "One commit per day, in your own repo",
      "Export now, or let Shortcuts run it",
      "Telegram, GitHub and your webhook",
      "Today at 21:00 or yesterday at 08:30",
    ],
  );
  assert.deepEqual(
    STORE_SHOTS.map((s) => s.screen),
    ["telegram", "store-webhook", "store-history", "store-home", "store-destinations", "store-automate"],
  );
});

test("output files are numbered in order", () => {
  assert.deepEqual(
    STORE_SHOTS.map((_, i) => storeFileName(i)),
    ["01-telegram.png", "02-webhook.png", "03-history.png", "04-home.png", "05-destinations.png", "06-automate.png"],
  );
});

test("every still has a kicker and no third-party agent names", () => {
  for (const shot of STORE_SHOTS) {
    assert.ok(shot.kicker.length > 0, shot.title);
    for (const name of [/openclaw/i, /hermes/i, /claude/i]) {
      assert.doesNotMatch(`${shot.kicker} ${shot.title}`, name);
    }
  }
});
