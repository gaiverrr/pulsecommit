## Privacy Policy

Pulse Commit has no servers. No developer collects, stores, or sees your data.

Last updated: 2026-11-26.

## What we collect

Nothing. The app reads selected Apple Health data on your device and writes it directly to destinations you configure. The developer operates no backend, no analytics, no telemetry, no crash reporter, no advertising SDK.

## Where your data goes

Before a Health export, Pulse Commit requires separate affirmative consent for each exact destination. The disclosure identifies the selected categories and the GitHub repository, branch and subdirectory, the Telegram chat and topic, or the webhook URL. A changed destination, category set or disclosure version requires consent again.

GitHub exports contain `summary.json`, `summary.md`, raw `samples/*.json`, workout JSON and route files when available. Repository collaborators and organization readers can access them; if the repository is public, anyone can. GitHub retains commits under the repository and account settings.

Telegram exports contain a Markdown summary and ZIP attachment. Chat members, bot operators and Telegram may process and retain them. An AI service may also process a message only when you chose an AI-backed bot or chat. Pulse Commit itself has no AI integration.

Webhook exports are one HTTPS POST to the URL you enter, with an optional token you set. The request contains `summary.json`, the `summary.md` text and a list of the files in the export. The owner of that URL receives it and can keep it. Pulse Commit cannot delete it. If a third-party AI service runs behind your endpoint, that service receives the data too. Pulse Commit itself has no AI integration.

If you separately opt in to automatic finished-workout messages, Pulse Commit checks Apple Health for workouts saved during the last 72 hours after that opt-in time. It sends one text-only Telegram message per workout to the exact bot, chat and optional topic shown in the disclosure. The message can contain workout type, local start and end time with timezone, recorded duration, and available distance, energy, pace or speed, average and maximum heart rate, laps and segments. It does not include route or GPS points, raw heart-rate samples, custom heart-rate zones, full-day totals, ZIP files or JSON. Delivery can be delayed while the iPhone is locked, offline or not given background time.

Automatic delivery keeps only local delivery metadata: workout UUID, workout end time, destination/consent fingerprint, attempt count, timestamps, delivery state and Telegram message ID when confirmed. It does not store a Health payload in this ledger. The file uses iOS complete file protection, is excluded from backup, and is removed by Reset all data. An interrupted request can have an unknown result; Pulse Commit does not resend it automatically. A manual retry warns that Telegram may already have the message.

Only to destinations you set up yourself:

- The GitHub repository you connect (via `api.github.com` and the GitHub Device Flow endpoints `https://github.com/login/device/code` and `https://github.com/login/oauth/access_token`).
- The Telegram chat you connect (via `api.telegram.org`).
- The HTTPS webhook URL you enter (the host of that URL).

The full list of outbound hosts in the production build:

- `api.github.com`
- `github.com` (Device Flow only)
- `api.telegram.org`
- the HTTPS webhook URL you enter

No other host is contacted. Pulse Commit has no server of its own.

## How to revoke

Disable automatic workout messages, disable or disconnect Telegram, or disable the Workouts category to stop future automatic attempts and clear that separate consent. Replacing the Telegram bot token, changing the chat or topic, changing selected categories, or using Reset all data also disables automatic workout delivery. Messages already sent or in flight cannot be recalled. Manual destination consent remains separate.

Disable or disconnect a destination to stop future manual exports and clear its local consent receipt. Replacing the Telegram bot token, or changing the repo, branch, subdirectory, chat, topic, webhook URL or selected categories, requires a new consent.

1. In Pulse Commit, open Destinations → GitHub and sign out. This deletes the OAuth token from the iOS Keychain.
2. In Telegram, talk to `@BotFather` and revoke (or delete) the bot you created. Then open Destinations → Telegram in Pulse Commit and clear the bot token field.
3. In iOS Settings → Privacy & Security → Health → Pulse Commit, turn off any category you no longer want the app to read.

## How to delete data

Reset all data removes local preferences, tokens, history, cursor and consent receipts. It cannot delete remote copies. Delete commits and files in GitHub, and delete Telegram messages or contact the bot operator where applicable. For a webhook, contact the owner of the endpoint.

The developer holds no copy of your data, so there is nothing for us to delete.

- To delete what was exported: delete the GitHub repository (or specific commits) and delete the Telegram chat history, and ask the owner of your webhook endpoint to delete what it received.
- To delete local state: open Pulse Commit → Settings → Reset all data. This wipes the history database, the export cursor, and the Keychain tokens on this device. It does not touch your GitHub repo or Telegram chat.

## Third-party services we depend on

- Apple — HealthKit (data source), App Store (distribution).
- GitHub — the repository you choose to commit to. Their privacy policy applies to your repo.
- Telegram — the chat you choose to send messages to. Their privacy policy applies to that chat.
- Your webhook endpoint — whoever operates the URL you enter. Their privacy policy applies to what it receives.

The app embeds one open-source library: ZIPFoundation (MIT). It runs on-device only and makes no network calls.

## No advertising / no data brokers / no analytics

The app contains no advertising SDKs, no data broker integrations, and no analytics. There is no event log to share, sell, or hand over.

## HealthKit-specific notice

In accordance with Apple App Review Guideline 5.1.3, Pulse Commit does not use HealthKit data for advertising or for any purpose other than manual exports you explicitly trigger or automatic finished-workout delivery you separately authorize. HealthKit data is never transmitted to the developer. It is written only to the destinations you configure and authorize.

## Contact

`hi@pulsecommit.app`
