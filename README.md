# Pulse Commit

iOS 17+ app that exports Apple Health (HealthKit) data to two user-owned destinations: a GitHub repository (atomic daily commit) and a Telegram chat (MarkdownV2 summary + ZIP). A separate off-by-default consent can send a text-only Telegram message for each finished workout saved to Health, with local deduplication and no route, raw samples, daily payload, ZIP or JSON. No backend, no analytics, no subscriptions, no in-app purchase: version 1.0 is free.

[Download on the App Store](https://apps.apple.com/app/pulse-commit/id6830329627) · [Website](https://pulsecommit.app) · [Privacy](https://pulsecommit.app/privacy)

Pull requests are welcome: new Health categories, export formats, destinations, fixes. Read [CONTRIBUTING.md](CONTRIBUTING.md) first; for anything larger than a bug fix, open an issue to agree on the approach before writing code. Architecture, design tokens and known pitfalls are in [AGENTS.md](AGENTS.md).

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
