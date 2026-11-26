# Webhook destination (1.0.2)

Status: draft for owner approval. Research: `export-destinations-research.md` (kept outside the repo).

## Goal

Send each export as one JSON `POST` to an HTTPS URL the user owns, so any AI agent or automation (OpenClaw, Hermes, n8n, Home Assistant, Zapier/Make, a Cloudflare Worker, a custom script) can receive it without the app running a backend.

## Payload

`Content-Type: application/json`, one request per exported day:

```json
{
  "schema_version": "1.0",
  "event_type": "daily_export",
  "date": "2026-11-23",
  "idempotency_key": "pc-2026-11-23-3f9a1c0b7e2d",
  "summary": { "...": "the summary.json object, unchanged" },
  "summary_markdown": "the summary.md text",
  "files": [ { "path": "samples/steps.json", "bytes": 1234 } ]
}
```

- `summary` is the same object as `summary.json` in GitHub exports.
- `summary_markdown` lets agent receivers use the text as a prompt directly (OpenClaw `{{payload.summary_markdown}}`, Hermes `{summary_markdown}`).
- `files` is a manifest only. Raw samples, workouts and GPX are not sent in 1.0.2 (they can exceed the 1 MB limit of agent gateways).

## Auth

One token, sent with every request. The URL may be public; without the token the receiver rejects the request.

- Default header: `Authorization: Bearer <token>`. The header name is editable (Hermes non-HMAC routes use `X-Gitlab-Token`, OpenClaw also accepts `x-openclaw-token`).
- The app can generate a random 32-byte token (base64url) with a Copy button, or the user can paste the token their receiver issued.
- Token optional: Home Assistant, Zapier and Make put the secret in the URL. If the token is empty, the screen shows a warning that anyone who knows the URL can post to it.
- URL and token live in Keychain only. History, errors and logs show the host only.
- Later (not 1.0.2): HMAC-SHA256 request signing with a timestamp, one scheme (Standard Webhooks or Hermes V2).

## Transport

- HTTPS only, publicly trusted certificate, no ATS exception keys. `http://`, URLs with user-info and LAN-only setups are rejected by validation.
- Redirects are refused (they would send data and the token to another host).
- `EphemeralAPISession`, 30 s timeout.
- Headers: `Content-Type`, `User-Agent: PulseCommit/<version>`, `Idempotency-Key` and `X-Request-ID` (same value), then the token header. The token header cannot override reserved headers.
- Success is any 2xx. Retries (3 attempts, short backoff) on transport errors, 408, 429 and 5xx, honouring `Retry-After`. Other 4xx fail immediately with the status code.
- Multi-day runs are paced (about one request every 2 s) to stay under typical 30 requests/minute limits.
- Idempotency key: `pc-<date>-<first 12 hex of SHA-256(summary.json)>`. Stable across retries within one run; a user re-run creates a new key. Receivers that want one record per day should upsert on `date`.

## Consent

- New identity `.webhook(scheme:host:port:path:)`. Changing any part requires fresh consent; rotating the token does not.
- Consent text (passes `scripts/verify-tone.sh`):

  > Pulse Commit will send the Health categories you selected to **hooks.example.com** over HTTPS each time you export to this destination.
  >
  > Pulse Commit does not run this server. Whoever operates it can read, keep and share what it receives. Pulse Commit cannot delete data after it is sent.
  >
  > If this address belongs to an AI agent or an automation service, that service will process your Health data.

- "Send test" posts a synthetic body with no Health data (`event_type: "test"`) and needs no Health consent.
- `authorizePayload` rechecks consent right before each request, as the Telegram sink does.

## Shortcuts

`DestinationOption` raw values are stored in users' saved shortcuts, so `both`, `githubOnly` and `telegramOnly` keep their identifiers and meaning: `both` stays GitHub + Telegram and never starts sending to a webhook. New cases: `webhookOnly` and `allEnabled` (every configured, consented destination).

## Code

HealthCore (URLProtocol-stub tests, test-first):
- `Sinks/Webhook/WebhookSink.swift` (`id = "webhook"`), `WebhookPayload` encoder, `WebhookEndpointValidator`, `WebhookSinkError: LocalizedError` (status codes only, never URL path or token).

App:
- Destinations → Webhook screen: URL, token (Generate / Paste / Copy), header name, Send test, last result.
- `HealthExportDestinationKind.webhook`, consent identity, `AppContainer` wiring, Keychain storage, History row with host and status.

Tests to write first:
- `summary` round-trips to the same JSON value as `summary.json`; key is stable across attempts and changes with `summary.json`.
- 200/202/204 succeed; 401/404/413 fail without retry; 429 with `Retry-After` and 503 retry, then succeed.
- 302 is refused and the second host is never contacted.
- Token header is sent; reserved headers cannot be overridden.
- Validator rejects `http://`, user-info URLs and bad header names.
- Error descriptions never contain the token or URL path.
- `authorizePayload == false` sends nothing; `both` never includes the webhook.

## Reference receiver and App Review endpoint

A small open-source Cloudflare Worker in a separate repository (not `pulsecommit-web`):
- checks the token, validates that the body is the envelope above, returns `200 {"ok": true, "bytes": N}` and discards the body;
- no storage and no logging of bodies or headers (Workers Logs and Logpush off for this Worker);
- the review token is a Worker secret, never in Git; it goes to App Review notes only;
- the same code is published as the "minimal receiver" recipe, with optional variants that store to R2 or forward to an agent.

The App Review note says the developer runs a test endpoint that accepts and immediately discards requests, so the "developer receives no data" claim stays true. Deploy only after owner approval.

## Copy that changes with 1.0.2 (not before)

The live 1.0 and 1.0.1 contact only `api.github.com`, `github.com` and `api.telegram.org`, so this copy changes in the same release, not earlier. New wording: "those three hosts, plus the webhook URL you enter; never a server of ours".

- App repo: `AGENTS.md` (host line and the "Out of scope" line that lists webhook sinks), `CONTRIBUTING.md`, `README.md`, `docs/legal/privacy-policy.md`, `docs/store/listing.md`, `PulseCommit/UI/Settings/PrivacyView.swift`, `LegalDocsTests`, `StoreListingTests`.
- Site: `index.html`, `privacy/index.html`, `test/pages.test.js`.
- Launch drafts (Show HN, Reddit).

Owner decision: the anti-positioning line "If you don't have a GitHub account or a Telegram bot, this isn't for you" needs new wording once a webhook exists.

## Release 1.0.2

- App name: Pulse Commit: Health Export.
- Webhook destination (this spec).
- AI-agent positioning on the site, README and listing, naming OpenClaw and Hermes only after a live end-to-end test with each.

## Out of scope for 1.0.2

HMAC signing, ZIP or multipart bodies, several webhooks, LAN or plain HTTP, receiver presets inside the app.
