import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, rmSync, statSync } from "node:fs";
import { join } from "node:path";

const root = new URL("..", import.meta.url).pathname;
const out = join(root, "out");
const maxBytes = Number(process.env.HERO_MAX_BYTES ?? 1_500_000);
const metaPath = join(root, "public/screens/meta.json");
const date = existsSync(metaPath)
  ? JSON.parse(readFileSync(metaPath, "utf8")).date
  : new Date().toISOString().slice(0, 10);

const run = (cmd, args) => execFileSync(cmd, args, { cwd: root, stdio: ["ignore", "inherit", "inherit"] });
const size = (file) => statSync(file).size;

function encode(master, target, codecArgs, crfs) {
  for (const crf of crfs) {
    run("ffmpeg", ["-v", "error", "-y", "-i", master, ...codecArgs(crf), "-an", "-r", "60", target]);
    const bytes = size(target);
    console.log(`  ${target.replace(root, "")} crf ${crf}: ${bytes} bytes`);
    if (bytes <= maxBytes) return;
  }
  throw new Error(`${target} stays above ${maxBytes} bytes`);
}

const h264 = (crf) => [
  "-c:v", "libx264", "-preset", "slow", "-tune", "animation", "-crf", String(crf),
  "-pix_fmt", "yuv420p", "-movflags", "+faststart",
];
const vp9 = (crf) => [
  "-c:v", "libvpx-vp9", "-crf", String(crf), "-b:v", "0", "-row-mt", "1",
  "-deadline", "good", "-cpu-used", "2", "-pix_fmt", "yuv420p",
];
const range = (from, to, step) => Array.from({ length: Math.floor((to - from) / step) + 1 }, (_, i) => from + i * step);

mkdirSync(out, { recursive: true });

for (const [composition, name] of [["HeroLoop", "hero"], ["HeroLoopWide", "hero-wide"]]) {
  const master = join(out, `.master-${name}.mp4`);
  console.log(`==> ${composition}`);
  run("npx", [
    "remotion", "render", composition, master,
    "--codec=h264", "--crf=10", "--muted", "--log=warn",
    `--props=${JSON.stringify({ date })}`,
  ]);
  encode(master, join(out, `${name}.mp4`), h264, range(23, 35, 2));
  encode(master, join(out, `${name}.webm`), vp9, range(34, 50, 3));
  run("ffmpeg", ["-v", "error", "-y", "-i", master, "-frames:v", "1", "-q:v", "3", join(out, `${name}-poster.jpg`)]);
  run("ffmpeg", [
    "-v", "error", "-y", "-i", master,
    "-vf", "select='not(mod(n\\,60))',scale=270:-1,tile=10x1:padding=8:color=0x0a0a0a",
    "-frames:v", "1", "-q:v", "4", join(out, `${name}-strip.jpg`),
  ]);
  rmSync(master);
}
