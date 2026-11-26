---
name: pulse-commit-health
description: Read Apple Health data that the Pulse Commit iOS app exported to a GitHub repository. Use when asked about the user's steps, sleep, heart rate, HRV, workouts, weight or other daily health metrics, or when a repo contains dated folders with summary.json.
---

# Pulse Commit health data

Status: not yet tested end to end.

Pulse Commit writes one commit per exported day to a GitHub repository the user owns. Read it with `git`, `gh` or the GitHub contents API. Do not guess values: if a file or field is missing, say so.

## Layout

```
<YYYY-MM-DD>/
  summary.json      daily totals and averages, start here
  summary.md        the same day as readable text
  samples/*.json    raw samples per category (steps.json, heart_rate.json, sleep.json, ...)
  workouts/*.json   one file per workout, named <id>-<type>.json
  routes/*.gpx      GPS route for a workout, only when it has one
```

The commit message looks like `chore: pulse 2026-08-28 · 10055 steps · 2 workouts · sleep 6h54m`.

## How to read it

1. List the top-level folders and keep names that match `YYYY-MM-DD`. Sort them to find the latest day or a range.
2. Read `<date>/summary.json` first. Fields:
   - `schema_version`, `date`, `timezone`
   - `metrics`: an object keyed by category, for example `steps.total`, `active_energy.total`, `resting_heart_rate.value`, `hrv_sdnn.avg`, `vo2_max.value`, `sleep.duration_minutes` with `stage_deep`, `stage_rem`, `stage_core`, `stage_awake`, `body_mass.value`. Each has a `unit`.
   - `workouts`: a list with `type`, `duration_minutes`, `distance_km`, `active_energy_kcal`, `has_route`
   - `unavailable_categories`: categories with no data that day
3. Use `summary.md` when you need to quote or show the day as text.
4. Open `samples/<category>.json` only when the summary is not enough, for example to see heart rate over the day. Samples can be large; read one file at a time.
5. For a workout, open `workouts/<id>-<type>.json`. Read `routes/<id>-<type>.gpx` only if `has_route` is true.
6. For trends, read `summary.json` for each day in the range. Do not read all samples.

Only categories the user enabled appear. A missing key means no data or a disabled category, not zero.

## schema_version

Every JSON file carries `"schema_version"`, currently `"1.0"`. Changes within a major version are additive, so ignore unknown fields. If the major version is not `1`, stop and tell the user the format changed instead of guessing at field meanings.

## Rules

- Times are in the file's `timezone`. Convert before comparing days.
- Report units with every number. Do not give medical advice or diagnoses; this is personal tracking data.
- Do not write to the repository or copy health data to other services unless the user asks.

Format reference: the example export in the [Pulse Commit README](../../../../README.md#github).
