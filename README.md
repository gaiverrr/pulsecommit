# Pulse Commit

iOS 17+ app that exports Apple Health (HealthKit) data to two user-owned destinations: a GitHub repository (atomic daily commit) and a Telegram chat (MarkdownV2 summary + ZIP). A separate off-by-default consent can send a text-only Telegram message for each finished workout saved to Health, with local deduplication and no route, raw samples, daily payload, ZIP or JSON. No backend, no analytics, no subscriptions, no in-app purchase: version 1.0 is free.

[Download on the App Store](https://apps.apple.com/app/pulse-commit/id6830329627) · [Website](https://pulsecommit.app) · [Privacy](https://pulsecommit.app/privacy)

Pull requests are welcome: new Health categories, export formats, destinations, fixes. Read [CONTRIBUTING.md](CONTRIBUTING.md) first; for anything larger than a bug fix, open an issue to agree on the approach before writing code. Architecture, design tokens and known pitfalls are in [AGENTS.md](AGENTS.md).

## Example export

Real data from the maintainer's own exports. GPS routes and raw sample files are omitted here.

### Telegram

A monospace summary followed by a ZIP of the JSON files (2026-11-23):

```
🫀 Pulse Commit · 2026-11-23

Activity
  Steps              19 651
  Active energy      1532 kcal
  Rings              Stand 3h · Exercise 100m

Heart
  Resting HR         57 bpm
  HRV (SDNN)         35 ms · 9 measurements
  VO₂ max            65

Sleep
  Duration           6h 59m
  Stages             Deep 0h57m · REM 1h26m · Core 4h35m
  Awake              13 min
  Fell asleep        2026-11-23 00:21
  Woke up            2026-11-23 07:34

Sleep breathing
  Respiratory rate   14.5 breaths/min

Body
  Weight             78.7 kg

Wrist temperature
  Sleeping temp      36.96 °C
  Change             +0.71 °C
  Baseline           PulseCommit: 36.26 °C · 13 nights / 28d

Workouts (1)
  Outdoor Run
    Time (Europe/Lisbon): 18:44–20:20
    Duration: 1h 32m 8.9s · Distance: 17.0 km
    Avg pace: 5:25/km · Active energy: 1209 kcal
    Heart rate: avg 125 bpm · max 210 bpm
    Recorded segments (29, elapsed)
      …

Raw sample counts
  hrv_sdnn           9
  respiratory_rate   43
  wrist_temperature  1

Generated: 2026-11-23 22:21
Latest sample: 2026-11-23 22:08
Time zone: Europe/Lisbon
schema_version: 1.0

📎 pulse-commit-2026-11-23.zip · 369.1 KB · 16 files
```

### GitHub

Each export is one commit (2026-08-28):

```
chore: pulse 2026-08-28 · 10055 steps · 2 workouts · sleep 6h54m
```

```
2026-08-28/
├── summary.json
├── summary.md
├── samples/
│   ├── active_energy.json
│   ├── activity_rings.json
│   ├── body_mass.json
│   ├── distance_walking_running.json
│   ├── heart_rate.json
│   ├── hrv_sdnn.json
│   ├── resting_heart_rate.json
│   ├── sleep.json
│   ├── steps.json
│   ├── vo2_max.json
│   └── workouts.json
├── workouts/
│   ├── B9E9A3ED-…-walking.json
│   └── C044D152-…-swimming.json
└── routes/
    └── B9E9A3ED-…-walking.gpx
```

`summary.json` (excerpt):

```json
{
  "schema_version": "1.0",
  "date": "2026-08-28",
  "timezone": "Europe/Lisbon",
  "metrics": {
    "steps": { "total": 10055, "unit": "count" },
    "active_energy": { "total": 919, "unit": "kcal" },
    "resting_heart_rate": { "value": 53, "unit": "bpm" },
    "hrv_sdnn": { "avg": 50, "unit": "ms" },
    "vo2_max": { "value": 61.7, "unit": "ml/kg·min" },
    "sleep": {
      "duration_minutes": 414,
      "stage_deep": 45, "stage_rem": 81, "stage_core": 287, "stage_awake": 10,
      "unit": "min"
    },
    "body_mass": { "value": 77.7, "unit": "kg" }
  },
  "workouts": [
    { "type": "walking", "duration_minutes": 45, "distance_km": 4.2, "active_energy_kcal": 220, "has_route": true },
    { "type": "swimming", "duration_minutes": 35, "distance_km": 1.5, "active_energy_kcal": 363, "has_route": false }
  ],
  "unavailable_categories": ["nutrition"]
}
```

## Setup

Install XcodeGen (one-time):

```bash
brew install xcodegen
```

Generate the Xcode project from `project.yml`:

```bash
xcodegen generate
open PulseCommit.xcodeproj
```

Never edit the generated `.xcodeproj` directly — change `project.yml` and re-run `xcodegen generate`.

## Tests

```bash
swift test --package-path Packages/HealthCore
xcodebuild test -project PulseCommit.xcodeproj -scheme PulseCommit \
  -destination 'platform=iOS Simulator,name=<any installed iPhone simulator>'
```

## Telegram health details

Standard and verbose reports include:

- HRV SDNN average and measurement count, for example `47 ms · 20 measurements`.
- Recorded sleep duration, stages, awake minutes, and the main sleep session's start/end times.
- Average respiratory rate during recorded asleep intervals, when **Sleep Respiratory Rate** is enabled and HealthKit supplies both breathing and sleep data.
- Sleeping wrist temperature and deviation from a clearly labelled PulseCommit baseline, when **Wrist Temperature** is enabled and enough previous nights are available.
- Estimated time in custom heart-rate zones with measured-time coverage, after configuring **Settings → Heart Rate Zones**.
- Average and maximum workout heart rate from the workout's associated HealthKit statistics, when available.
- Separate **Generated** and **Latest sample** timestamps, displayed in the export's time zone. Latest sample is the latest completed measurement in the enabled, available raw data for that export day; it is omitted when unknown. Neither timestamp guarantees that Apple Watch has finished syncing.

Sleep summaries group stages separated by less than three hours into sessions and assign each session to its local wake date, including sleep beginning the previous evening. The summary reads back 24 hours before the export window to recover overnight stages. Duration and awake minutes cover the day's sessions; start/end times describe the session with the most recorded sleep, so a daytime nap does not replace the main sleep times. Raw sample files retain their original timestamps and start-date bucketing.

Existing installations can enable **Categories → Sleep Respiratory Rate** and **Categories → Wrist Temperature**; the toggles request the corresponding read permissions (including sleep for respiratory rate). New installations include both in the default categories and onboarding permission request. Missing or denied data is omitted. Compact Telegram summaries keep their concise metrics and add the timestamp footer.

JSON changes are additive: `metrics.hrv_sdnn.sample_count`, `metrics.sleep.sleep_start`, `metrics.sleep.sleep_end`, `metrics.respiratory_rate.sleep_avg`, `metrics.respiratory_rate.sample_count`, and optional top-level `latest_sample_at`. Existing fields and schema version `1.0` remain. Sleep timestamps are ISO 8601; respiratory rate uses breaths/min.

### Temperature baseline and workout zones

Apple documents [sleeping wrist temperature](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/applesleepingwristtemperature) as an **absolute** value. PulseCommit calculates its own baseline: the mean of the previous 28 local days' nightly means, requiring at least five nights. Each night has equal weight. Only samples with the same source bundle ID and source name as the latest current-night sample are included; these source fields do not uniquely identify physical watch hardware. Nights are grouped by the measurement's local end date. The current night is excluded from its baseline. With fewer than five previous nights, the report shows the absolute temperature and baseline progress, without a deviation. The report labels the baseline **PulseCommit**; it is not Apple's Health baseline.

To enable workout zones, enter four increasing whole-number boundaries (the starts of zones 2–5) in **Settings → Heart Rate Zones**. No thresholds are assumed. You can copy your boundaries from Apple Watch settings; HealthKit does not expose those settings. Zone 1 is below the first boundary; a value exactly on a boundary belongs to the higher zone.

Zone durations use only heart-rate samples associated with the workout. Each reading is held forward until the next reading or for at most 30 seconds, clipped at workout end and pauses. Resuming requires a fresh reading; paused readings are ignored. Duplicate timestamps are averaged. Reports label zones **custom, estimated** and show HR-covered time alongside active workout time, so gaps do not appear measured. If imported workout duration disagrees with its available pause events by more than one second, zones are omitted because pause locations are uncertain. Missing readings or unset boundaries also omit zones; available average/maximum HR still appears.

Additional JSON fields remain additive under schema `1.0`: `metrics.wrist_temperature` contains `avg_c`, `sample_count`, baseline night/window/minimum counts, method and source labels, plus `baseline_c` and `deviation_c` when available. Workout entries in both `summary.json` and `workouts/*.json` can include `heart_rate_zones` with four `lower_bounds_bpm`, five `seconds_by_zone` values in Z1–Z5 order, `active_seconds`, and the calculation `method`. Covered seconds equal the sum of zone durations. Older workout JSON without zones still decodes.

## License

The source code is released under the [MIT License](LICENSE). The Pulse Commit name, app icon and logo are not covered by the license: forks must use a different name and icon before distributing a build.
