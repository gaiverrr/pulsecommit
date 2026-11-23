# Pulse Commit — Design Spec

**Date:** 2026-05-14
**Status:** Draft for review
**Author:** Yuriy Kaygorodov (brainstormed with Claude)

---

## 1. Product overview

**Pulse Commit** is an iOS application that exports Apple Health (HealthKit) data to two user-owned destinations:

1. A **Git repository** (GitHub in MVP) — as a time-series, human-readable, machine-parseable folder structure committed daily.
2. A **Telegram chat** (personal, group, or channel) — as a Markdown summary plus a JSON archive attachment.

The app is a **single-user personal tool, sold via the App Store**. There is no backend, no analytics, no telemetry. The user supplies their own credentials (GitHub PAT, Telegram bot token, chat ID); credentials are stored only in the device Keychain.

**Target audience:** technically literate quantified-self users who want to own their health data and/or feed it to their personal AI agent running inside Telegram.

**Differentiation vs. Health Auto Export (the closest competitor):** HAE already covers iCloud / Dropbox / REST API / MQTT / Home Assistant. It does **not** ship native GitHub-commit and Telegram-bot sinks. Pulse Commit owns this niche with a tighter, opinionated product.

## 2. Platform and stack

- **Platform:** iPhone, iOS 17.0+ (required for App Intents v2 and the State of Mind API).
- **Language / UI:** Swift 5.9+, SwiftUI.
- **Persistence:** Keychain for secrets, UserDefaults for non-sensitive preferences, a small SQLite (or file-based) store for the export history log.
- **No third-party analytics, crash reporters, or backend services.**
- **iPad / Mac:** out of scope for MVP.

## 3. Monetization

Free trial → one-time in-app purchase (no subscriptions).

**Free trial:**

- 10 export runs total (lifetime, counted locally).
- Each run is restricted to a 1-day window (last 24 hours).
- All sinks (GitHub + Telegram), all categories, all Shortcuts/App Intents are available in trial.

**Unlock (non-consumable IAP, product id `pulsecommit.unlock`):**

- Price: **$9.99** (one-time).
- Removes the run-count limit.
- Unlocks configurable backfill window (last 7/30/90 days, custom date range).
- Lifetime, no recurring charges.

The trial counter lives in UserDefaults. Reinstalling the app resets it — this is an accepted minor abuse vector; the friction of full reinstall is treated as sufficient deterrent for a $9.99 product.

## 4. Data categories (MVP)

The following HealthKit categories ship in MVP. Each is implemented as a conforming type of the `HealthCategory` protocol (see §6).

| Category | HealthKit type(s) | Notes |
|---|---|---|
| Steps | `stepCount` | Daily total + samples |
| Distance walking/running | `distanceWalkingRunning` | Daily total |
| Heart rate | `heartRate` | Sampled |
| Resting heart rate | `restingHeartRate` | Daily value |
| HRV (SDNN) | `heartRateVariabilitySDNN` | Daily avg |
| VO₂ max | `vo2Max` | Latest value |
| Active energy | `activeEnergyBurned` | Daily total |
| Activity rings | `appleStandHour`, `appleExerciseTime` | Daily |
| Sleep | `sleepAnalysis` | Duration + stages where available |
| Workouts | `HKWorkout` (all types) | Type, duration, distance, calories, avg/max HR |
| Workout routes | `HKWorkoutRoute` | GPX per outdoor workout |
| Body mass / weight | `bodyMass` | Latest value of the day |
| State of Mind | iOS 17+ State of Mind API | Valence + labels |
| Nutrition | `dietaryEnergyConsumed`, `dietaryProtein`, `dietaryCarbohydrates`, `dietaryFatTotal`, `dietaryFiber`, `dietarySugar`, `dietaryWater`, `dietaryCaffeine` | From third-party food apps |

**HealthKit access:** read-only. The app never requests write permissions.

**Privacy strings (Info.plist):**

- `NSHealthShareUsageDescription` = "Pulse Commit reads your Health data to export it to your own GitHub repository and Telegram chat. Data never leaves your device except to destinations you configure."

## 5. Sync model and windowing

**No background fetch / no observer queries in MVP.** Exports run only when:

1. The user taps **Export Now** in the app, or
2. A Shortcut / iOS Automation invokes one of the app's App Intents.

**Window logic (the "what to export this run" decision):**

- **Default — incremental:** the app maintains a `lastSuccessfulExportAt` cursor. Each run exports data from `cursor` to `now`, rounded to whole days. The cursor advances only when **both** sinks succeed. On failure, the cursor stays put so the next run retries the same range.
- **Manual backfill (paid):** the user can pick a date range and re-export it. This does not affect the cursor.
- **Trial users:** locked to a 1-day window. The cursor advances normally so trial behavior matches "one run = yesterday's data".

**Idempotency:** re-running for the same day overwrites the same daily folder/files. Re-running the same date is safe.

## 6. Architecture

### 6.1 High-level data flow

```
HealthKit ──► HealthReader ──► Normalizer ──► [DailySnapshot] ──┬─► GitRepoSink (GitHub) ──► commit to repo
                                                                 └─► TelegramSink ──► sendMessage + sendDocument

State: { lastExportCursor, trialRunCount, iapEntitlement, credentials in Keychain }
```

### 6.2 Modules

1. **`HealthReader`** — wraps HealthKit. One implementation per category via the `HealthCategory` protocol. Returns plain `Codable` DTOs; `HKSample` types do not leak out. Unit-testable with injected fixtures.

2. **`Normalizer`** — pure functions. Groups DTOs by day into `DailySnapshot` value objects. Computes summary aggregates (totals, averages, stage breakdowns). No I/O.

3. **`Serializers`** — encodes a `DailySnapshot` into:
   - `summary.json` (aggregates),
   - `samples/<category>.json` (raw samples per category),
   - `workouts/<workout-id>.json` (one per workout),
   - `routes/<workout-id>.gpx` (one per outdoor workout that has a route),
   - `summary.md` (Markdown summary for Telegram).

4. **`GitRepoSink` (protocol) + `GitHubSink` (MVP implementation)** — commits all files for a given day as a single atomic commit via the GitHub Git Data API:
   - `GET /repos/{owner}/{repo}/git/ref/heads/{branch}` — get current tip SHA
   - `POST /repos/{owner}/{repo}/git/blobs` — for each file
   - `POST /repos/{owner}/{repo}/git/trees` — build the tree
   - `POST /repos/{owner}/{repo}/git/commits` — create the commit
   - `PATCH /repos/{owner}/{repo}/git/refs/heads/{branch}` — fast-forward the branch
   - Conflict (non-fast-forward): refresh ref SHA, rebuild tree against latest, retry once.

5. **`TelegramSink` (`Sink` protocol implementation)** — uses the Telegram Bot API:
   - `sendMessage` (MarkdownV2) with the day summary.
   - `sendDocument` with the ZIP archive of all files for the day.
   - Respects `retry_after` on 429 rate limits.

6. **`Orchestrator`** — coordinates one export run:
   1. Determine window (cursor or manual range).
   2. For each day in window, fetch from each enabled category in parallel, normalize into a `DailySnapshot`.
   3. Serialize.
   4. Dispatch to all enabled sinks in parallel; await both.
   5. If both succeed, advance the cursor and append a success entry to History. Otherwise log failure (cursor unchanged).

7. **`Paywall`** — StoreKit 2 wrapper for product `pulsecommit.unlock`. Exposes `isUnlocked: Bool`. Orchestrator checks before each run; if trial exhausted and not unlocked, blocks with a paywall sheet.

8. **`AppIntents`** — three intents (see §8) delegating to the Orchestrator.

### 6.3 Extensibility

These are non-negotiable design constraints baked into the architecture from day one:

- **`HealthCategory` protocol** — adding a category = creating a new conforming type + registering it in `CategoryRegistry`. The settings UI, serializer, and summary builder pick it up automatically.

  ```swift
  protocol HealthCategory {
      static var id: String { get }            // stable, e.g. "steps", "hrv-sdnn"
      static var displayName: String { get }
      static var hkTypes: [HKObjectType] { get }
      func fetch(from: Date, to: Date) async throws -> [SampleDTO]
      func summarize(_ samples: [SampleDTO]) -> SummaryFragment
  }
  ```

- **`Sink` protocol** — `func deliver(_ snapshot: DailySnapshot) async throws -> SinkResult`. GitHub and Telegram are two implementations. Future webhook / Dropbox / S3 / generic-git sinks are new conforming types with no Orchestrator changes.

- **`GitRepoSink` sub-protocol** — leaves room for `GitLabSink`, `GiteaSink`, etc. in v1.1+. A generic git-over-HTTPS implementation backed by libgit2 is an option for v1.2+ if demand emerges.

- **Schema versioning** — every JSON file has a top-level `"schema_version": "1.0"`. Additive changes increment the minor version (1.1, 1.2). Breaking changes bump the major. Removed fields are kept for one major version with `"deprecated": true`.

- **Forward-compatible JSON** — new fields are additive; existing keys are never renamed or retyped within a major version.

- **Lab flags** — experimental categories (e.g. Blood Oxygen, Respiratory Rate, Mindful Minutes) live behind a `LabFlags.swift` enum, can be enabled per-build for TestFlight without UI work.

### 6.4 Error handling

- **Network errors:** retry with exponential backoff (3 attempts, 1s/3s/9s). On final failure: log to History, cursor unchanged.
- **HealthKit permission denied for a category:** skip that category gracefully, include `"unavailable_categories": [...]` in the summary, continue with what we have.
- **GitHub ref conflict (non-fast-forward):** refresh ref SHA, rebuild tree against latest, retry once. If still conflicting, fail the run.
- **Telegram 429 rate limit:** respect `retry_after`, retry once.
- **Telegram message > 4096 chars:** split into multiple `sendMessage` calls (header + chunked body).
- **Telegram document > 50 MB:** extremely unlikely for a single day; if hit, omit `routes/` from the ZIP and note in the caption.

## 7. UI / screens

### 7.1 Home / Export

- Big "Export Now" primary button.
- Last run status (timestamp, success/failure, brief summary).
- Trial counter pill ("8 of 10 runs left") or "Unlocked" badge.
- Quick toggle for Telegram on/off and GitHub on/off (per-run override).

### 7.2 Categories

- List of all categories from the registry with toggles.
- Per category: a "preview" row showing today's value (read from HealthKit live).
- All categories enabled by default.

### 7.3 Destinations

Two cards:

- **GitHub:** PAT input (Keychain-stored, never displayed back as plain text once saved), owner/repo, branch (default `main`), optional subdirectory inside the repo (default `/`). "Test connection" button hits `GET /user` + `GET /repos/{owner}/{repo}`.
- **Telegram:** bot token, chat ID (with helper: "send /start to your bot to discover your chat ID"), summary verbosity (Compact / Standard / Verbose), toggle "Include GitHub commit link in message" (only meaningful if both sinks are enabled).

### 7.4 Schedule / Shortcuts

- Documentation page explaining how to wire Shortcuts.app to call `Export Last Day` on a schedule.
- Buttons to add ready-made shortcuts via the Shortcuts URL scheme.

### 7.5 History

- Reverse-chronological list of past export runs.
- Per row: timestamp, status, day(s) covered, counts (records, workouts), link to GitHub commit, link to the Telegram message thread (if it can be deep-linked; otherwise just chat name).

### 7.6 Settings

- Backfill window picker (locked behind paywall in trial).
- Unit system (metric / imperial).
- iCloud sync toggle for **preferences only** (categories enabled list, formatting prefs; never tokens).
- Unlock IAP entry (or "Unlocked ✓").
- Privacy / About page (plain-language explanation of where data goes; no legalese).

## 8. App Intents (Shortcuts surface)

All three are free (available during trial too):

- **`Export Health Data`** — params: `window: enum {last1d, last7d, last30d, custom from/to}`, `categories: [String]?` (defaults to all enabled), `destinations: enum {both, githubOnly, telegramOnly}`.
- **`Export Last Day`** — no params. Equivalent to "tap Export Now in the app". Designed as the simple cron-style shortcut.
- **`Backfill Range`** — params: `from: Date`, `to: Date`. Paywalled (returns an error intent result with paywall guidance for trial users).

## 9. GitHub repo layout

```
<repo-root>/
├── README.md                          # generated on first commit
├── .pulsecommit/
│   └── config.json                    # { "schema_version": "1.0", "device": "iPhone 15 Pro", "app_version": "1.0.0" }
├── 2026-05-12/
│   ├── summary.json
│   ├── samples/
│   │   ├── steps.json
│   │   ├── heart-rate.json
│   │   ├── resting-heart-rate.json
│   │   ├── hrv.json
│   │   ├── vo2max.json
│   │   ├── active-energy.json
│   │   ├── activity-rings.json
│   │   ├── sleep.json
│   │   ├── body-mass.json
│   │   ├── nutrition.json
│   │   └── state-of-mind.json
│   ├── workouts/
│   │   ├── 7f3a-outdoor-run.json
│   │   └── 8b21-functional-strength.json
│   └── routes/
│       └── 7f3a-outdoor-run.gpx
└── 2026-05-13/
    └── ...
```

**`summary.json` example:**

```json
{
  "schema_version": "1.0",
  "date": "2026-05-14",
  "timezone": "Europe/Lisbon",
  "generated_at": "2026-05-14T22:30:12Z",
  "device": "iPhone 15 Pro",
  "app_version": "1.0.0",
  "unavailable_categories": [],
  "metrics": {
    "steps": { "total": 12483, "unit": "count" },
    "distance_walking_running": { "total": 8.4, "unit": "km" },
    "active_energy": { "total": 612, "unit": "kcal" },
    "resting_heart_rate": { "value": 58, "unit": "bpm" },
    "hrv_sdnn": { "avg": 47, "unit": "ms" },
    "vo2_max": { "value": 48.2, "unit": "ml/kg/min" },
    "sleep": {
      "duration_minutes": 432,
      "stages": { "deep": 78, "rem": 92, "core": 240, "awake": 22 }
    },
    "weight": { "value": 76.4, "unit": "kg" },
    "activity_rings": { "stand_hours": 11, "exercise_minutes": 42 },
    "nutrition": {
      "energy_consumed": { "total": 2240, "unit": "kcal" },
      "protein":  { "total": 145, "unit": "g" },
      "carbs":    { "total": 230, "unit": "g" },
      "fat":      { "total": 78,  "unit": "g" },
      "fiber":    { "total": 32,  "unit": "g" },
      "sugar":    { "total": 64,  "unit": "g" },
      "water":    { "total": 2100, "unit": "ml" },
      "caffeine": { "total": 180, "unit": "mg" }
    }
  },
  "workouts": [
    {
      "id": "7f3a",
      "type": "outdoor_run",
      "duration_minutes": 38,
      "distance_km": 6.2,
      "active_energy_kcal": 410,
      "avg_hr": 152,
      "max_hr": 174,
      "has_route": true
    }
  ],
  "state_of_mind": [
    { "time": "2026-05-14T08:15:00Z", "valence": 0.4, "labels": ["calm", "focused"] }
  ]
}
```

**Commit message:**

```
Pulse Commit · 2026-05-14 · 12.5k steps · 1 workout · sleep 7h12m
```

## 10. Telegram message format

**Message 1 — Markdown summary (Standard verbosity):**

```
🫀 *Pulse Commit · 2026-05-14*

🏃 *Activity*
• Steps: 12 483
• Active energy: 612 kcal
• Stand: 11 h · Exercise: 42 min

❤️ *Heart*
• Resting HR: 58 bpm
• HRV (SDNN): 47 ms
• VO₂ max: 48.2

😴 *Sleep*
• Duration: 7h 12m
• Deep 1h18m · REM 1h32m · Core 4h00m

🍽 *Nutrition*
• 2 240 kcal · P 145 / C 230 / F 78
• Water: 2.1 L

⚖️ *Body*
• Weight: 76.4 kg

🏋️ *Workouts (1)*
• Outdoor Run — 38 min · 6.2 km · avg HR 152

🧠 *State of Mind*: calm, focused

`schema_version: 1.0`
🔗 [View on GitHub](https://github.com/user/repo/commit/abc1234)
```

Verbosity modes:

- **Compact** — one-liner with key numbers.
- **Standard** — as above.
- **Verbose** — adds raw sample counts per category.

**Message 2 — Attachment:** ZIP archive `pulse-commit-2026-05-14.zip` containing the same files committed to GitHub. Caption: `JSON archive · N files · schema 1.0`.

**Delivery:** MarkdownV2 with proper escaping of `_*[]()~``>#+-=|{}.!`. If a summary message exceeds 4096 chars, split on section boundaries.

## 11. Security and privacy

- All secrets (GitHub PAT, Telegram bot token) live in Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Never iCloud-synced.
- No third-party SDKs, analytics, crash reporters. Crash reports rely on Apple's native opt-in mechanism only.
- No backend. The app contacts: Apple HealthKit (local), `api.github.com`, `api.telegram.org`. Nothing else.
- App Store Privacy Nutrition Label: "Data Not Collected" across all categories.
- GDPR posture: no controller relationship — the user controls their own data and chooses the recipients.

## 12. Out of scope (explicit non-goals for MVP)

- iPad / macOS apps.
- Localization beyond English.
- Background scheduling beyond Shortcuts/Automations (no `BGAppRefreshTask`, no `HKObserverQuery`).
- AI analysis or insights in the app itself — the user runs that elsewhere (their Telegram-side agent).
- Webhook / generic HTTP sink — backlog.
- Additional git providers (GitLab, Gitea, self-hosted) — v1.1+, abstraction is in place.
- Categories beyond §4 — lab-flag mechanism allows incremental rollout.
- Subscriptions, tiers beyond the single $9.99 unlock.
- Family / multi-account support.

## 13. Roadmap hints (not committed)

- **v1.1:** GitLab and Gitea sinks; expanded category coverage (Blood Oxygen, Respiratory Rate, Mindful Minutes promoted from lab flags).
- **v1.2:** Generic git-over-HTTPS via libgit2 for self-hosted Forgejo / Gitea / Bitbucket Server.
- **v1.3:** Webhook sink (POST JSON to any URL).
- **v1.4:** iPad / Mac Catalyst.
- **v1.5:** Russian / Portuguese localization.
