# App Store Connect listing — Pulse Commit v1.0.2

App Store Connect metadata for version 1.0.2 (name and subtitle change, Webhook destination). Version 1.0 is free, with no trial, in-app purchase, or Pro tier.

## App Name

Pulse Commit: Health Export

## Subtitle

Apple Health for AI agents

## Promotional Text

Daily Apple Health exports for your own AI agent as JSON and Markdown, via Telegram, GitHub or webhook. Free, no backend, no analytics, open source.

## What's New (1.0.2)

- New Webhook destination: each exported day is sent as one JSON POST to an HTTPS URL you own, with an optional token. Use it with any agent, automation tool or script that accepts a webhook.
- Shortcuts exports can target "Webhook only" or "All configured destinations".
- The Home export button no longer shifts while an export runs.
- A failed export's reason opens its History entry.
- Destinations you have not configured show OFF.
- App renamed to Pulse Commit: Health Export.

## What's New (1.0.1)

- Settings → About: Version opens a changelog; Website, Source code and Contact links open in Safari or Mail.
- Workout reports show one split series. Apple Watch records kilometer and mile splits in parallel; Telegram messages now list the main series (labeled km or mile splits) instead of mixing both. All splits stay in the JSON.
- After a few successful exports, the app may ask for an App Store rating once. iOS limits how often this appears.

## Description

Daily Apple Health exports for your own AI agent, or any script or service that reads JSON.

Pulse Commit sends the Apple Health categories you select to Telegram, a GitHub repository or your own webhook. The agent is yours; the app has no backend. Exports are JSON and Markdown, with GPX for routes.

WHAT IT DOES

1. Request read-only access to the Apple Health categories you choose.
2. Connect Telegram with a bot token and chat ID, connect GitHub through OAuth Device Flow and select a repository, or add a webhook URL.
3. Review the destination-specific disclosure, then export.

Each successful GitHub delivery creates a new commit with summary.json and summary.md, plus samples/*.json for enabled categories, workouts/*.json for workouts present, and routes/*.gpx for workouts with route data. Every JSON file has schema_version 1.0.

Webhook exports are one JSON POST per exported day to an HTTPS URL you own, sent up to 3 times in total on network errors, 408, 429 or 5xx, with one Idempotency-Key. It has an optional token, sent as Authorization: Bearer or in a header you name. The body holds summary.json (with workout details and State of Mind), the summary.md text and a file manifest; raw samples, workout files and routes are not sent. Redirects and local network addresses are refused.

Telegram exports contain a Markdown summary and ZIP attachment. Its setup screen can send a labeled sample message before any export.

An optional, separate consent can send one text-only Telegram message after a finished workout is saved to Apple Health. These messages omit routes, GPS points, raw heart-rate samples, custom zones, full-day totals, ZIP files and JSON. iPhone lock, sync, network and background scheduling can delay delivery. An uncertain request is not resent automatically; manual retry warns about possible duplication.

When several destinations are enabled, one may receive data even if the overall run fails because another destination failed. Retrying can create another GitHub commit, repeat a Telegram message and ZIP that already arrived, or deliver a webhook request again. History shows the overall result.

PRIVACY

Health data is read on-device and sent only for manual exports you trigger or automatic finished-workout delivery you separately authorize. Tokens stay in Apple Keychain. Pulse Commit has no developer backend, analytics, crash reporter, advertising SDK, or built-in AI. An AI agent receives data only if you point a destination at one. If your agent uses a third-party AI service, that service receives what you send. Pulse Commit does not control it.

The app contacts api.github.com, GitHub's device-flow endpoints on github.com, api.telegram.org, and the webhook host you enter. It does not send Health data to the developer.

Repository collaborators and readers may see GitHub exports. Chat members and bot operators may see or process Telegram exports. The operator of your webhook server may see and keep webhook exports. Remote copies remain until you delete them with the destination service. Resetting Pulse Commit removes local data and consent receipts; it does not delete remote commits, messages or webhook data.

AUTOMATION

Pulse Commit provides three actions to Apple Shortcuts:

- Export Last Day: yesterday's completed local day.
- Export Health Data: Today or a selected 1-day, 7-day, or 30-day window and destination.
- Backfill Range: a custom completed-day range.

Approve destination consent in Pulse Commit before an automation can export. Locked-device Health access and iOS scheduling can prevent an automation from finishing; open Pulse Commit and retry.

PRICE

Pulse Commit 1.0 is free. There is no export limit, in-app purchase, or subscription.

If you don't have a GitHub repo, a Telegram bot or your own HTTPS endpoint, this isn't for you. The destinations are yours; Pulse Commit does not host them.

Requires iOS 17.0 or later. State of Mind export is available on iOS 18 or later.

Support: hi@pulsecommit.app

## Keywords

```
telegram,webhook,llm,json,healthkit,github,gpx,shortcuts,markdown,hrv,sleep,steps,automation,backup
```

## URLs

- Support URL: `https://pulsecommit.app/support`
- Marketing URL: `https://pulsecommit.app`
- Privacy Policy URL: `https://pulsecommit.app/privacy`
- Terms of Use URL: `https://pulsecommit.app/terms`

All four URLs returned HTTP 200 on 2026-09-22 at 23:28:52 UTC. Recheck them from a clean network before submission. Apple's platform metadata reference requires the Support URL to lead to actual contact information as required by local law; the Account Holder must verify that content, not only the status code.

## Age Rating

Pending Account Holder completion of the current App Store Connect age-rating questionnaire. Do not copy the old hard-coded `12+` draft or infer questionnaire answers from the fact that the app reads Health data. Apple generates the rating from the submitted content-descriptor, capability, and control answers; those answers and the generated regional ratings must be reviewed in App Store Connect against the candidate build.

Reference: [Apple — Age ratings values and definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions).

## Category

- Proposed primary: Health & Fitness
- Proposed secondary: Developer Tools
- Account selection: **NOT VERIFIED**

## Pricing

- Owner decision 2026-11-17: version 1.0 is free. No trial, no in-app purchase, no Pro tier, no subscription.
- App price in App Store Connect: Free. Account state: **NOT VERIFIED**.
- The build contains no StoreKit code. An in-app purchase product created earlier in App Store Connect must not be attached to the 1.0 version.

## Privacy nutrition

App Privacy answers: **NOT VERIFIED**. The repository shows no developer backend and the developer does not receive Health data, but the Account Holder must answer the current questionnaire using Apple's definitions and account evidence. User-directed transfers to GitHub, Telegram and the webhook endpoint must be considered. Do not treat this draft as a completed `Data Not Collected` declaration.

Candidate explanation for the Account Holder to validate before use:

> Pulse Commit reads selected Apple Health data on-device. It sends data for manual exports the user triggers or separately authorized automatic finished-workout delivery to configured destinations. The developer operates no server that receives Health data.

## Primary references checked 2026-09-22

- [Apple — Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)
- [Apple — Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [Apple — Age ratings values and definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions)
