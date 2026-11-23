// design-system.jsx — Pulse Commit primitives (dark terminal aesthetic)

const PC = {
  // Surfaces
  bg: '#0a0a0a',
  surface: '#141414',
  elevated: '#1c1c1c',
  raised: '#242424',
  divider: 'rgba(255,255,255,0.07)',
  hairline: 'rgba(255,255,255,0.1)',

  // Text
  text: '#fafafa',
  muted: '#a3a3a3',
  dim: '#737373',
  faint: '#525252',

  // Semantic
  success: '#00D26A',
  warn: '#FFAD33',
  error: '#FF453A',

  // Fonts
  fontUI: '-apple-system, "SF Pro", system-ui, sans-serif',
  fontMono: '"SF Mono", "JetBrains Mono", Menlo, ui-monospace, monospace',
};

// Accent picker — set via tweaks
const ACCENTS = {
  crimson:  { hue: '#FF3355', soft: 'rgba(255,51,85,0.16)', label: 'Crimson' },
  lime:     { hue: '#A4F03A', soft: 'rgba(164,240,58,0.16)', label: 'Lime' },
  electric: { hue: '#3D8BFD', soft: 'rgba(61,139,253,0.16)', label: 'Electric' },
  mono:     { hue: '#FAFAFA', soft: 'rgba(250,250,250,0.12)', label: 'Mono' },
};

// ─── Icons (lightweight SF-Symbols-like SVGs) ────────────────────
const Icon = ({ name, size = 20, color = 'currentColor', weight = 1.7 }) => {
  const paths = {
    'arrow-up-circle': <><circle cx="12" cy="12" r="10" /><path d="M12 16V8M8 12l4-4 4 4" strokeLinecap="round" strokeLinejoin="round" /></>,
    'arrow-up': <path d="M12 19V5M5 12l7-7 7 7" strokeLinecap="round" strokeLinejoin="round" />,
    'arrow-right': <path d="M5 12h14M12 5l7 7-7 7" strokeLinecap="round" strokeLinejoin="round" />,
    'chevron-right': <path d="M9 6l6 6-6 6" strokeLinecap="round" strokeLinejoin="round" />,
    'chevron-left': <path d="M15 6l-6 6 6 6" strokeLinecap="round" strokeLinejoin="round" />,
    'chevron-down': <path d="M6 9l6 6 6-6" strokeLinecap="round" strokeLinejoin="round" />,
    'chevron-updown': <><path d="M7 9l5-5 5 5M7 15l5 5 5-5" strokeLinecap="round" strokeLinejoin="round" /></>,
    'plus': <path d="M12 5v14M5 12h14" strokeLinecap="round" />,
    'check': <path d="M5 12l5 5L20 7" strokeLinecap="round" strokeLinejoin="round" />,
    'check-circle': <><circle cx="12" cy="12" r="10" /><path d="M8 12l3 3 5-6" strokeLinecap="round" strokeLinejoin="round" /></>,
    'x': <path d="M6 6l12 12M18 6L6 18" strokeLinecap="round" />,
    'x-circle': <><circle cx="12" cy="12" r="10" /><path d="M9 9l6 6M15 9l-6 6" strokeLinecap="round" /></>,
    'dot': <circle cx="12" cy="12" r="3" stroke="none" fill="currentColor" />,
    'lock': <><rect x="5" y="11" width="14" height="10" rx="2" /><path d="M8 11V7a4 4 0 018 0v4" /></>,
    'shield': <path d="M12 3l8 3v6c0 5-3.5 8.5-8 10-4.5-1.5-8-5-8-10V6l8-3z" strokeLinejoin="round" />,
    'eye': <><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z" /><circle cx="12" cy="12" r="3" /></>,
    'eye-off': <><path d="M3 3l18 18M10.5 6.3A10 10 0 0112 6c6.5 0 10 6 10 6a18 18 0 01-3 4M6.3 6.3C3.3 8 2 12 2 12s3.5 7 10 7c1.7 0 3.2-.4 4.5-1" /><path d="M9.5 9.5a3 3 0 004.2 4.2" /></>,
    // Sinks
    'github': <path d="M12 2C6.5 2 2 6.6 2 12.2c0 4.5 2.9 8.3 6.8 9.6.5.1.7-.2.7-.5v-1.8c-2.8.6-3.4-1.4-3.4-1.4-.5-1.2-1.1-1.5-1.1-1.5-.9-.6.1-.6.1-.6 1 .1 1.5 1 1.5 1 .9 1.6 2.4 1.1 3 .9.1-.7.4-1.1.6-1.4-2.2-.3-4.6-1.1-4.6-5 0-1.1.4-2 1-2.7-.1-.3-.4-1.3.1-2.7 0 0 .8-.3 2.8 1a9.5 9.5 0 015 0c1.9-1.3 2.8-1 2.8-1 .5 1.4.2 2.5.1 2.7.6.7 1 1.6 1 2.7 0 3.9-2.3 4.7-4.6 5 .4.3.7.9.7 1.9v2.8c0 .3.2.6.7.5A10.2 10.2 0 0022 12.2C22 6.6 17.5 2 12 2z" stroke="none" fill="currentColor" />,
    'paper-plane': <path d="M22 2L11 13M22 2l-7 20-4-9-9-4 20-7z" strokeLinejoin="round" strokeLinecap="round" />,
    // Nav
    'home': <path d="M3 12l9-9 9 9M5 10v10h5v-6h4v6h5V10" strokeLinejoin="round" strokeLinecap="round" />,
    'list': <><path d="M8 6h13M8 12h13M8 18h13" strokeLinecap="round" /><circle cx="3.5" cy="6" r="1" stroke="none" fill="currentColor" /><circle cx="3.5" cy="12" r="1" stroke="none" fill="currentColor" /><circle cx="3.5" cy="18" r="1" stroke="none" fill="currentColor" /></>,
    'plug': <path d="M9 7V3M15 7V3M5 7h14v5a7 7 0 01-14 0V7zM12 19v3" strokeLinecap="round" strokeLinejoin="round" />,
    'clock': <><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" strokeLinecap="round" /></>,
    'gear': <><circle cx="12" cy="12" r="3" /><path d="M19.4 15a1.7 1.7 0 00.3 1.8l.1.1a2 2 0 11-2.8 2.8l-.1-.1a1.7 1.7 0 00-1.8-.3 1.7 1.7 0 00-1 1.5V21a2 2 0 01-4 0v-.1a1.7 1.7 0 00-1.1-1.5 1.7 1.7 0 00-1.8.3l-.1.1a2 2 0 11-2.8-2.8l.1-.1a1.7 1.7 0 00.3-1.8 1.7 1.7 0 00-1.5-1H3a2 2 0 010-4h.1a1.7 1.7 0 001.5-1.1 1.7 1.7 0 00-.3-1.8l-.1-.1a2 2 0 112.8-2.8l.1.1a1.7 1.7 0 001.8.3H9a1.7 1.7 0 001-1.5V3a2 2 0 014 0v.1a1.7 1.7 0 001 1.5 1.7 1.7 0 001.8-.3l.1-.1a2 2 0 112.8 2.8l-.1.1a1.7 1.7 0 00-.3 1.8V9a1.7 1.7 0 001.5 1H21a2 2 0 010 4h-.1a1.7 1.7 0 00-1.5 1z" strokeLinejoin="round" /></>,
    // Health categories
    'heart': <path d="M20.8 4.6a5.5 5.5 0 00-7.8 0L12 5.6l-1-1a5.5 5.5 0 00-7.8 7.8l1 1L12 21l7.8-7.8 1-1a5.5 5.5 0 000-7.6z" strokeLinejoin="round" />,
    'wave': <path d="M2 12h3l2-7 4 14 3-10 2 6 2-3h4" strokeLinecap="round" strokeLinejoin="round" />,
    'flame': <path d="M12 2c-2 5 4 6 4 11a4 4 0 11-8 0c0-2 1-3 2-4-2-2 0-5 2-7z" strokeLinejoin="round" />,
    'shoe': <path d="M3 17V8h3l3 3h8a4 4 0 014 4v2H3z" strokeLinejoin="round" />,
    'moon': <path d="M21 12.8A9 9 0 1111.2 3a7 7 0 009.8 9.8z" strokeLinejoin="round" />,
    'scale': <><path d="M3 7h18l-2 12a2 2 0 01-2 2H7a2 2 0 01-2-2L3 7z" strokeLinejoin="round" /><path d="M8 7V5a4 4 0 018 0v2" /></>,
    'mind': <><circle cx="12" cy="12" r="9" /><path d="M9 10a3 3 0 016 0M9 16h6" strokeLinecap="round" /></>,
    'fork': <path d="M5 3v8m0 0a3 3 0 003 3v7m6-18v7M5 11h6m0 0a3 3 0 003 3" strokeLinecap="round" />,
    'route': <><circle cx="6" cy="6" r="3" /><circle cx="18" cy="18" r="3" /><path d="M9 6h6a4 4 0 014 4v4M15 18H9a4 4 0 01-4-4v-4" strokeLinecap="round" /></>,
    'lab': <path d="M9 3v6L4 19a2 2 0 002 3h12a2 2 0 002-3l-5-10V3M8 3h8M9 14h6" strokeLinecap="round" strokeLinejoin="round" />,
    // Tools
    'play': <path d="M6 4l14 8-14 8V4z" strokeLinejoin="round" fill="currentColor" stroke="none" />,
    'bolt': <path d="M13 2L4 14h7l-1 8 9-12h-7l1-8z" strokeLinejoin="round" />,
    'cloud': <path d="M6 19a4 4 0 010-8 6 6 0 0111-3 5 5 0 011 9.9" strokeLinejoin="round" />,
    'cloud-check': <><path d="M6 19a4 4 0 010-8 6 6 0 0111-3 5 5 0 011 9.9" strokeLinejoin="round" /><path d="M9 14l2 2 4-4" strokeLinecap="round" strokeLinejoin="round" /></>,
    'document': <path d="M14 3H6a2 2 0 00-2 2v14a2 2 0 002 2h12a2 2 0 002-2V9l-6-6z M14 3v6h6 M8 13h8 M8 17h6" strokeLinejoin="round" strokeLinecap="round" />,
    'terminal': <><path d="M4 17l5-5-5-5M12 19h8" strokeLinecap="round" strokeLinejoin="round" /></>,
    'commit': <><circle cx="12" cy="12" r="4" /><path d="M3 12h5M16 12h5" strokeLinecap="round" /></>,
    'branch': <path d="M6 3v12m12-6v6a3 3 0 01-3 3H9m9-12a3 3 0 100-6 3 3 0 000 6zM6 21a3 3 0 100-6 3 3 0 000 6zm0-18a3 3 0 100-6 3 3 0 000 6z" strokeLinecap="round" />,
    'sparkle': <path d="M12 3l2 7 7 2-7 2-2 7-2-7-7-2 7-2 2-7z" strokeLinejoin="round" />,
    'info': <><circle cx="12" cy="12" r="9" /><path d="M12 8v.01M11 12h1v4h1" strokeLinecap="round" /></>,
    'sidebar': <><rect x="3" y="4" width="18" height="16" rx="3" /><path d="M9 4v16" /></>,
  };
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color}
         strokeWidth={weight} style={{ flexShrink: 0, display: 'block' }}>
      {paths[name] || <circle cx="12" cy="12" r="9" />}
    </svg>
  );
};

// ─── Tab bar ──────────────────────────────────────────────────────
function TabBar({ active = 'home', accent = ACCENTS.crimson }) {
  const tabs = [
    { id: 'home',    icon: 'home',  label: 'Home' },
    { id: 'cats',    icon: 'list',  label: 'Categories' },
    { id: 'dests',   icon: 'plug',  label: 'Destinations' },
    { id: 'history', icon: 'clock', label: 'History' },
    { id: 'settings',icon: 'gear',  label: 'Settings' },
  ];
  return (
    <div style={{
      position: 'absolute', bottom: 0, left: 0, right: 0, zIndex: 30,
      paddingBottom: 26, paddingTop: 8,
      background: 'linear-gradient(180deg, rgba(10,10,10,0) 0%, rgba(10,10,10,0.96) 60%)',
      backdropFilter: 'blur(20px)', WebkitBackdropFilter: 'blur(20px)',
      borderTop: `0.5px solid ${PC.hairline}`,
    }}>
      <div style={{ display: 'flex', justifyContent: 'space-around', padding: '0 6px' }}>
        {tabs.map(t => {
          const on = t.id === active;
          return (
            <div key={t.id} style={{
              display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3,
              padding: '6px 4px', minWidth: 60,
              color: on ? accent.hue : PC.dim,
            }}>
              <Icon name={t.icon} size={22} weight={on ? 2 : 1.7} />
              <div style={{ fontSize: 10, fontWeight: 500, letterSpacing: 0.1 }}>{t.label}</div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

// ─── Card primitive ───────────────────────────────────────────────
function Card({ children, style = {}, padded = true, onClick }) {
  return (
    <div onClick={onClick} style={{
      background: PC.surface,
      border: `0.5px solid ${PC.divider}`,
      borderRadius: 16,
      padding: padded ? 16 : 0,
      ...style,
    }}>
      {children}
    </div>
  );
}

// ─── Mono code block ──────────────────────────────────────────────
function CodeBlock({ children, accent, style = {} }) {
  return (
    <div style={{
      fontFamily: PC.fontMono,
      fontSize: 12,
      lineHeight: 1.55,
      color: PC.muted,
      background: '#000',
      border: `0.5px solid ${PC.divider}`,
      borderRadius: 12,
      padding: '12px 14px',
      whiteSpace: 'pre-wrap',
      wordBreak: 'break-word',
      ...style,
    }}>
      {children}
    </div>
  );
}

// ─── Toggle ───────────────────────────────────────────────────────
function Toggle({ on = true, accent = ACCENTS.crimson, size = 'md' }) {
  const W = size === 'sm' ? 44 : 51;
  const H = size === 'sm' ? 26 : 31;
  const knob = H - 4;
  return (
    <div style={{
      width: W, height: H, borderRadius: H, position: 'relative',
      background: on ? accent.hue : '#3a3a3a',
      transition: 'background .15s',
      flexShrink: 0,
    }}>
      <div style={{
        position: 'absolute', top: 2, left: on ? W - knob - 2 : 2,
        width: knob, height: knob, borderRadius: knob,
        background: '#fff',
        boxShadow: '0 2px 4px rgba(0,0,0,0.3)',
        transition: 'left .15s',
      }} />
    </div>
  );
}

// ─── Header (custom — replaces nav bar) ───────────────────────────
function ScreenHeader({ title, subtitle, leading, trailing, accent }) {
  return (
    <div style={{ padding: '60px 20px 16px' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 14 }}>
        <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
          {leading}
        </div>
        <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
          {trailing}
        </div>
      </div>
      <div style={{
        fontSize: 32, fontWeight: 700, letterSpacing: -0.8, color: PC.text,
        lineHeight: 1.1,
      }}>{title}</div>
      {subtitle && (
        <div style={{
          fontFamily: PC.fontMono,
          fontSize: 12, color: PC.dim, marginTop: 8, letterSpacing: 0,
        }}>{subtitle}</div>
      )}
    </div>
  );
}

// ─── Pill ─────────────────────────────────────────────────────────
function Pill({ children, color, bg, mono, style = {} }) {
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 5,
      padding: '4px 10px', borderRadius: 99,
      background: bg || 'rgba(255,255,255,0.06)',
      color: color || PC.muted,
      fontSize: 11, fontWeight: 600, letterSpacing: 0.2,
      fontFamily: mono ? PC.fontMono : PC.fontUI,
      border: `0.5px solid ${PC.hairline}`,
      ...style,
    }}>{children}</span>
  );
}

// ─── Status dot ───────────────────────────────────────────────────
function StatusDot({ status = 'idle', accent }) {
  const colors = {
    idle: PC.dim,
    running: accent ? accent.hue : PC.warn,
    ok: PC.success,
    error: PC.error,
  };
  const c = colors[status];
  return (
    <span style={{
      display: 'inline-block', width: 8, height: 8, borderRadius: 8,
      background: c, boxShadow: status === 'running' ? `0 0 12px ${c}` : 'none',
      animation: status === 'running' ? 'pulse 1.4s infinite ease-in-out' : 'none',
      flexShrink: 0,
    }} />
  );
}

Object.assign(window, {
  PC, ACCENTS, Icon, TabBar, Card, CodeBlock, Toggle, ScreenHeader, Pill, StatusDot,
});
