import { ISLAND, SCREEN } from "./layout";

export const Phone: React.FC<{ height: number; children: React.ReactNode }> = ({ height, children }) => {
  const bezel = Math.round(height * 0.014);
  const screenH = height - bezel * 2;
  const scale = screenH / SCREEN.height;
  const screenW = SCREEN.width * scale;
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
            width: SCREEN.width,
            height: SCREEN.height,
            transform: `scale(${scale})`,
            transformOrigin: "0 0",
          }}
        >
          {children}
          <div
            style={{
              position: "absolute",
              left: (SCREEN.width - ISLAND.w) / 2,
              top: ISLAND.top,
              width: ISLAND.w,
              height: ISLAND.h,
              borderRadius: ISLAND.h / 2,
              background: "#000",
            }}
          />
        </div>
      </div>
    </div>
  );
};

export function phoneWidth(height: number): number {
  const bezel = Math.round(height * 0.014);
  return (SCREEN.width * (height - bezel * 2)) / SCREEN.height + bezel * 2;
}
