import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { measureCapture } from "../src/measure.ts";
import { decode } from "./decode.mjs";

const root = new URL("..", import.meta.url).pathname;
const screens = process.argv[2] ?? join(root, "public/screens");
const target = process.argv[3] ?? join(root, "src/capture-layout.ts");

const frames = JSON.parse(readFileSync(join(screens, "frames.json"), "utf8"));
const layout = measureCapture(
  {
    idle: decode(join(screens, "01-home-idle.png")),
    running: decode(join(screens, "03-home-running-b.png")),
    done: decode(join(screens, "05-home-done.png")),
  },
  frames,
);
writeFileSync(
  target,
  `import type { CaptureLayout } from "./measure.ts";\n\nexport const CAPTURE: CaptureLayout = ${JSON.stringify(layout, null, 2)};\n`,
);
console.log(`measured ${screens} -> ${target}`);
console.log(JSON.stringify({ card: layout.card, bar: layout.bar, commitsArea: layout.commitsArea }));
