import { ISLAND, SCREEN } from "./layout";

type ScreenSize = { width: number; height: number };

const BEZEL = 0.02;
const EDGE = 0.004;

export const Phone: React.FC<{ height: number; screen?: ScreenSize; children: React.ReactNode }> = ({
  height,
  screen = SCREEN,
  children,
}) => {
  const bezel = Math.round(height * BEZEL);
  const edge = Math.max(3, Math.round(height * EDGE));
  const screenH = height - bezel * 2;
  const scale = screenH / screen.height;
  const screenW = screen.width * scale;
  const island = screen.width / SCREEN.width;
  const width = screenW + bezel * 2;
  const radius = width * 0.155;
  return (
    <div
      style={{
        position: "relative",
        width,
        height,
        borderRadius: radius,
        background: "#000",
        boxShadow: `inset 0 0 0 ${edge}px #3a3a3a`,
        padding: bezel,
        boxSizing: "border-box",
      }}
    >
      <div
        style={{
          position: "relative",
          width: screenW,
          height: screenH,
          borderRadius: radius - bezel,
          overflow: "hidden",
          clipPath: `inset(0 round ${radius - bezel}px)`,
          background: "#000",
        }}
      >
        <div
          style={{
            position: "absolute",
            left: 0,
            top: 0,
            width: screen.width,
            height: screen.height,
            transform: `scale(${scale})`,
            transformOrigin: "0 0",
          }}
        >
          {children}
          <div
            style={{
              position: "absolute",
              left: (screen.width - ISLAND.w * island) / 2,
              top: ISLAND.top * island,
              width: ISLAND.w * island,
              height: ISLAND.h * island,
              borderRadius: (ISLAND.h * island) / 2,
              background: "#000",
            }}
          />
        </div>
      </div>
    </div>
  );
};

export function phoneWidth(height: number, screen: ScreenSize = SCREEN): number {
  const bezel = Math.round(height * BEZEL);
  return (screen.width * (height - bezel * 2)) / screen.height + bezel * 2;
}
