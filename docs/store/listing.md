# App Store Connect listing — Pulse Commit v1.0

App Store Connect metadata for version 1.0. Version 1.0 is free, with no trial, in-app purchase, or Pro tier.

## App Name

Pulse Commit

## Subtitle

Apple Health export to GitHub

## Promotional Text

Export Apple Health to your GitHub repo or Telegram chat. No developer backend, analytics, subscription, or in-app purchase.

## Description

Your Apple Health, committed daily to your own GitHub repo.

Pulse Commit reads the Apple Health categories you select and exports them to destinations you configure: a GitHub repository, a Telegram chat, or both.

WHAT IT DOES

1. Request read-only access to the Apple Health categories you choose.
2. Connect Telegram with a bot token and chat ID, or connect GitHub through OAuth Device Flow and select a repository.
3. Review the destination-specific disclosure, then export.

Each successful GitHub delivery creates a new commit containing summary.json and summary.md. It also includes samples/*.json for enabled categories with readable samples, workouts/*.json for workouts present, and routes/*.gpx only for workouts with route data. Re-exporting the same day creates another commit. Every JSON file carries schema_version 1.0.

Telegram exports contain a Markdown summary and ZIP attachment. Its setup screen can send a clearly labeled sample message before any Health export.

An optional, separate consent can send one text-only Telegram message after a finished workout is saved to Apple Health. Pulse Commit checks a rolling 72-hour window after the current opt-in time and locally deduplicates by workout. These messages omit routes, GPS points, raw heart-rate samples, custom zones, full-day totals, ZIP files and JSON. iPhone lock, sync, network and background scheduling can delay delivery. An uncertain request is not resent automatically; manual retry warns about possible duplication.

When both destinations are enabled, one may receive data even if the overall run fails because the other destination failed. Retrying can create another GitHub commit or repeat a Telegram message and ZIP that already arrived. History shows the overall result.

PRIVACY

Health data is read on-device and sent only for manual exports you trigger or automatic finished-workout delivery you separately authorize. Tokens stay in Apple Keychain. Pulse Commit has no developer backend, analytics, crash reporter, advertising SDK, or AI integration.

The app contacts api.github.com, GitHub's device-flow endpoints on github.com, and api.telegram.org. It does not send Health data to the developer.

Repository collaborators and readers may see GitHub exports. Chat members and bot operators may see or process Telegram exports. Remote copies remain until you delete them with the destination service. Resetting Pulse Commit removes local data and consent receipts; it does not delete remote commits or messages.

AUTOMATION

Pulse Commit provides three actions to Apple Shortcuts:

- Export Last Day: yesterday's completed local day.
- Export Health Data: Today or a selected 1-day, 7-day, or 30-day window and destination.
- Backfill Range: a custom completed-day range.

Approve destination consent in Pulse Commit before an automation can export. Locked-device Health access and iOS scheduling can prevent an automation from finishing; open Pulse Commit and retry.

PRICE

Pulse Commit 1.0 is free. There is no export limit, in-app purchase, or subscription. Every feature, including multi-day windows, custom backfill, and automatic finished-workout messages, is available to everyone.

If you don't have a GitHub account or a Telegram bot, this app is not for you. The destinations are yours; Pulse Commit does not host them.

Requires iOS 17.0 or later. State of Mind export is available on iOS 18 or later.

Support: hi@pulsecommit.app

## Keywords

```
telegram,json,healthkit,data,auto,backup,gpx,shortcuts,quantified,self,workout,sleep,hrv,git,steps
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

App Privacy answers: **NOT VERIFIED**. The repository shows no developer backend and the developer does not receive Health data, but the Account Holder must answer the current questionnaire using Apple's definitions and account evidence. User-directed transfers to GitHub and Telegram must be considered. Do not treat this draft as a completed `Data Not Collected` declaration.

Candidate explanation for the Account Holder to validate before use:

> Pulse Commit reads selected Apple Health data on-device. It sends data for manual exports the user triggers or separately authorized automatic finished-workout delivery to configured destinations. The developer operates no server that receives Health data.

## Primary references checked 2026-09-22

- [Apple — Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)
- [Apple — Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [Apple — Age ratings values and definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions)
