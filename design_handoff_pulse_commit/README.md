# Handoff — Pulse Commit (iOS MVP v1.0)

## Overview

**Pulse Commit** is an iOS app that exports Apple HealthKit data to two user-owned destinations: a **Git repository** (GitHub in MVP) and a **Telegram chat**. Single-user, no backend, no analytics. Sold as a one-time $9.99 IAP after a 10-run trial.

This handoff covers the **complete UI design for v1.0** — 10 screens organized into 3 sections (Home, Configuration, History/Settings/Automate), plus two design directions for the main Home screen.

Full product spec is also included in this folder (`product-spec.md`) — read that first for context, then return here for visual/UI details.

---

## About the design files

The HTML files in this bundle are **design references built with React + Babel for visual fidelity in a browser**. They are NOT the codebase you will ship.

Your job is to **recreate these designs in SwiftUI** (the target platform per spec §2). The HTML/JSX serves three purposes:

1. **Source of truth for visual decisions** — colors, spacing, typography, layout structure, copy.
2. **Component vocabulary** — every reusable piece (cards, toggles, pill badges, status dots, code-blocks, sink rows) is named and structured in `screens.jsx` and `design-system.jsx`. Mirror those structures as SwiftUI views.
3. **Interactive prototype to click through** — open `PulseCommit Design.html` to see all 10 screens side-by-side. The Tweaks panel toggles accent color, Home state (idle/running/done/error), and Trial/Unlocked entitlement — useful for understanding state variations.

When in doubt about pixel exactness, prefer **iOS-native patterns** (system materials, SF Symbols, standard padding) over slavish replication of the web rendering.

---

## Fidelity

**High-fidelity.** Final colors, typography, spacing, and copy. Recreate pixel-close in SwiftUI using the design tokens below. Use SF Symbols for icons (the JSX uses custom SVGs only because SF Symbols don't render in browsers).

---

## Design direction

**Aesthetic:** Dark terminal / developer tool. Inspired by GitHub, Linear, and developer CLIs.

**Voice & character:**
- UI text in SF Pro (system default).
- Technical details — commit hashes, file paths, timestamps, IP addresses, version strings, "what will be exported" previews — in SF Mono. This is the most important typographic choice. Every screen has both.
- Subtle CLI metaphors: `$ pulse commit --since=yesterday` as the supertitle on the Home button, `$ git log --oneline` as the History supertitle, code-block-style previews for upcoming commits and Telegram messages.
- Status uses tiny round dots and short tags (`● 8 / 10 RUNS`, `● CONNECTED`) over icons-with-labels.

**Color mode:** Dark only for v1.0. Light mode not in scope per spec.

---

## Design tokens

### Color palette

```
Surfaces
  bg                #0a0a0a    page background
  surface           #141414    cards
  elevated          #1c1c1c    nested chips (icon backgrounds, code blocks bg)
  raised            #242424    pressed/hover state
  divider           rgba(255,255,255,0.07)   row separators
  hairline          rgba(255,255,255,0.10)   card borders, segmented control borders

Text
  text              #fafafa    primary
  muted             #a3a3a3    secondary
  dim               #737373    tertiary / monospace metadata
  faint             #525252    quaternary / placeholders

Semantic
  success           #00D26A    successful commit, "Connected" status
  warn              #FFAD33    in-progress, warnings
  error             #FF453A    failed run, destructive actions

Accent (locked to Lime)
  accent            #A4F03A    primary action color
  accent-soft       rgba(164,240,58,0.16)   tinted backgrounds (icon chips, pill bg)
```

> **Accent note:** The HTML prototype includes 4 accent options as a tweak (Crimson, Lime, Electric, Mono). The user has locked in **Lime (`#A4F03A`)** for production. Keep the other accents out of the SwiftUI build.

> **Black text on accent:** Because Lime is a high-luminance color, all CTAs that fill with Lime use **`#000` text** (not white). See `HomeA` "Export Now" button and Paywall "Unlock" button.

### Typography

```
UI font           SF Pro Text / SF Pro Display (-apple-system in HTML)
Mono font         SF Mono (fallback to JetBrains Mono / Menlo)

Sizes (px, all dark mode):
  Large title     32 / 700 / -0.8 letter-spacing       screen titles
  Hero number     64 / 700 / -3 letter-spacing         streak counter, paywall price
  Big button      36 / 700 / -1.2                       Home "Export Now"
  Title           18 / 700 / -0.3                       Home B button title, paywall card titles
  Body large      17 / 500                              row labels (system size)
  Body            15 / 600 (semibold) or 500 (regular)  most lists, cards
  Body small      14                                    form values, settings rows
  Caption         13                                    detail rows, subtitles
  Mono detail     12 / fontMono                         hashes, paths, "8 of 10"
  Caption mono    11 / fontMono                         row meta (timestamps, file counts)
  Label           10 / fontMono / 1.5 letter-spacing / UPPERCASE   section headers (LAST COMMIT, etc.)
```

### Spacing

Layout uses standard iOS gutters:

```
Screen horizontal padding     20pt
Card horizontal padding       16pt
Card vertical padding         12-16pt
Card radius                   14-16pt
Row min height                52pt (tap target)
Section header → content gap  8pt
Section bottom margin         16pt
Header top padding            60pt (clears status bar + dynamic island)
Tab bar height                ~80pt (including home indicator)
```

### Border radius

```
Card               16
Tile               14
Pill / chip        99 (full)
Icon container     8
Button (large)     14-22
Toggle             full
Code block         12
```

### Shadows / glow

Almost no shadows in dark mode — rely on hairline borders + slight bg differences. The exceptions:

```
Big button glow            0 24px 48px -16px <accent-soft>
Paywall button glow        0 8px 24px -4px <accent-soft>
Running state pulse        animation: pulse 1.4s infinite ease-in-out
```

### Tab bar

5 tabs, custom (not standard iOS tab bar). Glass-blurred background with a hairline top border. Tab heights ~44pt, icon 22pt, label 10pt below.

```
Home          home icon
Categories    list icon (3 lines with dots)
Destinations  plug icon
History       clock icon
Settings      gear icon
```

---

## Screen-by-screen reference

### Section 1 — Home

#### A · "Big Button" (RECOMMENDED for MVP)

The opinionated, safe direction. Use this for v1.0.

**Layout (top to bottom):**

1. **Header** — large title "Pulse Commit", supertitle in mono ("v1.0.0 · iPhone 15 Pro · Europe/Lisbon"), trial pill top-left (`● 8 / 10 RUNS`), sidebar icon top-right.
2. **Big button** — full-width accent-color block, 22pt radius. Contains:
   - CLI supertitle in mono caps: `$ pulse commit --since=yesterday`
   - Huge label: "Export Now" (36/700)
   - Sub-label in mono: "Since yesterday · ready to commit"
   - Arrow-up-circle icon, top-right
   - In `running` state: 3pt progress bar inside, label changes to "Committing…"
   - In `error` state: red accent override, label "Retry Export", sub "Last attempt failed · GitHub 401", icon is bare arrow-up
   - In `done` state: same as idle but sub says "Last commit · 2 min ago · ✓"
3. **LAST COMMIT** section — card with 3 rows separated by dividers:
   - Commit-icon + hash (`a8f3c2d`) + branch (`· main`) + timestamp (`2m ago`)
   - Date + human summary (`2026-05-13 · 12.5k steps · 1 workout · sleep 7h12m`)
   - Sink badges row in mono (`github · telegram   14 files`)
4. **SINKS · NEXT RUN** — list card with GitHub and Telegram toggles, each with name + mono detail line (`user/health-data · main`, `@me · standard verbosity`).
5. **TO BE EXPORTED · LIVE** — 2×2 grid of stat tiles (Steps / Active / Sleep / Workouts), mono values.
6. **Tab bar.**

**States:** `idle` (default), `running` (progress bar), `done`, `error`. Implement all four with the same layout; only the button block changes.

#### B · "Commit Graph" (ALTERNATIVE)

The ambitious, GitHub-feel direction. Save for v1.1 or as a Settings toggle if there's appetite.

Key elements: streak counter ("47 days" in 64pt accent), 14×7 contribution heatmap of exported days (4 intensity levels of accent + empty cells), compact "Export Now" button, recent commits feed with hashes and one-line summaries.

#### C · First run / empty state

For a user who has just installed and not yet configured anything. Reuses the Home tab.

- Small "Welcome to Pulse Commit" header (no big title)
- Terminal-icon chip in accent-soft, 56×56
- 2-line intro paragraph in muted text
- "SETUP · 3 STEPS" card with 3 rows: Grant Health access (✓ done state), Connect GitHub (pending → CTA pill "Set up"), Connect Telegram (pending → CTA pill "Set up")
- Footnote in mono with `>` markers explaining keychain storage

---

### Section 2 — Configuration

#### Categories

List of all 14 MVP HealthKit categories + 3 lab-flag categories, grouped:

```
ACTIVITY   4/4    steps, distance, active energy, activity rings
HEART      4/4    heart rate, resting HR, HRV, VO₂ max
SLEEP · BODY · MIND   3/3   sleep, body mass, state of mind
WORKOUTS   2/2    workouts, workout routes
NUTRITION  1/2    food & macros (on), water · caffeine (off)
LAB · OPT-IN   0/3   blood oxygen, respiratory rate, mindful minutes
```

Each row: 32pt icon chip (accent-soft bg + accent color when ON, elevated bg + dim color when OFF), name (15/500), live "today" value in mono (`12 483`, `8.4 km`, `58 bpm`...), iOS-style toggle.

Section header row format: `<NAME>   <enabled>/<total>` (right-aligned count in dim).

> **Implementation hint:** Make this list driven by the `CategoryRegistry` from spec §6.3. Each category type contributes its row config. Adding a new category should append automatically.

#### Destinations · GitHub

Sub-screen accessed via Destinations tab. Has a "< Destinations" back affordance.

Sections:

- **PERSONAL ACCESS TOKEN** — single row card showing masked token with lock icon (`ghp_•••••••••••••••3a2f`), "Edit" affordance. After first save, token is never displayed again in clear text.
- **REPOSITORY** — 4-row card: Owner / Repo / Branch (accent-colored value to emphasize) / Subdirectory.
- **Test connection** button — full-width, surface bg, bolt icon in accent.
- **PREVIEW · NEXT COMMIT** — code block in mono showing the file tree that will be committed for the next run. Use accent color for `$`, success-green for commit message string, dim for tree branches, faint for file counts.

#### Destinations · Telegram

Parallel structure. Sections:

- **BOT TOKEN** — masked, lock icon, "Edit"
- **CHAT ID** — accent-colored mono value (single editable row)
- **VERBOSITY** — segmented control with three options: Compact / Standard / Verbose. Selected pill fills with accent + `#000` text.
- **Include GitHub link** toggle row
- **PREVIEW · STANDARD** — code block showing what the Telegram message will look like with emoji, asterisks for markdown bold, etc.

---

### Section 3 — Operations

#### History

`git log`-style chronological list of past export runs.

- Header subtitle in mono: `147 commits · 4 failures · since Jan 2026`
- Top-right pill: `$ git log --oneline`
- Filter row: segmented "All / Success / Failed"
- One card containing all rows. Each row:
  - Status dot (green ok / red error) + hash in mono + date in dim mono + relative time top-right
  - Human summary on line 2 (red text if failure: `GitHub 401 · cursor not advanced`)
  - Sink badges row (green pill if ok, red pill if failed) + file count

#### Settings

Sections matching spec §7.6:

- **UNLOCK card** at top (or "Pulse Commit Pro / unlocked · forever · thank you" if entitled). Trial state: cyan-on-black accent-color text "UNLOCK · ONE-TIME · $9.99", then big accent button.
- **GENERAL** — Backfill window (locked in trial — lock icon + "Last 1 day · locked"), Units, Schedule via, iCloud prefs sync (toggle)
- **DESTINATIONS** — quick view of current GitHub repo and Telegram chat (mono, success-green values)
- **PRIVACY** — What we collect: "Nothing" (success-green), Where data goes, Reset all data (red value color)
- **ABOUT** — Version, Source, Contact
- Footer: `⌘ Made with care in Lisbon, 2026` in mono / faint / centered

#### Shortcuts (Automate)

Documentation + add-to-Shortcuts surface for App Intents.

- Top code block showing recommended setup pattern (`# Shortcuts › Automation › Time of Day`...)
- "APP INTENTS · TAP TO INSTALL" section — 3 cards, each with:
  - Bolt icon + intent name + tag pill (`CRON` / `FLEX` / `PRO` — PRO is accent-colored)
  - One-line description
  - Code preview in a nested dark block (`$ pulse-commit export-last-day`)
  - "+ Add to Shortcuts" outlined button (accent border + accent text, transparent fill)
- Footer notes about trial behavior in mono

#### Paywall

Modal-style, no tab bar.

- Top-left pill in mono: `product: pulsecommit.unlock`
- Top-right close (×)
- Accent-color icon block (60×60, bolt icon)
- Title: "Pulse Commit" (line 1, normal weight) / "Pro" (line 2, accent color)
- 1-line subtitle: "Own your health data, forever — one payment, no recurring charges."
- Price block: `$9.99` in 54pt mono + strikethrough comparison `$24.99/yr*`, with footnote
- 4-perk card: Unlimited runs / Custom backfill / No subscriptions, ever / All future categories
- **Sticky bottom CTA** — big "Unlock for $9.99" button + footer row with "Restore purchase" (accent) / Privacy / Terms

---

## Interactions & behavior

### Animations

| What | When | How |
|---|---|---|
| Status dot pulse | when status = `running` | `opacity 1 ↔ 0.4`, 1.4s, ease-in-out, infinite |
| Toggle | tap | 0.15s ease, position + bg color |
| Button press | tap | 0.05s, scale 0.96 (system default for SwiftUI Button) |
| Tab switch | tap | no animation between tabs; content swaps instantly |
| Sheet present | paywall, edit destination | iOS standard sheet (medium then large detents) |

### Navigation flow

```
Home  ─────────────┐
Categories ────────┤
Destinations ──┬───┤   tab bar — instant swap
               │   │
History ───────┤   │
Settings ──┬───┴───┘
           │
           ├─► Unlock IAP (paywall sheet)
           ├─► Backfill window picker (sheet) — gated by paywall in trial
           └─► About / Privacy (push)

Destinations
  ├─► GitHub (push) — PAT edit (sheet), test result (toast)
  └─► Telegram (push) — Token edit (sheet), test send (toast)

Home
  └─► Export Now (in-place state change: idle → running → done/error)
```

### State management

Three persistent state surfaces — implement as ObservableObjects:

1. **`AppState`** (UserDefaults-backed):
   - `lastExportCursor: Date?`
   - `trialRunCount: Int`
   - `isUnlocked: Bool` (from StoreKit 2)
   - `enabledCategoryIDs: Set<String>`
   - `selectedDestinations: Set<DestID>`
   - `verbosity: TelegramVerbosity`

2. **`CredentialsStore`** (Keychain-backed; never in UserDefaults):
   - `githubPAT`, `githubOwner`, `githubRepo`, `githubBranch`, `githubSubdir`
   - `telegramBotToken`, `telegramChatID`
   - All with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`

3. **`ExportRunState`** (in-memory, transient):
   - `phase: idle | running(progress) | done | error(reason)` — drives the Home button
   - `runHistory: [HistoryEntry]` (loaded from local SQLite or file-based log)

### Form validation

- **GitHub PAT** — basic shape check: starts with `ghp_` or `github_pat_`, length ≥ 40. Full validation happens via "Test connection" (`GET /user`).
- **owner / repo** — non-empty, `[a-zA-Z0-9-_.]` only.
- **Telegram bot token** — shape `\d+:[A-Za-z0-9_-]{30,}`.
- **Telegram chat ID** — integer (can be negative for groups).

Test-connection states: idle / testing (spinner inline) / ok (green checkmark + "Connected as @user") / fail (red + reason).

---

## Implementation tips

### Layout primitives to build first

1. `PCCard` — surface card with hairline border, 16pt radius, `padded` parameter.
2. `PCSectionHeader` — uppercase mono label with optional right-side hint (`8/10`).
3. `PCPill` — rounded badge with mono text option, color + bg variants.
4. `PCStatusDot` — 8pt circle with optional pulse animation.
5. `PCToggle` — wrap iOS `Toggle` with the accent color via `.tint(Color("Accent"))`.
6. `PCCodeBlock` — mono text on `#000` bg with hairline border.
7. `PCSegmented` — 3-option segmented control matching iOS 17 segmented control but with accent fill.

### Things that look "developer" without being un-iOS

- Mono font for every numeric or technical value (timestamps, hashes, counts, file paths)
- `$ ` prompts in supertitles
- `●` for status pills
- Tree-art (`├──`, `│`, `└──`) in preview blocks
- `>` line prefixes for tip blocks in muted color
- Pluralization-stable units ("min", "kcal", "bpm" — never "minute(s)")

### Things to NOT do

- No emoji as load-bearing UI (the heart emoji `🫀` in the Telegram preview is fine because it's literally the rendered message)
- No drop shadows on cards
- No gradients on backgrounds (the one Home-button glow is acceptable)
- No rainbow accents — Lime only, everywhere
- No bouncy animations — this is a tool, not a toy

---

## Assets

- **All icons:** Replace with SF Symbols. Mapping:

| Design name | SF Symbol |
|---|---|
| arrow-up-circle | `arrow.up.circle.fill` |
| arrow-up | `arrow.up` |
| chevron-right | `chevron.right` |
| commit | `circle.dashed` or custom (Git has no SF Symbol — consider a custom asset) |
| github | (none — use a flat custom asset) |
| paper-plane | `paperplane.fill` |
| home | `house.fill` |
| list | `list.bullet` |
| plug | `powerplug.fill` |
| clock | `clock.fill` |
| gear | `gear` |
| heart | `heart.fill` |
| wave | `waveform.path.ecg` |
| flame | `flame.fill` |
| shoe | `figure.walk` |
| moon | `moon.fill` |
| scale | `scalemass.fill` |
| mind | `brain` |
| fork | `fork.knife` |
| route | `point.topleft.down.curvedto.point.bottomright.up` |
| lab | `flask.fill` |
| bolt | `bolt.fill` |
| cloud-check | `checkmark.icloud.fill` |
| document | `doc.text.fill` |
| terminal | `terminal.fill` |
| lock | `lock.fill` |
| sparkle | `sparkles` |
| shield | `lock.shield.fill` |
| sidebar | `sidebar.left` |

- **App icon:** Not designed yet. Sketch: lime square with black mono `>` glyph centered (terminal prompt) — discuss with user when ready for App Store assets.

---

## Files in this bundle

```
design_handoff_pulse_commit/
├── README.md                  ← you are here
├── product-spec.md            ← full product spec (read for context)
├── PulseCommit Design.html    ← open this in a browser to interact with all 10 screens + Tweaks
├── design-system.jsx          ← color tokens, Icon component (SVG defs match SF Symbol set), Card, Pill, Toggle, etc.
├── screens.jsx                ← all 10 screen components — your primary reference
├── ios-frame.jsx              ← iOS device chrome wrapper (status bar + dynamic island)
├── design-canvas.jsx          ← Figma-like canvas (not used in production, just for browsing)
├── tweaks-panel.jsx           ← Tweaks panel (not used in production)
└── screenshots/               ← PNG of every screen (use for visual reference)
    ├── 01-home-a-big-button.png       ← THE recommended Home for v1.0
    ├── 02-home-b-commit-graph.png     ← alternative / v1.1 candidate
    ├── 03-first-run-empty.png
    ├── 04-categories.png
    ├── 05-destination-github.png
    ├── 06-destination-telegram.png
    ├── 07-history.png
    ├── 08-settings.png
    ├── 09-shortcuts-automate.png
    └── 10-paywall.png
```

> **How to read the HTML files:** Open `PulseCommit Design.html` in any modern browser. You'll see all 10 screens on a pan/zoom canvas. Click any artboard's expand button to focus it fullscreen. The Tweaks panel (bottom-right toggle) lets you flip Home state and Trial/Unlocked entitlement.

> **How to read the JSX files:** They are React components. `screens.jsx` is the most useful file — every screen's structure, copy, spacing, and color usage is in there. Translate component-by-component into SwiftUI views.
