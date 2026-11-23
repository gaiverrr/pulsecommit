# Pulse Commit

Pulse Commit is an iOS 17+ app that exports Apple Health data to a GitHub repository you own, a Telegram chat, or both. Each GitHub export is one commit; each Telegram export is a MarkdownV2 summary plus a ZIP of the JSON files. If you opt in separately, the app also sends a short text message to Telegram for every finished workout saved to Health. That message has no route, raw samples, ZIP or JSON, and the app deduplicates it locally. There is no backend, no analytics and no in-app purchase. Version 1.0 is free.

[Download on the App Store](https://apps.apple.com/app/pulse-commit/id6830329627) · [Website](https://pulsecommit.app) · [Privacy](https://pulsecommit.app/privacy)

Pull requests are welcome, for example new Health categories, export formats, destinations or bug fixes. Read [CONTRIBUTING.md](CONTRIBUTING.md) first, and for anything larger than a bug fix, open an issue so we agree on the approach before you write code. [AGENTS.md](AGENTS.md) covers the architecture, design tokens and known pitfalls.

## Example export

These come from the maintainer's own exports, minus GPS routes and raw sample files.

### Telegram

The message for 2026-11-23, sent with a ZIP of the JSON files:

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

Each export is one commit. This one is from 2026-08-28:

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

An excerpt from `summary.json`:

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

Install XcodeGen once:

```bash
brew install xcodegen
```

Generate the Xcode project from `project.yml`:

```bash
xcodegen generate
open PulseCommit.xcodeproj
```

Change `project.yml` and rerun `xcodegen generate` instead of editing the generated `.xcodeproj`.

## Tests

```bash
swift test --package-path Packages/HealthCore
xcodebuild test -project PulseCommit.xcodeproj -scheme PulseCommit \
  -destination 'platform=iOS Simulator,name=<any installed iPhone simulator>'
```

## Telegram health details

Standard and verbose reports include:

- HRV SDNN average and measurement count, for example `47 ms · 20 measurements`.
- Recorded sleep duration, stages, awake minutes, and the start and end times of the main sleep session.
- Average respiratory rate during recorded sleep, when Sleep Respiratory Rate is enabled and HealthKit has both breathing and sleep data.
- Sleeping wrist temperature and its change from a baseline labelled PulseCommit, when Wrist Temperature is enabled and enough earlier nights exist.
- Estimated time in custom heart-rate zones and how much of the workout had heart-rate readings, once you set zones in Settings → Heart Rate Zones.
- Average and maximum workout heart rate from the workout's HealthKit statistics, when available.
- Generated and Latest sample timestamps in the export's time zone. Latest sample is the most recent completed measurement in the enabled raw data for that day and is left out when unknown. Neither timestamp means Apple Watch has finished syncing.

Sleep stages less than three hours apart form one session, and each session belongs to the local date you woke up, so sleep that starts the previous evening counts for the next day. To catch overnight stages, the summary reads 24 hours further back than the export window. Duration and awake minutes cover all of the day's sessions. Start and end times come from the session with the most recorded sleep, so a daytime nap does not replace your night. Raw sample files keep their original timestamps and are bucketed by start date.

Sleep Respiratory Rate and Wrist Temperature are on by default for new installs, and onboarding asks for their permissions. On an existing install, turn them on in Categories; the toggles ask for the read permissions they need, including sleep for respiratory rate. Missing or denied data is left out. Compact Telegram summaries keep their short metric list and add the timestamp footer.

These fields are additive under schema `1.0`: `metrics.hrv_sdnn.sample_count`, `metrics.sleep.sleep_start`, `metrics.sleep.sleep_end`, `metrics.respiratory_rate.sleep_avg`, `metrics.respiratory_rate.sample_count`, and an optional top-level `latest_sample_at`. Sleep timestamps are ISO 8601, and respiratory rate is in breaths/min.

### Temperature baseline and workout zones

Apple documents [sleeping wrist temperature](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/applesleepingwristtemperature) as an absolute value, so PulseCommit computes its own baseline. It is the mean of nightly means over the previous 28 local days, needs at least five nights, and weights each night equally. Only samples with the same source bundle ID and source name as the latest sample from the current night count, and those fields do not identify a specific watch. Nights are grouped by the local end date of the measurement, and the current night is excluded from its own baseline. With fewer than five earlier nights, the report shows the absolute temperature and how many nights the baseline has so far, with no deviation. The report labels the baseline PulseCommit because it is not Apple's Health baseline.

To get workout zones, enter four increasing whole-number boundaries in Settings → Heart Rate Zones. They are the starting points of zones 2 to 5. The app assumes no default thresholds. HealthKit does not expose Apple Watch zone settings, but you can copy them from the Watch. Zone 1 is everything below the first boundary, and a value exactly on a boundary belongs to the higher zone.

Zone durations use only heart-rate samples attached to the workout. Each reading counts until the next one, for at most 30 seconds, and stops at a pause or the end of the workout. After a resume, the app waits for a fresh reading and ignores readings taken during a pause. Readings with the same timestamp are averaged. Reports label zones as custom and estimated and show heart-rate-covered time next to active workout time, so gaps are not presented as measured. If an imported workout's duration and its pause events disagree by more than one second, the app leaves zones out because it cannot tell where the pauses were. Zones are also left out when readings are missing or boundaries are not set; average and maximum heart rate still appear when available.

Schema `1.0` also has these additive fields. `metrics.wrist_temperature` holds `avg_c`, `sample_count`, baseline night, window and minimum counts, method and source labels, and `baseline_c` and `deviation_c` when available. Workout entries in `summary.json` and `workouts/*.json` can include `heart_rate_zones` with four `lower_bounds_bpm`, five `seconds_by_zone` values ordered Z1 to Z5, `active_seconds`, and the calculation `method`. Covered seconds are the sum of the zone durations. Workout JSON without zones still decodes.

## License

The source code is under the [MIT License](LICENSE). The license does not cover the Pulse Commit name, app icon or logo, so a fork needs its own name and icon before distributing a build.
