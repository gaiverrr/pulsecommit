# Repeat Export Policy

Pulse Commit's "Export Now" button is intentionally **side-effecting on every tap**. There is no client-side dedup, no diff-based skip, and no cooldown.

## What every tap does

Every tap of Export Now (or any option from the long-press menu) produces:

- **GitHub:** one new commit. The day folder `YYYY-MM-DD/` is overwritten in full — `summary.json`, `samples/*.json`, `workouts/*.json`, `routes/*.gpx`, and `summary.md` are all replaced with the current snapshot. The commit message keeps the form `Pulse Commit · YYYY-MM-DD · ...`.
- **Telegram:** one new summary message + one new ZIP attachment. No dedup.
- **History:** one row per tap.

The commit history therefore shows the **progression** of a day's data as the user re-exports throughout the afternoon. This is intentional — users asked to see how their day evolved rather than collapse into a single end-of-day commit.

## Cursor advancement

Only the smart modes advance the cursor:

| Mode | Source | Advances cursor? |
|---|---|---|
| `.todayLive` | Smart default (PM) | Yes → `startOfDay(now)` |
| `.lastDayOnly` | Smart default (AM) | Yes → `startOfDay(now)` |
| `.incremental` | App Intent backfill | Yes → `startOfDay(now)` |
| `.lastNDays(N)` | Long-press → Last 7 / 30 days | **No** |
| `.range(from:to:)` | Long-press → Custom range | **No** |

Backfill modes (`lastNDays`, `range`) are explicit one-shot operations and do not move the cursor — they are diagnostic / catch-up workflows, not the regular daily sync.

## Idempotency

There is none, by design. Repeat taps create repeat commits. If a user wants to avoid duplicates they should not tap the button.

## Future work (out of scope)

- A post-tap cooldown (e.g. 10 s) to prevent accidental double-tap spam.
- A skip-if-identical optimisation comparing the new snapshot against the most-recent commit tree.

Neither is shipping in v1.0.
