import { ISLAND, SCREEN } from "./layout";

type ScreenSize = { width: number; height: number };

export const Phone: React.FC<{ height: number; screen?: ScreenSize; children: React.ReactNode }> = ({
  height,
  screen = SCREEN,
  children,
}) => {
  const bezel = Math.round(height * 0.014);
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
        background: "#1a1a1a",
        boxShadow: "inset 0 0 0 2px rgba(255,255,255,0.14)",
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
  const bezel = Math.round(height * 0.014);
  return (screen.width * (height - bezel * 2)) / screen.height + bezel * 2;
}
