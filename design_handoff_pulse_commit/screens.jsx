// screens.jsx — Pulse Commit screens
// All screens are 402×874 phone-content components, designed to render
// inside an IOSDevice frame (which provides status bar + dynamic island).

// ─── Shared phone wrapper ─────────────────────────────────────────
function Phone({ children, dark = true, tab, accent, noTabBar = false }) {
  return (
    <IOSDevice width={402} height={874} dark={dark}>
      <div style={{
        position: 'relative', height: '100%', overflow: 'hidden',
        background: PC.bg, color: PC.text,
        fontFamily: PC.fontUI,
      }}>
        <div style={{ height: '100%', overflowY: 'auto', paddingBottom: noTabBar ? 0 : 90 }}>
          {children}
        </div>
        {!noTabBar && <TabBar active={tab} accent={accent} />}
      </div>
    </IOSDevice>
  );
}

// ╔═════════════════════════════════════════════════════════════════╗
// ║  HOME — VARIANT A : "Big Button"                                 ║
// ║  Safe, focused. One huge Export Now button + last-commit card.   ║
// ╚═════════════════════════════════════════════════════════════════╝
function HomeA({ accent, state = 'idle', unlocked = false }) {
  const stateMap = {
    idle:    { label: 'Export Now',  sub: 'Since yesterday · ready to commit' },
    running: { label: 'Committing…', sub: 'fetching 1 day · 6 categories' },
    done:    { label: 'Export Now',  sub: 'Last commit · 2 min ago · ✓' },
    error:   { label: 'Retry Export',sub: 'Last attempt failed · GitHub 401' },
  };
  const s = stateMap[state];

  return (
    <Phone tab="home" accent={accent}>
      <ScreenHeader
        title="Pulse Commit"
        subtitle="v1.0.0 · iPhone 15 Pro · Europe/Lisbon"
        leading={<Pill mono>● {unlocked ? 'UNLOCKED' : '8 / 10 RUNS'}</Pill>}
        trailing={<Icon name="sidebar" size={22} color={PC.muted} />}
      />

      {/* THE BIG BUTTON */}
      <div style={{ padding: '8px 20px 24px' }}>
        <div style={{
          position: 'relative',
          background: accent.hue,
          borderRadius: 22,
          padding: '28px 24px',
          color: state === 'idle' || state === 'done' ? '#000' : '#fff',
          boxShadow: `0 0 0 1px ${accent.hue}, 0 24px 48px -16px ${accent.soft}`,
          overflow: 'hidden',
        }}>
          {/* ascii-style top label */}
          <div style={{
            fontFamily: PC.fontMono, fontSize: 11, opacity: 0.7,
            letterSpacing: 1.5, textTransform: 'uppercase', marginBottom: 4,
          }}>
            {state === 'error' ? '$ retry --since=yesterday' :
             state === 'running' ? '$ pulse commit --running' :
             '$ pulse commit --since=yesterday'}
          </div>
          <div style={{
            fontSize: 36, fontWeight: 700, letterSpacing: -1.2, lineHeight: 1.05,
          }}>{s.label}</div>
          <div style={{
            fontSize: 13, opacity: 0.8, marginTop: 8, fontFamily: PC.fontMono,
          }}>{s.sub}</div>
          {state === 'running' && (
            <div style={{
              marginTop: 16, height: 3, background: 'rgba(0,0,0,0.2)',
              borderRadius: 3, overflow: 'hidden',
            }}>
              <div style={{
                width: '62%', height: '100%', background: '#000',
                borderRadius: 3,
              }} />
            </div>
          )}
          <div style={{
            position: 'absolute', right: 18, top: 18,
            color: state === 'idle' || state === 'done' ? '#000' : '#fff',
          }}>
            <Icon name={state === 'error' ? 'arrow-up' : 'arrow-up-circle'} size={28} />
          </div>
        </div>
      </div>

      {/* LAST COMMIT */}
      <div style={{ padding: '0 20px 16px' }}>
        <div style={{
          fontFamily: PC.fontMono, fontSize: 10, color: PC.dim,
          letterSpacing: 1.5, marginBottom: 8, paddingLeft: 4,
        }}>LAST COMMIT</div>
        <Card style={{ padding: 0 }} padded={false}>
          <div style={{ padding: '14px 16px', display: 'flex', alignItems: 'center', gap: 10 }}>
            <Icon name="commit" size={18} color={state === 'error' ? PC.error : PC.success} />
            <span style={{
              fontFamily: PC.fontMono, fontSize: 13, color: PC.text, letterSpacing: 0,
            }}>a8f3c2d</span>
            <span style={{ fontSize: 13, color: PC.muted, flex: 1 }}>· main</span>
            <span style={{ fontFamily: PC.fontMono, fontSize: 11, color: PC.dim }}>2m ago</span>
          </div>
          <div style={{ height: 0.5, background: PC.divider }} />
          <div style={{ padding: '12px 16px', fontSize: 13, color: PC.muted, lineHeight: 1.5 }}>
            2026-05-13 · 12.5k steps · 1 workout · sleep 7h12m
          </div>
          <div style={{ height: 0.5, background: PC.divider }} />
          <div style={{
            padding: '10px 16px', display: 'flex', alignItems: 'center', gap: 14,
            fontSize: 12, color: PC.dim, fontFamily: PC.fontMono,
          }}>
            <span style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
              <Icon name="github" size={14} color={PC.success} />
              github
            </span>
            <span style={{ color: PC.faint }}>·</span>
            <span style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
              <Icon name="paper-plane" size={14} color={PC.success} />
              telegram
            </span>
            <span style={{ flex: 1 }} />
            <span style={{ color: PC.dim }}>14 files</span>
          </div>
        </Card>
      </div>

      {/* QUICK TOGGLES */}
      <div style={{ padding: '0 20px 16px' }}>
        <div style={{
          fontFamily: PC.fontMono, fontSize: 10, color: PC.dim,
          letterSpacing: 1.5, marginBottom: 8, paddingLeft: 4,
        }}>SINKS · NEXT RUN</div>
        <Card padded={false}>
          <SinkRow icon="github" label="GitHub" detail="user/health-data · main" on accent={accent} />
          <div style={{ height: 0.5, background: PC.divider, marginLeft: 56 }} />
          <SinkRow icon="paper-plane" label="Telegram" detail="@me · standard verbosity" on accent={accent} isLast />
        </Card>
      </div>

      {/* STATS STRIP */}
      <div style={{ padding: '0 20px 16px' }}>
        <div style={{
          fontFamily: PC.fontMono, fontSize: 10, color: PC.dim,
          letterSpacing: 1.5, marginBottom: 8, paddingLeft: 4,
        }}>TO BE EXPORTED · LIVE</div>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
          <StatTile label="Steps"    value="12 483" mono accent={accent} />
          <StatTile label="Active"   value="612" suffix="kcal" mono accent={accent} />
          <StatTile label="Sleep"    value="7h 12m" mono accent={accent} />
          <StatTile label="Workouts" value="1" mono accent={accent} />
        </div>
      </div>
    </Phone>
  );
}

function SinkRow({ icon, label, detail, on, accent, isLast }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', padding: '14px 16px', gap: 12 }}>
      <div style={{
        width: 32, height: 32, borderRadius: 8, background: PC.elevated,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        color: on ? PC.text : PC.dim,
      }}>
        <Icon name={icon} size={18} />
      </div>
      <div style={{ flex: 1 }}>
        <div style={{ fontSize: 15, fontWeight: 600, color: PC.text }}>{label}</div>
        <div style={{
          fontSize: 11, color: PC.dim, fontFamily: PC.fontMono, marginTop: 2,
        }}>{detail}</div>
      </div>
      <Toggle on={on} accent={accent} size="sm" />
    </div>
  );
}

function StatTile({ label, value, suffix, accent, mono }) {
  return (
    <div style={{
      background: PC.surface, borderRadius: 14,
      border: `0.5px solid ${PC.divider}`,
      padding: '12px 14px',
    }}>
      <div style={{
        fontSize: 10, color: PC.dim, letterSpacing: 1.5,
        fontFamily: PC.fontMono, textTransform: 'uppercase',
      }}>{label}</div>
      <div style={{
        marginTop: 6, fontSize: 22, fontWeight: 600,
        fontFamily: mono ? PC.fontMono : PC.fontUI,
        letterSpacing: -0.5, color: PC.text,
        display: 'flex', alignItems: 'baseline', gap: 4,
      }}>
        {value}
        {suffix && <span style={{ fontSize: 11, color: PC.dim, fontWeight: 500 }}>{suffix}</span>}
      </div>
    </div>
  );
}

// ╔═════════════════════════════════════════════════════════════════╗
// ║  HOME — VARIANT B : "Commit Graph"                                ║
// ║  Ambitious. GitHub-feel heatmap + activity feed.                  ║
// ╚═════════════════════════════════════════════════════════════════╝
function HomeB({ accent, state = 'idle', unlocked = false }) {
  // contribution grid — 14 cols × 7 rows
  const cells = [];
  for (let i = 0; i < 14 * 7; i++) {
    const intensity = Math.random();
    let v = 0;
    if (intensity > 0.2) v = 1;
    if (intensity > 0.5) v = 2;
    if (intensity > 0.75) v = 3;
    if (intensity > 0.9) v = 4;
    if (i < 4) v = 0; // future days
    cells.push(v);
  }

  const cellColor = (v) => {
    if (v === 0) return PC.elevated;
    if (v === 1) return `rgba(${hexToRgb(accent.hue)},0.25)`;
    if (v === 2) return `rgba(${hexToRgb(accent.hue)},0.5)`;
    if (v === 3) return `rgba(${hexToRgb(accent.hue)},0.8)`;
    return accent.hue;
  };

  return (
    <Phone tab="home" accent={accent}>
      <div style={{ padding: '60px 20px 0' }}>
        {/* mini-header */}
        <div style={{
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          marginBottom: 18,
        }}>
          <Pill mono>● {unlocked ? 'UNLOCKED' : '8 / 10'}</Pill>
          <Icon name="sidebar" size={22} color={PC.muted} />
        </div>

        {/* streak counter */}
        <div style={{
          fontFamily: PC.fontMono, fontSize: 11, color: PC.dim,
          letterSpacing: 1.5, marginBottom: 6,
        }}>CURRENT STREAK</div>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginBottom: 4 }}>
          <span style={{
            fontSize: 64, fontWeight: 700, letterSpacing: -3, color: accent.hue,
            fontFamily: PC.fontUI, fontVariantNumeric: 'tabular-nums',
            lineHeight: 1,
          }}>47</span>
          <span style={{ fontSize: 18, color: PC.muted, fontWeight: 500 }}>days</span>
        </div>
        <div style={{ fontSize: 13, color: PC.dim, marginBottom: 22 }}>
          Best: <span style={{ color: PC.muted }}>82 days</span> · This year: <span style={{ color: PC.muted }}>147 commits</span>
        </div>

        {/* heatmap */}
        <div style={{
          display: 'grid', gridTemplateColumns: 'repeat(14, 1fr)',
          gap: 4, marginBottom: 8,
        }}>
          {cells.map((v, i) => (
            <div key={i} style={{
              aspectRatio: '1', borderRadius: 3, background: cellColor(v),
              border: v === 0 ? `0.5px solid ${PC.divider}` : 'none',
            }} />
          ))}
        </div>
        <div style={{
          display: 'flex', justifyContent: 'space-between',
          fontFamily: PC.fontMono, fontSize: 10, color: PC.dim, marginBottom: 24,
        }}>
          <span>4 weeks ago</span>
          <div style={{ display: 'flex', gap: 4, alignItems: 'center' }}>
            <span>Less</span>
            {[0,1,2,3,4].map(v => (
              <div key={v} style={{ width: 9, height: 9, borderRadius: 2, background: cellColor(v) }} />
            ))}
            <span>More</span>
          </div>
        </div>
      </div>

      {/* primary action */}
      <div style={{ padding: '0 20px 22px' }}>
        <button style={{
          width: '100%', appearance: 'none', border: `1px solid ${accent.hue}`,
          background: accent.hue, color: '#000',
          padding: '16px 20px', borderRadius: 14,
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          fontFamily: PC.fontUI, cursor: 'pointer',
        }}>
          <div style={{ textAlign: 'left' }}>
            <div style={{
              fontFamily: PC.fontMono, fontSize: 10, opacity: 0.7,
              letterSpacing: 1.2, textTransform: 'uppercase',
            }}>commit yesterday</div>
            <div style={{ fontSize: 18, fontWeight: 700, letterSpacing: -0.3 }}>Export Now</div>
          </div>
          <Icon name="arrow-up" size={22} color="#000" weight={2.2} />
        </button>
      </div>

      {/* recent commits feed */}
      <div style={{ padding: '0 20px 16px' }}>
        <div style={{
          fontFamily: PC.fontMono, fontSize: 10, color: PC.dim,
          letterSpacing: 1.5, marginBottom: 10, paddingLeft: 4,
          display: 'flex', justifyContent: 'space-between',
        }}>
          <span>RECENT COMMITS</span>
          <span style={{ color: PC.faint }}>main · user/health</span>
        </div>
        <Card padded={false}>
          {[
            { hash: 'a8f3c2d', when: '2m', date: '2026-05-13', sum: '12.5k steps · 1 workout · 7h12m sleep', ok: true },
            { hash: '7b29e1f', when: '1d', date: '2026-05-12', sum: '8.9k steps · sleep 6h58m', ok: true },
            { hash: 'c4421a0', when: '2d', date: '2026-05-11', sum: '14.2k steps · 2 workouts · 8h04m', ok: true },
            { hash: '——————', when: '3d', date: '2026-05-10', sum: 'failed · GitHub 401 unauthorized', ok: false },
          ].map((c, i, arr) => (
            <React.Fragment key={c.hash + i}>
              <div style={{ padding: '12px 16px', display: 'flex', alignItems: 'center', gap: 12 }}>
                <Icon name="commit" size={16} color={c.ok ? accent.hue : PC.error} />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                    <span style={{ fontFamily: PC.fontMono, fontSize: 12, color: c.ok ? PC.text : PC.error }}>{c.hash}</span>
                    <span style={{ fontFamily: PC.fontMono, fontSize: 11, color: PC.dim }}>{c.date}</span>
                  </div>
                  <div style={{
                    fontSize: 12, color: PC.muted, marginTop: 2,
                    whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
                  }}>{c.sum}</div>
                </div>
                <span style={{ fontFamily: PC.fontMono, fontSize: 11, color: PC.dim }}>{c.when}</span>
              </div>
              {i < arr.length - 1 && <div style={{ height: 0.5, background: PC.divider, marginLeft: 44 }} />}
            </React.Fragment>
          ))}
        </Card>
      </div>
    </Phone>
  );
}

function hexToRgb(hex) {
  const m = hex.match(/#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})/i);
  return m ? `${parseInt(m[1],16)},${parseInt(m[2],16)},${parseInt(m[3],16)}` : '255,255,255';
}

// ╔═════════════════════════════════════════════════════════════════╗
// ║  FIRST-RUN / EMPTY STATE                                          ║
// ╚═════════════════════════════════════════════════════════════════╝
function FirstRun({ accent }) {
  return (
    <Phone tab="home" accent={accent}>
      <div style={{ padding: '60px 20px 0' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 32 }}>
          <Pill mono>● 10 / 10 RUNS · TRIAL</Pill>
          <Icon name="sidebar" size={22} color={PC.muted} />
        </div>

        <div style={{ textAlign: 'left', marginBottom: 32 }}>
          <div style={{
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
            width: 56, height: 56, borderRadius: 16,
            background: accent.soft, color: accent.hue, marginBottom: 18,
            border: `0.5px solid ${accent.hue}`,
          }}>
            <Icon name="terminal" size={28} weight={2} />
          </div>
          <div style={{ fontSize: 30, fontWeight: 700, letterSpacing: -0.8, lineHeight: 1.1 }}>
            Welcome to<br/>Pulse Commit
          </div>
          <div style={{ fontSize: 15, color: PC.muted, marginTop: 12, lineHeight: 1.45, maxWidth: 320 }}>
            Export your Apple Health data to <span style={{ color: PC.text }}>your own</span> Git repo and Telegram chat. No backend, no analytics, just your data.
          </div>
        </div>

        {/* setup steps */}
        <div style={{
          fontFamily: PC.fontMono, fontSize: 10, color: PC.dim,
          letterSpacing: 1.5, marginBottom: 10, paddingLeft: 4,
        }}>SETUP · 3 STEPS</div>
        <Card padded={false}>
          {[
            { n: 1, icon: 'heart',       label: 'Grant Health access',  detail: 'Read-only, 14 categories',         done: true,  cta: 'Granted' },
            { n: 2, icon: 'github',      label: 'Connect GitHub',       detail: 'Personal access token · repo scope', done: false, cta: 'Set up' },
            { n: 3, icon: 'paper-plane', label: 'Connect Telegram',     detail: 'Bot token · chat ID',               done: false, cta: 'Set up' },
          ].map((s, i, arr) => (
            <React.Fragment key={s.n}>
              <div style={{ padding: '14px 16px', display: 'flex', alignItems: 'center', gap: 12 }}>
                <div style={{
                  width: 30, height: 30, borderRadius: 8,
                  background: s.done ? accent.soft : PC.elevated,
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  color: s.done ? accent.hue : PC.muted,
                }}>
                  {s.done ? <Icon name="check" size={18} weight={2.5} /> :
                    <span style={{ fontFamily: PC.fontMono, fontSize: 14, fontWeight: 600 }}>{s.n}</span>}
                </div>
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: 15, fontWeight: 600, color: PC.text }}>{s.label}</div>
                  <div style={{ fontSize: 11, color: PC.dim, fontFamily: PC.fontMono, marginTop: 2 }}>{s.detail}</div>
                </div>
                <span style={{
                  fontSize: 12, fontWeight: 600,
                  color: s.done ? PC.success : accent.hue,
                  padding: '6px 10px',
                  borderRadius: 8,
                  background: s.done ? 'transparent' : accent.soft,
                  border: s.done ? `0.5px solid ${PC.divider}` : `0.5px solid ${accent.hue}`,
                }}>{s.cta}</span>
              </div>
              {i < arr.length - 1 && <div style={{ height: 0.5, background: PC.divider, marginLeft: 58 }} />}
            </React.Fragment>
          ))}
        </Card>

        <div style={{ marginTop: 22, fontFamily: PC.fontMono, fontSize: 11, color: PC.dim, padding: '0 4px', lineHeight: 1.6 }}>
          {'>'} Credentials stored in iOS Keychain only.<br/>
          {'>'} Nothing ever leaves your device except<br/>
          {'  '}to destinations you configure above.
        </div>
      </div>
    </Phone>
  );
}

// ╔═════════════════════════════════════════════════════════════════╗
// ║  CATEGORIES                                                       ║
// ╚═════════════════════════════════════════════════════════════════╝
function Categories({ accent }) {
  const groups = [
    {
      header: 'ACTIVITY',
      items: [
        { id: 'steps', icon: 'shoe',  name: 'Steps',          today: '12 483',    on: true },
        { id: 'dist',  icon: 'route', name: 'Distance',       today: '8.4 km',    on: true },
        { id: 'act',   icon: 'flame', name: 'Active energy',  today: '612 kcal',  on: true },
        { id: 'rings', icon: 'sparkle', name: 'Activity rings', today: 'stand 11h · exc 42m', on: true },
      ],
    },
    {
      header: 'HEART',
      items: [
        { id: 'hr',    icon: 'heart', name: 'Heart rate',           today: '— samples', on: true },
        { id: 'rhr',   icon: 'heart', name: 'Resting HR',           today: '58 bpm',    on: true },
        { id: 'hrv',   icon: 'wave',  name: 'HRV (SDNN)',           today: '47 ms',     on: true },
        { id: 'vo2',   icon: 'wave',  name: 'VO₂ max',              today: '48.2',      on: true },
      ],
    },
    {
      header: 'SLEEP · BODY · MIND',
      items: [
        { id: 'sleep', icon: 'moon',  name: 'Sleep analysis',  today: '7h 12m', on: true },
        { id: 'body',  icon: 'scale', name: 'Body mass',       today: '76.4 kg', on: true },
        { id: 'mind',  icon: 'mind',  name: 'State of mind',   today: '1 entry · calm', on: true },
      ],
    },
    {
      header: 'WORKOUTS',
      items: [
        { id: 'wk',    icon: 'flame', name: 'Workouts',        today: '1 today · 38m run', on: true },
        { id: 'rt',    icon: 'route', name: 'Workout routes',  today: '1 GPX (outdoor)',   on: true },
      ],
    },
    {
      header: 'NUTRITION',
      items: [
        { id: 'food',  icon: 'fork',  name: 'Food & macros',   today: '2240 kcal · P145', on: true },
        { id: 'water', icon: 'wave',  name: 'Water · caffeine', today: '2.1 L · 180 mg',  on: false },
      ],
    },
    {
      header: 'LAB · OPT-IN',
      items: [
        { id: 'o2',    icon: 'lab',   name: 'Blood oxygen',     today: 'no data today',    on: false },
        { id: 'resp',  icon: 'lab',   name: 'Respiratory rate', today: 'no data today',    on: false },
        { id: 'mind2', icon: 'lab',   name: 'Mindful minutes',  today: 'no data today',    on: false },
      ],
    },
  ];

  return (
    <Phone tab="cats" accent={accent}>
      <ScreenHeader
        title="Categories"
        subtitle="14 enabled · 3 lab · auto-detected from HealthKit"
        leading={<Icon name="sidebar" size={22} color={PC.muted} />}
        trailing={
          <div style={{ display: 'flex', gap: 8 }}>
            <Pill mono>{`{ id: "steps" }`}</Pill>
          </div>
        }
      />

      <div style={{ padding: '0 20px 20px' }}>
        {groups.map(g => (
          <div key={g.header} style={{ marginBottom: 20 }}>
            <div style={{
              fontFamily: PC.fontMono, fontSize: 10, color: PC.dim,
              letterSpacing: 1.5, marginBottom: 8, paddingLeft: 4,
              display: 'flex', justifyContent: 'space-between',
            }}>
              <span>{g.header}</span>
              <span style={{ color: PC.faint }}>{g.items.filter(i=>i.on).length}/{g.items.length}</span>
            </div>
            <Card padded={false}>
              {g.items.map((it, i) => (
                <React.Fragment key={it.id}>
                  <div style={{ padding: '12px 16px', display: 'flex', alignItems: 'center', gap: 12 }}>
                    <div style={{
                      width: 32, height: 32, borderRadius: 8,
                      background: it.on ? accent.soft : PC.elevated,
                      color: it.on ? accent.hue : PC.dim,
                      display: 'flex', alignItems: 'center', justifyContent: 'center',
                    }}>
                      <Icon name={it.icon} size={18} />
                    </div>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ fontSize: 15, fontWeight: 500, color: PC.text }}>{it.name}</div>
                      <div style={{
                        fontFamily: PC.fontMono, fontSize: 11,
                        color: it.on ? PC.muted : PC.dim, marginTop: 2,
                      }}>{it.today}</div>
                    </div>
                    <Toggle on={it.on} accent={accent} size="sm" />
                  </div>
                  {i < g.items.length - 1 && (
                    <div style={{ height: 0.5, background: PC.divider, marginLeft: 60 }} />
                  )}
                </React.Fragment>
              ))}
            </Card>
          </div>
        ))}
      </div>
    </Phone>
  );
}

// ╔═════════════════════════════════════════════════════════════════╗
// ║  DESTINATIONS · GITHUB                                            ║
// ╚═════════════════════════════════════════════════════════════════╝
function DestGitHub({ accent }) {
  return (
    <Phone tab="dests" accent={accent}>
      <ScreenHeader
        title="GitHub"
        subtitle="Commits to repo · atomic per day"
        leading={
          <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
            <Icon name="chevron-left" size={22} color={accent.hue} />
            <span style={{ color: accent.hue, fontSize: 17 }}>Destinations</span>
          </div>
        }
        trailing={
          <Pill mono color={PC.success} bg={'rgba(0,210,106,0.1)'}>● CONNECTED</Pill>
        }
      />

      {/* PAT */}
      <div style={{ padding: '0 20px 16px' }}>
        <FieldLabel label="PERSONAL ACCESS TOKEN" hint="stored in keychain · device only" />
        <Card padded={false}>
          <div style={{ padding: '14px 16px', display: 'flex', alignItems: 'center', gap: 10 }}>
            <Icon name="lock" size={18} color={PC.success} />
            <div style={{ flex: 1, fontFamily: PC.fontMono, fontSize: 14, color: PC.text, letterSpacing: 0.5 }}>
              ghp_•••••••••••••••3a2f
            </div>
            <span style={{ fontSize: 12, color: accent.hue, fontWeight: 600 }}>Edit</span>
          </div>
        </Card>
      </div>

      {/* Repo config */}
      <div style={{ padding: '0 20px 16px' }}>
        <FieldLabel label="REPOSITORY" />
        <Card padded={false}>
          <FormRow label="Owner"        value="yuriy"            mono />
          <FormRow label="Repo"         value="health-data"      mono />
          <FormRow label="Branch"       value="main"             mono accent={accent} />
          <FormRow label="Subdirectory" value="/"                mono isLast />
        </Card>
      </div>

      {/* Test */}
      <div style={{ padding: '0 20px 16px' }}>
        <button style={{
          width: '100%', appearance: 'none',
          background: PC.surface, color: PC.text,
          border: `0.5px solid ${PC.hairline}`,
          padding: '14px 16px', borderRadius: 14,
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
          fontSize: 15, fontWeight: 600,
        }}>
          <Icon name="bolt" size={16} color={accent.hue} />
          Test connection
        </button>
      </div>

      {/* Preview */}
      <div style={{ padding: '0 20px 24px' }}>
        <FieldLabel label="PREVIEW · NEXT COMMIT" />
        <CodeBlock>
          <span style={{ color: accent.hue }}>{'$ '}</span>
          <span style={{ color: PC.text }}>git commit -m</span>
          <span style={{ color: PC.success }}>{' "Pulse Commit · 2026-05-14"'}</span>
          {'\n'}
          {'\n'}
          <span style={{ color: PC.dim }}>{'yuriy/health-data on '}</span>
          <span style={{ color: accent.hue }}>main</span>
          {'\n'}
          <span style={{ color: PC.dim }}>{'├── 2026-05-14/'}</span>
          {'\n'}
          <span style={{ color: PC.dim }}>{'│   ├── summary.json'}</span>
          {'\n'}
          <span style={{ color: PC.dim }}>{'│   ├── samples/  '}</span><span style={{ color: PC.faint }}>11 files</span>
          {'\n'}
          <span style={{ color: PC.dim }}>{'│   ├── workouts/ '}</span><span style={{ color: PC.faint }}>1 file</span>
          {'\n'}
          <span style={{ color: PC.dim }}>{'│   └── routes/   '}</span><span style={{ color: PC.faint }}>1 file (gpx)'}</span>
          {'\n'}
          <span style={{ color: PC.dim }}>{'└── .pulsecommit/config.json'}</span>
        </CodeBlock>
      </div>
    </Phone>
  );
}

function FieldLabel({ label, hint }) {
  return (
    <div style={{
      display: 'flex', justifyContent: 'space-between',
      fontFamily: PC.fontMono, fontSize: 10, color: PC.dim,
      letterSpacing: 1.5, marginBottom: 8, paddingLeft: 4,
    }}>
      <span>{label}</span>
      {hint && <span style={{ color: PC.faint, textTransform: 'none', letterSpacing: 0 }}>{hint}</span>}
    </div>
  );
}

function FormRow({ label, value, mono, accent, isLast }) {
  return (
    <>
      <div style={{ padding: '13px 16px', display: 'flex', alignItems: 'center', gap: 10 }}>
        <span style={{ fontSize: 14, color: PC.muted, minWidth: 100 }}>{label}</span>
        <span style={{
          flex: 1, fontFamily: mono ? PC.fontMono : PC.fontUI, fontSize: 14,
          color: accent ? accent.hue : PC.text,
        }}>{value}</span>
        <Icon name="chevron-right" size={14} color={PC.faint} weight={2} />
      </div>
      {!isLast && <div style={{ height: 0.5, background: PC.divider, marginLeft: 16 }} />}
    </>
  );
}

// ╔═════════════════════════════════════════════════════════════════╗
// ║  DESTINATIONS · TELEGRAM                                          ║
// ╚═════════════════════════════════════════════════════════════════╝
function DestTelegram({ accent }) {
  return (
    <Phone tab="dests" accent={accent}>
      <ScreenHeader
        title="Telegram"
        subtitle="Markdown summary + JSON archive"
        leading={
          <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
            <Icon name="chevron-left" size={22} color={accent.hue} />
            <span style={{ color: accent.hue, fontSize: 17 }}>Destinations</span>
          </div>
        }
        trailing={<Pill mono color={PC.success} bg={'rgba(0,210,106,0.1)'}>● CONNECTED</Pill>}
      />

      <div style={{ padding: '0 20px 16px' }}>
        <FieldLabel label="BOT TOKEN" hint="from @BotFather" />
        <Card padded={false}>
          <div style={{ padding: '14px 16px', display: 'flex', alignItems: 'center', gap: 10 }}>
            <Icon name="lock" size={18} color={PC.success} />
            <div style={{ flex: 1, fontFamily: PC.fontMono, fontSize: 14, color: PC.text }}>
              8123456789:•••••••••••AaBcDeF
            </div>
            <span style={{ fontSize: 12, color: accent.hue, fontWeight: 600 }}>Edit</span>
          </div>
        </Card>
      </div>

      <div style={{ padding: '0 20px 16px' }}>
        <FieldLabel label="CHAT ID" hint="send /start to your bot" />
        <Card padded={false}>
          <FormRow label="Chat ID" value="847291835" mono accent={accent} isLast />
        </Card>
      </div>

      <div style={{ padding: '0 20px 16px' }}>
        <FieldLabel label="VERBOSITY" />
        <Segmented options={['Compact', 'Standard', 'Verbose']} selected="Standard" accent={accent} />
      </div>

      <div style={{ padding: '0 20px 16px' }}>
        <Card padded={false}>
          <div style={{ padding: '14px 16px', display: 'flex', alignItems: 'center', gap: 10 }}>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 15, fontWeight: 500, color: PC.text }}>Include GitHub link</div>
              <div style={{ fontSize: 11, color: PC.dim, fontFamily: PC.fontMono, marginTop: 2 }}>
                appends commit URL to message
              </div>
            </div>
            <Toggle on accent={accent} size="sm" />
          </div>
        </Card>
      </div>

      <div style={{ padding: '0 20px 24px' }}>
        <FieldLabel label="PREVIEW · STANDARD" />
        <CodeBlock>
          <span style={{ color: accent.hue }}>🫀 *Pulse Commit · 2026-05-14*</span>{'\n'}
          {'\n'}
          <span style={{ color: PC.text, fontWeight: 600 }}>🏃 *Activity*</span>{'\n'}
          <span style={{ color: PC.muted }}>{'• Steps: 12 483'}</span>{'\n'}
          <span style={{ color: PC.muted }}>{'• Active energy: 612 kcal'}</span>{'\n'}
          <span style={{ color: PC.muted }}>{'• Stand: 11 h · Exercise: 42 m'}</span>{'\n'}
          {'\n'}
          <span style={{ color: PC.text, fontWeight: 600 }}>❤️ *Heart*</span>{'\n'}
          <span style={{ color: PC.muted }}>{'• Resting HR: 58 bpm  · HRV: 47 ms'}</span>{'\n'}
          {'\n'}
          <span style={{ color: PC.text, fontWeight: 600 }}>😴 *Sleep*  </span>
          <span style={{ color: PC.muted }}>7h 12m</span>{'\n'}
          <span style={{ color: PC.text, fontWeight: 600 }}>🏋️ *1 workout* </span>
          <span style={{ color: PC.muted }}>Outdoor Run · 38m · 6.2 km</span>{'\n'}
          {'\n'}
          <span style={{ color: PC.faint }}>schema 1.0</span>{'\n'}
          <span style={{ color: accent.hue }}>🔗 View on GitHub →</span>
        </CodeBlock>
      </div>
    </Phone>
  );
}

function Segmented({ options, selected, accent }) {
  return (
    <div style={{
      display: 'flex', padding: 3, borderRadius: 12,
      background: PC.surface, border: `0.5px solid ${PC.divider}`,
      gap: 3,
    }}>
      {options.map(o => {
        const on = o === selected;
        return (
          <div key={o} style={{
            flex: 1, padding: '8px 12px', textAlign: 'center',
            fontSize: 13, fontWeight: 600,
            color: on ? '#000' : PC.muted,
            background: on ? accent.hue : 'transparent',
            borderRadius: 9,
            transition: 'all .15s',
          }}>{o}</div>
        );
      })}
    </div>
  );
}

// ╔═════════════════════════════════════════════════════════════════╗
// ║  HISTORY                                                           ║
// ╚═════════════════════════════════════════════════════════════════╝
function History({ accent }) {
  const runs = [
    { hash: 'a8f3c2d', date: '2026-05-13', when: 'Today · 14:32', sum: '12.5k steps · 1 workout · sleep 7h12m', ok: 'ok',  github: true, tg: true,  files: 14 },
    { hash: '7b29e1f', date: '2026-05-12', when: 'Yesterday · 14:30', sum: '8.9k steps · sleep 6h58m', ok: 'ok',  github: true, tg: true,  files: 12 },
    { hash: 'c4421a0', date: '2026-05-11', when: 'May 12 · 14:31', sum: '14.2k steps · 2 workouts · sleep 8h04m', ok: 'ok',  github: true, tg: true,  files: 16 },
    { hash: '——————', date: '2026-05-10', when: 'May 11 · 14:32', sum: 'GitHub 401 · cursor not advanced', ok: 'err', github: false, tg: true, files: 0 },
    { hash: 'e10b8c4', date: '2026-05-09', when: 'May 10 · 14:30', sum: '11.0k steps · sleep 7h22m', ok: 'ok',  github: true, tg: true, files: 13 },
    { hash: 'd9a3e22', date: '2026-05-08', when: 'May 9 · 14:31',  sum: '9.7k steps · 1 workout · sleep 7h00m', ok: 'ok', github: true, tg: true, files: 13 },
  ];
  return (
    <Phone tab="history" accent={accent}>
      <ScreenHeader
        title="History"
        subtitle="147 commits · 4 failures · since Jan 2026"
        leading={<Icon name="sidebar" size={22} color={PC.muted} />}
        trailing={
          <Pill mono>{'$ git log --oneline'}</Pill>
        }
      />

      {/* filter row */}
      <div style={{ padding: '0 20px 16px', display: 'flex', gap: 8 }}>
        <Segmented options={['All', 'Success', 'Failed']} selected="All" accent={accent} />
      </div>

      <div style={{ padding: '0 20px 0' }}>
        <Card padded={false}>
          {runs.map((r, i, arr) => (
            <React.Fragment key={i}>
              <div style={{ padding: '14px 16px' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 6 }}>
                  <StatusDot status={r.ok === 'ok' ? 'ok' : 'error'} />
                  <span style={{ fontFamily: PC.fontMono, fontSize: 13, color: r.ok === 'ok' ? PC.text : PC.error }}>
                    {r.hash}
                  </span>
                  <span style={{ fontFamily: PC.fontMono, fontSize: 11, color: PC.dim }}>{r.date}</span>
                  <span style={{ flex: 1 }} />
                  <span style={{ fontFamily: PC.fontMono, fontSize: 11, color: PC.dim }}>{r.when}</span>
                </div>
                <div style={{ fontSize: 13, color: r.ok === 'ok' ? PC.muted : PC.error, marginBottom: 8, paddingLeft: 18 }}>
                  {r.sum}
                </div>
                <div style={{
                  display: 'flex', gap: 6, paddingLeft: 18,
                  fontFamily: PC.fontMono, fontSize: 10,
                }}>
                  <SinkBadge ok={r.github} icon="github" label="github" />
                  <SinkBadge ok={r.tg} icon="paper-plane" label="telegram" />
                  {r.files > 0 && <span style={{ color: PC.dim, padding: '3px 8px' }}>{r.files} files</span>}
                </div>
              </div>
              {i < arr.length - 1 && <div style={{ height: 0.5, background: PC.divider, marginLeft: 16 }} />}
            </React.Fragment>
          ))}
        </Card>
      </div>
    </Phone>
  );
}

function SinkBadge({ ok, icon, label }) {
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 4,
      padding: '3px 8px', borderRadius: 6,
      background: ok ? 'rgba(0,210,106,0.1)' : 'rgba(255,69,58,0.1)',
      color: ok ? PC.success : PC.error,
      fontFamily: PC.fontMono, fontSize: 10, fontWeight: 600,
    }}>
      <Icon name={icon} size={11} />
      {label}
    </span>
  );
}

// ╔═════════════════════════════════════════════════════════════════╗
// ║  SETTINGS                                                          ║
// ╚═════════════════════════════════════════════════════════════════╝
function Settings({ accent, unlocked = false }) {
  return (
    <Phone tab="settings" accent={accent}>
      <ScreenHeader
        title="Settings"
        subtitle={unlocked ? 'unlocked · v1.0.0' : 'trial · v1.0.0'}
        leading={<Icon name="sidebar" size={22} color={PC.muted} />}
      />

      {/* unlock / unlocked card */}
      <div style={{ padding: '0 20px 16px' }}>
        {unlocked ? (
          <Card style={{
            background: accent.soft, border: `0.5px solid ${accent.hue}`, padding: 16,
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
              <Icon name="check-circle" size={26} color={accent.hue} />
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 16, fontWeight: 700, color: PC.text }}>Pulse Commit Pro</div>
                <div style={{ fontSize: 12, color: PC.muted, fontFamily: PC.fontMono, marginTop: 2 }}>
                  unlocked · forever · thank you
                </div>
              </div>
            </div>
          </Card>
        ) : (
          <Card style={{ padding: 0 }} padded={false}>
            <div style={{ padding: '16px 16px 12px' }}>
              <div style={{ fontSize: 12, color: accent.hue, fontWeight: 700, letterSpacing: 1.5, marginBottom: 6, fontFamily: PC.fontMono }}>
                UNLOCK · ONE-TIME · $9.99
              </div>
              <div style={{ fontSize: 16, fontWeight: 600, color: PC.text, lineHeight: 1.4 }}>
                Remove the 10-run trial limit. Custom date ranges. Forever.
              </div>
            </div>
            <div style={{ padding: '0 16px 16px' }}>
              <button style={{
                width: '100%', appearance: 'none',
                background: accent.hue, color: '#000',
                border: 'none', padding: '12px 16px',
                borderRadius: 12, fontSize: 15, fontWeight: 700,
              }}>Unlock Pulse Commit</button>
            </div>
          </Card>
        )}
      </div>

      <SectionGroup title="GENERAL" accent={accent}>
        <SettingsRow label="Backfill window" value={unlocked ? 'Last 30 days' : 'Last 1 day · locked'} locked={!unlocked} accent={accent} />
        <SettingsRow label="Units"           value="Metric"         accent={accent} />
        <SettingsRow label="Schedule via"    value="Shortcuts" accent={accent} />
        <SettingsRow label="iCloud prefs sync" toggle isLast accent={accent} />
      </SectionGroup>

      <SectionGroup title="DESTINATIONS" accent={accent}>
        <SettingsRow label="GitHub"   value="yuriy/health-data" mono valueColor={PC.success} accent={accent} />
        <SettingsRow label="Telegram" value="@me · standard" mono valueColor={PC.success} isLast accent={accent} />
      </SectionGroup>

      <SectionGroup title="PRIVACY" accent={accent}>
        <SettingsRow label="What we collect" value="Nothing" valueColor={PC.success} accent={accent} />
        <SettingsRow label="Where data goes" value="Your destinations only" accent={accent} />
        <SettingsRow label="Reset all data"  value="" valueColor={PC.error} isLast accent={accent} />
      </SectionGroup>

      <SectionGroup title="ABOUT" accent={accent}>
        <SettingsRow label="Version"    value="1.0.0 (build 142)" mono accent={accent} />
        <SettingsRow label="Source"     value="github.com/yk/pulse" mono accent={accent} />
        <SettingsRow label="Contact"    value="hi@pulsecommit.app" mono isLast accent={accent} />
      </SectionGroup>

      <div style={{
        padding: '8px 24px 32px', fontFamily: PC.fontMono, fontSize: 10,
        color: PC.faint, lineHeight: 1.7, textAlign: 'center',
      }}>
        ⌘ Made with care in Lisbon, 2026
      </div>
    </Phone>
  );
}

function SectionGroup({ title, children, accent }) {
  return (
    <div style={{ padding: '0 20px 16px' }}>
      <FieldLabel label={title} />
      <Card padded={false}>{children}</Card>
    </div>
  );
}

function SettingsRow({ label, value, valueColor, mono, locked, toggle, isLast, accent }) {
  return (
    <>
      <div style={{ padding: '13px 16px', display: 'flex', alignItems: 'center', gap: 10 }}>
        <span style={{ fontSize: 15, color: PC.text, flex: 1 }}>{label}</span>
        {locked && <Icon name="lock" size={13} color={PC.dim} weight={2} />}
        {value && (
          <span style={{
            fontSize: 14,
            fontFamily: mono ? PC.fontMono : PC.fontUI,
            color: valueColor || PC.muted,
          }}>{value}</span>
        )}
        {toggle ? <Toggle on accent={accent} size="sm" /> :
          <Icon name="chevron-right" size={14} color={PC.faint} weight={2} />}
      </div>
      {!isLast && <div style={{ height: 0.5, background: PC.divider, marginLeft: 16 }} />}
    </>
  );
}

// ╔═════════════════════════════════════════════════════════════════╗
// ║  PAYWALL                                                            ║
// ╚═════════════════════════════════════════════════════════════════╝
function Paywall({ accent }) {
  const perks = [
    { icon: 'plus',     title: 'Unlimited runs',          detail: 'No 10-run trial limit' },
    { icon: 'clock',    title: 'Custom backfill',         detail: 'Last 7 / 30 / 90 days · custom range' },
    { icon: 'shield',   title: 'No subscriptions, ever',  detail: 'One time. Yours forever.' },
    { icon: 'sparkle',  title: 'All future categories',   detail: 'Lab → stable, no extra IAPs' },
  ];
  return (
    <Phone tab="settings" accent={accent} noTabBar>
      <div style={{ padding: '60px 20px 0' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 32 }}>
          <Pill mono>{'product: pulsecommit.unlock'}</Pill>
          <Icon name="x" size={22} color={PC.muted} />
        </div>

        <div style={{
          width: 60, height: 60, borderRadius: 18, background: accent.hue,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          color: '#000', marginBottom: 22, boxShadow: `0 24px 48px -16px ${accent.soft}`,
        }}>
          <Icon name="bolt" size={32} weight={2.4} />
        </div>

        <div style={{ fontSize: 36, fontWeight: 700, letterSpacing: -1, lineHeight: 1.05 }}>
          Pulse Commit<br/><span style={{ color: accent.hue }}>Pro</span>
        </div>
        <div style={{ fontSize: 15, color: PC.muted, marginTop: 12, lineHeight: 1.45 }}>
          Own your health data, forever — one payment, no recurring charges.
        </div>

        {/* price */}
        <div style={{
          marginTop: 24, marginBottom: 24,
          display: 'flex', alignItems: 'baseline', gap: 10,
          fontFamily: PC.fontMono,
        }}>
          <span style={{ fontSize: 54, fontWeight: 700, color: PC.text, letterSpacing: -2 }}>$9.99</span>
          <span style={{ fontSize: 15, color: PC.dim, textDecoration: 'line-through' }}>$24.99/yr*</span>
        </div>
        <div style={{ fontSize: 11, color: PC.faint, marginBottom: 22, fontFamily: PC.fontMono }}>
          * what a typical subscription would cost over 1 year
        </div>

        <Card padded={false}>
          {perks.map((p, i) => (
            <React.Fragment key={p.title}>
              <div style={{ padding: '14px 16px', display: 'flex', alignItems: 'flex-start', gap: 12 }}>
                <div style={{
                  width: 30, height: 30, borderRadius: 8, background: accent.soft,
                  color: accent.hue, display: 'flex', alignItems: 'center', justifyContent: 'center',
                  flexShrink: 0,
                }}>
                  <Icon name={p.icon} size={16} weight={2.2} />
                </div>
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: 15, fontWeight: 600, color: PC.text }}>{p.title}</div>
                  <div style={{ fontSize: 12, color: PC.muted, marginTop: 2 }}>{p.detail}</div>
                </div>
              </div>
              {i < perks.length - 1 && <div style={{ height: 0.5, background: PC.divider, marginLeft: 58 }} />}
            </React.Fragment>
          ))}
        </Card>
      </div>

      <div style={{
        position: 'absolute', bottom: 0, left: 0, right: 0,
        padding: '20px 20px 40px',
        background: 'linear-gradient(180deg, rgba(10,10,10,0) 0%, rgba(10,10,10,0.95) 30%)',
        backdropFilter: 'blur(20px)', WebkitBackdropFilter: 'blur(20px)',
      }}>
        <button style={{
          width: '100%', appearance: 'none',
          background: accent.hue, color: '#000', border: 'none',
          padding: '17px 16px', borderRadius: 14,
          fontSize: 17, fontWeight: 700, letterSpacing: -0.3,
          boxShadow: `0 8px 24px -4px ${accent.soft}`,
        }}>Unlock for $9.99</button>
        <div style={{
          marginTop: 12, textAlign: 'center', fontFamily: PC.fontMono,
          fontSize: 11, color: PC.dim,
        }}>
          <span style={{ color: accent.hue }}>Restore purchase</span>
          <span style={{ color: PC.faint }}>  ·  </span>
          <span>Privacy</span>
          <span style={{ color: PC.faint }}>  ·  </span>
          <span>Terms</span>
        </div>
      </div>
    </Phone>
  );
}

// ╔═════════════════════════════════════════════════════════════════╗
// ║  SHORTCUTS                                                         ║
// ╚═════════════════════════════════════════════════════════════════╝
function Shortcuts({ accent }) {
  const intents = [
    { name: 'Export Last Day', desc: 'No params. Yesterday → both sinks.', tag: 'CRON', code: '$ pulse-commit export-last-day' },
    { name: 'Export Health Data', desc: 'window: 1d/7d/30d/custom · categories · sinks', tag: 'FLEX', code: '$ pulse-commit export --window=7d' },
    { name: 'Backfill Range', desc: 'from: Date → to: Date · paid feature', tag: 'PRO', code: '$ pulse-commit backfill --from=…' },
  ];
  return (
    <Phone tab="settings" accent={accent}>
      <ScreenHeader
        title="Automate"
        subtitle="3 App Intents · works with iOS Shortcuts and Automations"
        leading={<Icon name="sidebar" size={22} color={PC.muted} />}
      />

      <div style={{ padding: '0 20px 16px' }}>
        <CodeBlock>
          <span style={{ color: PC.dim }}>{'# Recommended setup'}</span>{'\n'}
          <span style={{ color: PC.dim }}>{'# Shortcuts › Automation › Time of Day'}</span>{'\n'}
          <span style={{ color: accent.hue }}>{'$ '}</span><span style={{ color: PC.text }}>schedule</span> <span style={{ color: PC.success }}>"00:30 daily"</span> {'→'} <span style={{ color: PC.text }}>Export Last Day</span>
        </CodeBlock>
      </div>

      <div style={{ padding: '0 20px 16px' }}>
        <FieldLabel label="APP INTENTS · TAP TO INSTALL" />
        {intents.map((i, idx) => (
          <Card key={i.name} style={{ marginBottom: 10 }} padded={false}>
            <div style={{ padding: '14px 16px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 8 }}>
                <Icon name="bolt" size={18} color={accent.hue} weight={2.2} />
                <div style={{ fontSize: 15, fontWeight: 700, color: PC.text }}>{i.name}</div>
                <span style={{ flex: 1 }} />
                <Pill mono color={i.tag === 'PRO' ? accent.hue : PC.dim}
                       bg={i.tag === 'PRO' ? accent.soft : 'rgba(255,255,255,0.05)'}>
                  {i.tag}
                </Pill>
              </div>
              <div style={{ fontSize: 12, color: PC.muted, marginBottom: 10, paddingLeft: 28 }}>{i.desc}</div>
              <div style={{
                fontFamily: PC.fontMono, fontSize: 11, color: PC.dim,
                background: '#000', borderRadius: 8, padding: '8px 10px',
                marginLeft: 28, border: `0.5px solid ${PC.divider}`,
              }}>
                {i.code}
              </div>
              <div style={{ marginLeft: 28, marginTop: 12 }}>
                <button style={{
                  appearance: 'none', background: 'transparent',
                  color: accent.hue, border: `0.5px solid ${accent.hue}`,
                  padding: '6px 14px', borderRadius: 9,
                  fontSize: 12, fontWeight: 600,
                  display: 'inline-flex', alignItems: 'center', gap: 6,
                }}>
                  <Icon name="plus" size={12} weight={2.4} /> Add to Shortcuts
                </button>
              </div>
            </div>
          </Card>
        ))}
      </div>

      <div style={{ padding: '0 20px 24px', fontFamily: PC.fontMono, fontSize: 11, color: PC.dim, lineHeight: 1.7 }}>
        {'>'} Trial: all 3 intents available (subject to run cap)<br/>
        {'>'} No background scheduling without Shortcuts<br/>
        {'>'} No analytics, no backend, ever
      </div>
    </Phone>
  );
}

Object.assign(window, {
  HomeA, HomeB, FirstRun, Categories, DestGitHub, DestTelegram,
  History, Settings, Paywall, Shortcuts,
});
