import { execFileSync } from "node:child_process";

export function decode(file) {
  const [width, height] = execFileSync("ffprobe", [
    "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "csv=p=0", file,
  ]).toString().trim().split(",").map(Number);
  const data = execFileSync("ffmpeg", ["-v", "error", "-i", file, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], {
    maxBuffer: width * height * 3 + 1024,
  });
  return { width, height, data: new Uint8Array(data.buffer, data.byteOffset, data.length) };
}
