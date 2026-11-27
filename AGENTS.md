# AGENTS.md - Pulse Commit

Guidance for contributors and coding agents working in this repository.

## Project at a glance

**Pulse Commit** is an iOS 17+ app that exports Apple Health (HealthKit) data to two user-owned destinations: a **GitHub repository** (atomic commit with `summary.json`, `samples/*.json`, `workouts/*.json`, `routes/*.gpx`, `summary.md`) and a **Telegram chat** (MarkdownV2 summary + ZIP attachment). A separate opt-in sends a text-only Telegram message for each finished workout. No backend, no analytics, no subscriptions, no in-app purchase.

The visual design handoff in `design_handoff_pulse_commit/` (start with `README.md`, then `PulseCommit Design.html`) is the visual reference. Its paywall screen is historical: 1.0 has no paywall.

**Tone rule:** the audience is developers. Numeric facts over adjectives. Forbidden words are enforced by `scripts/verify-tone.sh` and `PulseCommitTests/ToneAuditTests.swift`.

## Architecture in one paragraph

A local SwiftPM package `Packages/HealthCore` holds all pure logic (`HealthCategory` protocol, `CategoryRegistry`, DTOs, `Normalizer`, `Serializers`, `Sink` protocol and impls). The app target `PulseCommit` provides the HealthKit-bound adapters, SwiftUI screens, SwiftData persistence (history + cursor), Keychain-backed `SecretsStore`, and the `Orchestrator` that ties everything together. App Intents reach the same components via `AppContainer.shared`.

## Stack

- Swift 5.9+, SwiftUI, iOS 17+, iPhone only
- XcodeGen-driven project (`project.yml` is the source of truth, never edit the generated `.xcodeproj`)
- SwiftData via `@Model`
- HealthKit (read-only; no write entitlements)
- ZIPFoundation
- XCTest with URLProtocol stubs for sink tests

## Build / run

```bash
brew install xcodegen        # one-time
xcodegen generate            # whenever project.yml changes
open PulseCommit.xcodeproj   # or run on a sim via xcodebuild/simctl (see Sim destination below)
```

Tests:

```bash
swift test --package-path Packages/HealthCore
xcodebuild test -project PulseCommit.xcodeproj -scheme PulseCommit \
  -destination 'platform=iOS Simulator,name=<any installed iPhone simulator>'
```

> **Signing:** `project.yml` sets `DEVELOPMENT_TEAM` to the maintainer's team. To run on a device, change it locally to your own team and the Debug bundle id to `app.pulsecommit.<your-suffix>`; do not commit those changes. Simulator builds and tests work without a team. If a preflight failure follows an AppIcon change, uninstall and reinstall the app on the simulator.
>
> **Serialize `xcodebuild test` runs.** Concurrent simulator test runners hang in diagnostic collection.

## Concurrency posture

- `SWIFT_STRICT_CONCURRENCY: minimal` for the app target. **Do not raise to `complete`** — SwiftData `#Predicate` macro expansions emit `KeyPath<Model, Field>` that isn't Sendable; that's an Apple framework bug, not ours.
- `SWIFT_TREAT_WARNINGS_AS_ERRORS: YES` for the app target; **`NO` for `PulseCommitTests`** so tests can legitimately exercise deprecated APIs like `HKWorkout(activityType:start:end:duration:...)`.

## GitHub App

The production GitHub App lives in the `pulse-commit` organisation. Current configuration:

- App slug: `pulse-commit` (settings at <https://github.com/organizations/pulse-commit/settings/apps/pulse-commit>)
- Public install URL: <https://github.com/apps/pulse-commit>
- Client ID hard-coded in `Packages/HealthCore/Sources/HealthCore/Sinks/GitHub/GitHubAppConfig.swift` — public, safe to commit.
- Permissions: Repository → Contents: read/write; Metadata: read. Device Flow enabled. No webhooks, no callback URL.
- Setup runbook + config: `docs/operations/github-app-setup.md`, `docs/operations/github-app-config.md`.

## Visual design (locked, dark terminal aesthetic)

**Mood:** developer tool. Inspired by GitHub, Linear, CLI tools. Dark mode only for v1.0.

**Accent: Lime `#A4F03A`** — locked. Black text (`#000`) on accent fills because Lime is high-luminance. No other accent options ship.

### Design tokens (use as `Color` extensions and `Font` constants)

```
Surfaces
  bg          #0a0a0a            page background
  surface     #141414            cards
  elevated    #1c1c1c            nested chips, code blocks
  raised      #242424            pressed/hover
  divider     rgba(255,255,255,0.07)
  hairline    rgba(255,255,255,0.10)

Text
  text   #fafafa     primary
  muted  #a3a3a3     secondary
  dim    #737373     tertiary / mono metadata
  faint  #525252     placeholders

Semantic
  success  #00D26A
  warn     #FFAD33
  error    #FF453A

Accent
  accent       #A4F03A
  accent-soft  rgba(164,240,58,0.16)
```

### Typography rule of thumb

**UI font** = SF Pro (system default). **Mono font** = SF Mono. *Every numeric or technical value — hashes, paths, timestamps, IPs, file counts, "8 of 10", "12 483 steps" — uses SF Mono.* This is the single most important typographic choice. Every screen has both.

CLI metaphors are part of the voice: `$ pulse commit --since=yesterday`, `$ git log --oneline`, `>` line-prefix in tips. Don't over-do it — use only in supertitles and code-preview blocks.

### Component vocabulary (build these first in `DesignSystem/`)

- `PCCard` — `Color("surface")` + hairline border, 16pt radius.
- `PCSectionHeader` — uppercase 10pt mono label, 1.5 letter-spacing, optional right-aligned hint (`8/10`).
- `PCPill` — rounded full-radius badge; mono variant for `● 8 / 10 RUNS`.
- `PCStatusDot` — 8pt circle, optional pulse animation when `running`.
- `PCToggle` — `Toggle` with `.tint(Color("Accent"))`.
- `PCCodeBlock` — SF Mono on `#000` with hairline border; supports tree-art (`├──`, `│`, `└──`).
- `PCSegmented` — 3-option segmented control; selected pill is accent-filled with `#000` text.

### Things to NOT do

- No emoji as load-bearing UI (literal Telegram-message previews excepted).
- No drop shadows on cards (only Home-button accent glow and paywall CTA glow).
- No background gradients.
- No additional accent colors.
- No bouncy animations — this is a tool, not a toy.

### Icons

All icons → SF Symbols. The handoff README has a complete name → SF Symbol mapping table. Custom assets are needed only for: GitHub mark and Git-commit glyph (no native SF Symbol).

### Home button states

`idle` (default) / `running` (3pt inner progress bar + "Committing…" label + pulsing dot) / `done` ("Last commit · 2 min ago · ✓" sub-label) / `error` (red accent override + "Retry Export"). Same layout across all four — only the button block content changes.

### Screen inventory

1. Home A — Big Button (recommended for MVP)
2. First-run / empty state
3. Categories (14 MVP + 3 lab-flag, grouped)
4. Destinations · GitHub
5. Destinations · Telegram
6. History (`git log`-style)
7. Settings
8. Shortcuts / Automate

Reference screenshots: `design_handoff_pulse_commit/screenshots/`. Home B and Paywall are historical and not shipped.

## Conventions

- **Tests first:** add or update a failing test before changing behavior.
- **No third-party SDKs beyond ZIPFoundation.** No analytics, no crash reporters, no networking libs. URLSession only.
- **No editing `.xcodeproj` directly.** Change `project.yml`, run `xcodegen generate`.
- **No comments explaining what code does.** Names should carry that. Only comment non-obvious *why*.
- **Privacy is load-bearing.** Read tokens from Keychain (`SecretsStore`) and never log them. The only outbound hosts allowed in production code are `api.github.com`, `github.com` (Device Flow endpoints only: `/login/device/code` and `/login/oauth/access_token`), `api.telegram.org`, and the HTTPS webhook URL the user enters. There is no server of ours.
- **Schema-versioning matters.** Every JSON file we emit carries `"schema_version": "1.0"`. Treat changes as additive unless we agree to bump the major version.

## Known footguns (encoded the hard way)

- **HealthKit cumulative metrics double-count across sources** — `HKSampleQuery` returns per-source samples (iPhone + Apple Watch both record steps). Use `HKStatisticsQuery(options: .cumulativeSum)` for `steps`, `distance_walking_running`, `active_energy`, `appleStandTime`, `appleExerciseTime`, all `dietary*` types. We have a `fetchSummarySamples` path on `HealthCategory` that does the dedup'd fetch; `fetch` keeps returning raw samples for the GitHub `samples/*.json` export.
- **GitHub Device Flow ≠ RFC 8628.** `verification_uri_complete` is absent — synthesise from `verification_uri + ?user_code=…`. Apps with token expiration disabled return only `{access_token, scope, token_type}`. Empty `refresh_token` must not trigger refresh (would silently force-logout).
- **GitHub Manifest `hook_attributes` requires `hook_attributes.url`** if present. For no-webhook Apps, omit the whole object.
- **Telegram `chat_id` for supergroups starts with `-100`** + at least 9 digits. Missing minus → 400 `chat not found`. We validate client-side in `TelegramDestinationView`.
- **Telegram MarkdownV2** reserves `_ * [ ] ( ) ~ \` > # + - = | { } . !` outside code spans and link URLs. Escape every dynamic value.
- **Telegram custom errors must conform to `LocalizedError`** — otherwise `\(error)` produces `Optional("...")` enum-mirror noise that's hard to read in History.
- **Forum-style supergroups** (`is_forum: true`) route default `sendMessage` to the General topic. For specific threads, pass `message_thread_id`.

## Out of scope (for v1.0)

iPad / macOS apps, localisation beyond English, background fetch / observer queries, AI analysis inside the app, generic-git / GitLab / Gitea sinks, family sharing, subscriptions, web companion. These live in §13 of the spec as roadmap hints — do not pre-build for them.
