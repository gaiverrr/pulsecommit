import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { measureCapture } from "../src/measure.ts";

export function decode(file) {
  const [width, height] = execFileSync("ffprobe", [
    "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "csv=p=0", file,
  ]).toString().trim().split(",").map(Number);
  const data = execFileSync("ffmpeg", ["-v", "error", "-i", file, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], {
    maxBuffer: width * height * 3 + 1024,
  });
  return { width, height, data: new Uint8Array(data.buffer, data.byteOffset, data.length) };
}

export function measureScreens(screens) {
  const shot = (name) => decode(join(screens, `${name}.png`));
  return measureCapture(
    {
      idle: shot("01-home-idle"),
      running: ["02-home-running-a", "03-home-running-b", "04-home-running-c"].map(shot),
      done: shot("05-home-done"),
    },
    JSON.parse(readFileSync(join(screens, "frames.json"), "utf8")),
  );
}
