import { color } from "./theme";

const INK = "#0a0a0a";
const STROKE = 6;

export const agentPalette = {
  base: "#6ab2f2",
  shade: "#3f86cc",
  deep: "#13253a",
  steel: "#d8e6f2",
};

type AvatarProps = { size: number };

const Frame: React.FC<AvatarProps & { label: string; children: React.ReactNode }> = ({ size, label, children }) => (
  <svg
    width={size}
    height={size}
    viewBox="0 0 100 100"
    role="img"
    aria-label={label}
    style={{ display: "block", flexShrink: 0 }}
    shapeRendering="geometricPrecision"
  >
    {children}
  </svg>
);

export const PulseBotAvatar: React.FC<AvatarProps> = ({ size }) => (
  <Frame size={size} label="pulse bot">
    <defs>
      <clipPath id="pulse-bot-clip">
        <circle cx={50} cy={50} r={50} />
      </clipPath>
    </defs>
    <g clipPath="url(#pulse-bot-clip)">
      <rect width={100} height={100} fill="#1d2a12" />
      <line x1={50} y1={30} x2={50} y2={15} stroke={color.accent} strokeWidth={STROKE} strokeLinecap="round" />
      <line x1={38} y1={11} x2={62} y2={11} stroke={color.accent} strokeWidth={STROKE - 2} strokeLinecap="round" />
      <circle cx={50} cy={11} r={6} fill="#1d2a12" stroke={color.accent} strokeWidth={STROKE - 2} />
      <rect x={10} y={50} width={10} height={18} rx={5} fill={color.accent} />
      <rect x={80} y={50} width={10} height={18} rx={5} fill={color.accent} />
      <circle cx={50} cy={62} r={36} fill={color.accent} />
      <rect x={25} y={42} width={50} height={38} rx={17} fill={INK} />
      <circle cx={38.5} cy={54} r={6} fill={color.accent} />
      <circle cx={61.5} cy={54} r={6} fill={color.accent} />
      <circle cx={40.5} cy={52} r={2} fill={INK} />
      <circle cx={63.5} cy={52} r={2} fill={INK} />
      <polyline
        points="29,70 40,70 44,65 48,76 53,61 57,70 71,70"
        fill="none"
        stroke={color.accent}
        strokeWidth={STROKE - 2}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <ellipse cx={26} cy={72} rx={4} ry={2.5} fill="#ff8fa3" opacity={0.75} />
      <ellipse cx={74} cy={72} rx={4} ry={2.5} fill="#ff8fa3" opacity={0.75} />
    </g>
  </Frame>
);

export const HealthAgentAvatar: React.FC<AvatarProps & { blink?: boolean }> = ({ size, blink = false }) => {
  const p = agentPalette;
  return (
    <Frame size={size} label="Health agent">
      <defs>
        <clipPath id="health-agent-clip">
          <circle cx={50} cy={50} r={50} />
        </clipPath>
      </defs>
      <g clipPath="url(#health-agent-clip)">
        <rect width={100} height={100} fill={p.deep} />
        <path d="M14,104 C14,84 30,78 50,78 C70,78 86,84 86,104 Z" fill="#f4f8fb" />
        <path d="M44,78 L50,90 L56,78 Z" fill={p.shade} />
        <path
          d="M30,80 C26,92 34,98 42,94"
          fill="none"
          stroke={INK}
          strokeWidth={STROKE - 2}
          strokeLinecap="round"
        />
        <path
          d="M70,80 C75,90 70,96 64,96"
          fill="none"
          stroke={INK}
          strokeWidth={STROKE - 2}
          strokeLinecap="round"
        />
        <circle cx={62} cy={96} r={5} fill={p.steel} stroke={INK} strokeWidth={STROKE - 3} />
        <rect x={11} y={40} width={10} height={16} rx={4} fill={p.steel} stroke={INK} strokeWidth={STROKE - 3} />
        <rect x={79} y={40} width={10} height={16} rx={4} fill={p.steel} stroke={INK} strokeWidth={STROKE - 3} />
        <circle cx={50} cy={48} r={33} fill={p.base} />
        <path d="M17,48 A33,33 0 0 0 83,48 A33,27 0 0 1 17,48 Z" fill={p.shade} opacity={0.55} />
        <path d="M18,36 C30,26 70,26 82,36" fill="none" stroke={INK} strokeWidth={STROKE - 1} strokeLinecap="round" />
        <circle cx={33} cy={26} r={11} fill={p.steel} stroke={INK} strokeWidth={STROKE - 2} />
        <circle cx={33} cy={26} r={3.5} fill={INK} />
        <path d="M27,21 A8,8 0 0 1 35,18" fill="none" stroke="#ffffff" strokeWidth={2.5} strokeLinecap="round" />
        {blink ? (
          <>
            <path d="M33,50 Q38,53 43,50" fill="none" stroke={INK} strokeWidth={STROKE - 2} strokeLinecap="round" />
            <path d="M57,50 Q62,53 67,50" fill="none" stroke={INK} strokeWidth={STROKE - 2} strokeLinecap="round" />
          </>
        ) : (
          <>
            <circle cx={38} cy={50} r={5} fill={INK} />
            <circle cx={62} cy={50} r={5} fill={INK} />
            <rect x={31} y={42.5} width={14} height={6.5} fill={p.base} />
            <rect x={55} y={42.5} width={14} height={6.5} fill={p.base} />
            <line x1={32} y1={46} x2={44} y2={46} stroke={INK} strokeWidth={STROKE - 3} strokeLinecap="round" />
            <line x1={56} y1={46} x2={68} y2={46} stroke={INK} strokeWidth={STROKE - 3} strokeLinecap="round" />
          </>
        )}
        <path d="M55,39 Q62,34 69,38" fill="none" stroke={INK} strokeWidth={STROKE - 2} strokeLinecap="round" />
        <path d="M40,63 Q52,69 64,59" fill="none" stroke={INK} strokeWidth={STROKE - 2} strokeLinecap="round" />
        <path d="M62,57 L66,60" fill="none" stroke={INK} strokeWidth={STROKE - 3} strokeLinecap="round" />
        <ellipse cx={29} cy={60} rx={4} ry={2.5} fill="#ff8fa3" opacity={0.6} />
      </g>
    </Frame>
  );
};

export const HealthLogAvatar: React.FC<AvatarProps> = ({ size }) => (
  <Frame size={size} label="Health log">
    <circle cx={50} cy={50} r={50} fill={color.accent} />
    <path
      d="M50,80 L24,54 C14,44 18,26 33,25 C42,24 48,30 50,36 C52,30 58,24 67,25 C82,26 86,44 76,54 L62,68"
      fill="none"
      stroke={INK}
      strokeWidth={STROKE}
      strokeLinecap="round"
      strokeLinejoin="round"
    />
    <path d="M62,68 C62,74 66,78 72,78" fill="none" stroke={INK} strokeWidth={STROKE} strokeLinecap="round" />
    <circle cx={50} cy={80} r={6} fill={color.accent} stroke={INK} strokeWidth={STROKE - 1} />
    <circle cx={77} cy={78} r={5.5} fill={color.accent} stroke={INK} strokeWidth={STROKE - 1} />
    <circle cx={42} cy={47} r={3.5} fill={INK} />
    <circle cx={58} cy={47} r={3.5} fill={INK} />
    <path d="M45,55 Q50,60 55,55" fill="none" stroke={INK} strokeWidth={STROKE - 2.5} strokeLinecap="round" />
    <ellipse cx={34} cy={54} rx={4} ry={2.5} fill="#ff6f8a" opacity={0.7} />
    <ellipse cx={66} cy={54} rx={4} ry={2.5} fill="#ff6f8a" opacity={0.7} />
  </Frame>
);

export const AvatarSheet: React.FC = () => (
  <div
    style={{
      position: "absolute",
      inset: 0,
      background: "#17212b",
      display: "flex",
      alignItems: "center",
      justifyContent: "space-evenly",
    }}
  >
    <PulseBotAvatar size={44} />
    <HealthAgentAvatar size={44} />
    <HealthAgentAvatar size={44} blink />
    <HealthLogAvatar size={44} />
  </div>
);
