import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { STORE_SHOTS, STORE_SIZE, storeFileName } from "../src/store.ts";

const root = new URL("..", import.meta.url).pathname;
const screenshots = join(root, "../screenshots");
const out = join(screenshots, "out");
const sheet = join(screenshots, "preview/contact-sheet.jpg");
const maxSheetBytes = 400 * 1024;
const metaPath = join(root, "public/store/meta.json");
const date = existsSync(metaPath)
  ? JSON.parse(readFileSync(metaPath, "utf8")).date
  : new Date().toISOString().slice(0, 10);

const run = (cmd, args) => execFileSync(cmd, args, { cwd: root, stdio: ["ignore", "inherit", "inherit"] });
const probe = (file) =>
  execFileSync("ffprobe", [
    "-v", "error", "-select_streams", "v:0",
    "-show_entries", "stream=width,height,pix_fmt", "-of", "csv=p=0", file,
  ]).toString().trim();

rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });
mkdirSync(join(screenshots, "preview"), { recursive: true });
const work = mkdtempSync(join(tmpdir(), "pulse-store-"));

const files = STORE_SHOTS.map((shot, index) => {
  const raw = join(work, `${index}.png`);
  const target = join(out, storeFileName(index));
  console.log(`==> ${storeFileName(index)}: ${shot.title}`);
  run("npx", [
    "remotion", "still", "StoreShot", raw,
    "--image-format=png", "--log=warn",
    `--props=${JSON.stringify({ index, date })}`,
  ]);
  run("ffmpeg", ["-v", "error", "-y", "-i", raw, "-vf", "format=rgb24", "-pix_fmt", "rgb24", target]);
  const info = probe(target);
  if (info !== `${STORE_SIZE.width},${STORE_SIZE.height},rgb24`) {
    throw new Error(`${target}: expected ${STORE_SIZE.width}x${STORE_SIZE.height} rgb24, got ${info}`);
  }
  return target;
});
rmSync(work, { recursive: true, force: true });

const inputs = files.flatMap((file) => ["-i", file]);
const tiles = files.map((_, i) => `[${i}:v]scale=330:-1,pad=iw+16:ih+32:8:16:color=0x0a0a0a[s${i}]`).join(";");
const stack = files.map((_, i) => `[s${i}]`).join("");
const filter = `${tiles};${stack}hstack=inputs=${files.length},pad=iw+16:ih:8:0:color=0x0a0a0a,format=yuvj420p[row]`;
for (const q of [4, 6, 8, 10, 14, 20]) {
  run("ffmpeg", [
    "-v", "error", "-y", ...inputs,
    "-filter_complex", filter,
    "-map", "[row]", "-frames:v", "1", "-q:v", String(q), sheet,
  ]);
  const bytes = statSync(sheet).size;
  console.log(`  contact-sheet.jpg q ${q}: ${bytes} bytes`);
  if (bytes < maxSheetBytes) break;
}
if (statSync(sheet).size >= maxSheetBytes) throw new Error("contact sheet stays at 400 KB or more");
