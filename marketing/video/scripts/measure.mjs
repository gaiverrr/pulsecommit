import { writeFileSync } from "node:fs";
import { join } from "node:path";
import { measureScreens } from "./decode.mjs";

const root = new URL("..", import.meta.url).pathname;
const screens = process.argv[2] ?? join(root, "public/screens");
const target = process.argv[3] ?? join(root, "src/capture-layout.ts");

const layout = measureScreens(screens);
writeFileSync(
  target,
  `import type { CaptureLayout } from "./measure.ts";\n\nexport const CAPTURE: CaptureLayout = ${JSON.stringify(layout, null, 2)};\n`,
);
console.log(`measured ${screens} -> ${target}`);
console.log(JSON.stringify({ card: layout.card, bar: layout.bar, commitsArea: layout.commitsArea }));
