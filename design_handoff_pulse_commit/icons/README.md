# PulseCommit · Icon set

46 icons used across the app. **All custom SVGs in this folder are for design reference only.**
In the SwiftUI build, replace each one with the listed **SF Symbol** — that's the production source of truth (it gives you accessibility, dynamic type, automatic dark/light tinting, weight variants, and Apple's continuous updates for free).

## Source of truth

```
brand/icons/
├── catalog.html         ← open in a browser — visual grid of every icon
├── svg/                 ← one <name>.svg per icon, viewBox 0 0 24 24
│   ├── arrow-up.svg
│   ├── ...
│   └── wave.svg
└── README.md            ← you are here
```

## SVG conventions

- **ViewBox:** `0 0 24 24` for every icon.
- **Color:** all strokes/fills use `currentColor` — set `color` on the parent and the icon inherits it. This is why every SVG renders correctly on dark and light backgrounds without per-asset edits.
- **Stroke weight:** `1.7` is the canonical weight. Bump to `2` or `2.2` for emphasized actions (matches how the Icon component uses the `weight` prop).
- **Caps/joins:** `round` everywhere — feels softer at small sizes.
- **No fill on stroke icons** — `fill="none"` is set at the SVG root.

## Icon → SF Symbol mapping

When you implement in SwiftUI, use `Image(systemName:)` with the SF Symbol name listed below. The custom SVG is the design reference; SF Symbols is what ships.

| Icon | SF Symbol | Used on |
|---|---|---|
| `arrow-right` | `arrow.right` | reserved |
| `arrow-up` | `arrow.up` | Home A · big Export button (error, retry); Home B · primary action |
| `arrow-up-circle` | `arrow.up.circle.fill` | Home A · big Export button (idle, done, menu) |
| `bolt` | `bolt.fill` | Test connection · Shortcuts intents · Paywall hero |
| `branch` | `arrow.triangle.branch` | reserved |
| `check` | `checkmark` | First-run "Granted" step · ExportMenu default check |
| `check-circle` | `checkmark.circle.fill` | Settings · "Unlocked" pro card |
| `chevron-down` | `chevron.down` | split-button hint on Export Now; menu indicators |
| `chevron-left` | `chevron.left` | back affordance (sub-screen headers) |
| `chevron-right` | `chevron.right` | navigation rows (Settings, Destinations, Forms) |
| `chevron-updown` | `chevron.up.chevron.down` | reserved |
| `clock` | `clock.fill` | tab bar · History; Paywall perks |
| `cloud` | `cloud.fill` | reserved |
| `cloud-check` | `checkmark.icloud.fill` | reserved (iCloud sync state) |
| `commit` | `(custom asset — no SF Symbol)` | Home A LAST COMMIT card; Home B commit feed |
| `document` | `doc.text.fill` | ExportMenu · Custom range |
| `dot` | `circle.fill` | reserved (legacy) |
| `eye` | `eye` | reserved (token reveal) |
| `eye-off` | `eye.slash` | reserved (token hide) |
| `flame` | `flame.fill` | Categories · Active energy, Workouts |
| `fork` | `fork.knife` | Categories · Food & macros |
| `gear` | `gearshape.fill` | tab bar · Settings |
| `github` | `(custom asset — no SF Symbol)` | Home A LAST COMMIT; SinkRow; History sink badge |
| `heart` | `heart.fill` | Categories · ACTIVITY / HEART rows; First-run "Grant Health" |
| `hold` | `(custom — long-press affordance, no SF equivalent)` | Export Now split-button "HOLD" badge; ExportMenu header |
| `home` | `house.fill` | tab bar · Home |
| `info` | `info.circle.fill` | reserved |
| `lab` | `flask.fill` | Categories · LAB · OPT-IN section |
| `list` | `list.bullet` | tab bar · Categories |
| `lock` | `lock.fill` | Destinations (PAT, bot token) · Settings locked rows |
| `mind` | `brain` | Categories · State of mind |
| `moon` | `moon.fill` | Categories · Sleep |
| `paper-plane` | `paperplane.fill` | Home A SinkRow; History sink badge; Telegram destination |
| `play` | `play.fill` | reserved |
| `plug` | `powerplug.fill` | tab bar · Destinations |
| `plus` | `plus` | Paywall perks · Shortcuts "Add to Shortcuts" |
| `route` | `point.topleft.down.to.point.bottomright.curvepath.fill` | Categories · Distance, Workout routes |
| `scale` | `scalemass.fill` | Categories · Body mass |
| `shield` | `lock.shield.fill` | Paywall · "No subscriptions ever" |
| `shoe` | `figure.walk` | Categories · Steps |
| `sidebar` | `sidebar.left` | top-right of most screen headers |
| `sparkle` | `sparkles` | Categories · Activity rings; Paywall perks |
| `terminal` | `terminal.fill` | First-run hero glyph |
| `wave` | `waveform.path.ecg` | Categories · HRV, VO₂, Water rows |
| `x` | `xmark` | Paywall close |
| `x-circle` | `xmark.circle.fill` | reserved (Destinations test-failed) |


## Custom assets (no SF Symbol)

Three glyphs need a real PNG/SVG asset shipped in your Xcode asset catalog — SF Symbols doesn't cover them:

- **`github`** — Use [Octicons mark-github](https://primer.style/octicons/mark-github-16) or our `svg/github.svg` as the source. Drop into `Assets.xcassets` as a template image so SwiftUI tinting works.
- **`commit`** — Custom dot-on-line glyph (used in History, Home A LAST COMMIT, Home B feed). Same template-image treatment.
- **`hold`** — Long-press affordance (concentric circle + filled center). Tiny — only used in the Export Now split-button and the ExportMenu header. Could be inlined as an SF Symbols-style template image at 12pt, or drawn directly in SwiftUI with two `Circle()`s.

## Adding a new icon

If you need an icon that's not here:
1. Prefer an SF Symbol — search [SF Symbols app](https://developer.apple.com/sf-symbols/).
2. If none fits, add a 24×24 `currentColor` SVG here, register it in `design-system.jsx` (the `paths` object inside `Icon`), and update this README.

## Color usage

These icons take their tint from the parent's `color` (web) or `.foregroundStyle` (SwiftUI). In the design:

- Default secondary chrome: `#a3a3a3` (`PC.muted`)
- Active / on state: accent (`#A4F03A`)
- Critical: `#FF453A` (PC.error)
- Success / connected: `#00D26A` (PC.success)

Never burn a color into the SVG itself.
