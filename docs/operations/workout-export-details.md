# Workout export details

Pulse Commit exports the workout values that HealthKit provides on each `HKWorkout`. Standard and verbose summaries include the workout's local start and end time, recorded duration, distance, active energy, average and maximum heart rate, and an activity-appropriate average pace or speed when the required source values exist. Compact summaries keep only the workout count.

`duration_seconds` is HealthKit's recorded workout duration. It can be shorter than the wall-clock interval from `start_date` to `end_date` when the workout was paused. Running, walking, and hiking pace and cycling speed use this duration with the unrounded `distance_meters`; they are not derived from the rounded display values or route points. The existing `duration_minutes` and `distance_km` fields remain for schema 1.0 compatibility.

HealthKit may attach recorded `.lap` and `.segment` events. Pulse Commit keeps positive elapsed intervals wholly inside the workout, preserves overlapping segments, and exports all accepted records in JSON. Summary text shows at most four laps and four segments per workout and reports how many additional records remain in JSON. These are source-recorded elapsed intervals: they are not reconstructed kilometre splits, and segments are not inferred work or rest periods. Point markers, pause/resume events, zero-duration legacy laps, malformed intervals, and event metadata are omitted.

All richer fields are optional. A missing distance, energy, heart-rate value, route, or recorded interval does not identify the reason; it can reflect source behavior, sync timing, association, or HealthKit access. Pulse Commit does not label missing data as denied or normal. Heart-rate averages and maxima remain HealthKit workout statistics. Custom heart-rate zones remain Pulse Commit estimates based on the user's configured boundaries and retain their coverage line.

Automatic finished-workout messages reuse these display semantics for duration, distance, energy, pace or cycling speed, average/maximum heart rate, laps and segments. They add the workout's local date/time and timezone, omit custom zones and the “more in JSON” remainder wording, and never attach the manual daily ZIP or include routes/GPS, raw heart-rate samples, full-day data or JSON. The automatic renderer omits non-finite and out-of-range numeric values rather than inventing or overflowing display values.

Synthetic standard-summary example:

```text
Workouts (1)
  Outdoor Run
    Time (Europe/Lisbon): 18:02–18:49
    Duration: 44m 32s · Distance: 8 km
    Avg pace: 5:34/km · Active energy: 612 kcal
    Heart rate: avg 152 bpm · max 176 bpm
    Recorded laps (5, elapsed)
      Lap 1: 18:02:00–18:07:00 · 5m 0s
      Lap 2: 18:07:00–18:12:00 · 5m 0s
      Lap 3: 18:12:00–18:17:00 · 5m 0s
      Lap 4: 18:17:00–18:22:00 · 5m 0s
      +1 more lap in JSON
```

HealthKit references: [workout duration](https://developer.apple.com/documentation/healthkit/hkworkout/duration), [workout events](https://developer.apple.com/documentation/healthkit/hkworkoutevent), [laps](https://developer.apple.com/documentation/healthkit/hkworkouteventtype/lap), and [segments](https://developer.apple.com/documentation/healthkit/hkworkouteventtype/segment).
