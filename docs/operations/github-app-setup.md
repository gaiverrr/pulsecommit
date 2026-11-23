# GitHub App setup — Pulse Commit

One-shot runbook to register the `Pulse Commit` GitHub App under a new `pulse-commit` GitHub Organization. Total time: ~10 minutes.

## Prerequisites

- A GitHub account with org-creation rights (any personal account qualifies).
- You are signed in to github.com in your default browser.
- Free plan is fine — no paid features required.

## Step 1 — Create the Organization

1. Open <https://github.com/account/organizations/new>.
2. Pick **Free** plan.
3. Organization name: `pulse-commit`.
   - Names are globally unique. If `pulse-commit` is taken, GitHub will tell you immediately. Fallbacks, in order: `pulsecommit-app`, `pulse-commit-os`.
   - Whatever name you end up with, remember it — you will use it in Step 2.
4. Contact email: your own. Belongs to: **My personal account**.
5. Skip the "invite members" and "tell us about your org" screens (click Skip / Submit).

You should now land on `https://github.com/pulse-commit` (or your fallback).

## Step 2 — Open the manifest installer

1. In Finder, open `scripts/register-github-app.html` (or run `open scripts/register-github-app.html` from the repo root).
2. If you used a fallback org name in Step 1, change the **Organization** input on the page to match — the form action updates live.
3. Review the manifest JSON shown on the page. It requests:
   - Repository **Contents: read/write** and **Metadata: read**.
   - No webhooks, no account permissions, no install-time OAuth.
4. Click **Create GitHub App**. The browser submits the manifest to GitHub.
5. GitHub will show a confirmation screen — click **Create GitHub App for pulse-commit**.
6. After creation GitHub redirects to the `redirect_url` (`https://pulsecommit.app/auth/redirect`). That page may not load — **that's expected and harmless**. The App has been created.

## Step 3 — Capture the Client ID

1. Open `https://github.com/organizations/pulse-commit/settings/apps/pulse-commit` (substitute your org name if it differs).
2. Under **About**, copy the **Client ID** (starts with `Iv23` or similar).
3. The manifest does **not** enable Device Flow (no manifest field exists for it). On the same settings page:
   - Scroll to **Identifying and authorizing users**.
   - Check **Enable Device Flow**.
   - Click **Save changes**.
4. Confirm permissions under the **Permissions & events** tab:
   - Repository → Contents: **Read and write**.
   - Repository → Metadata: **Read-only**.
   - No account permissions, no subscribed events.

For Device Flow, only the Client ID is needed — no Client Secret, no private key.

## Step 4 — Upload App icon

1. Same settings page → **Display information** → **Upload a logo**.
2. Asset must be **1024×1024** PNG.
3. **TODO** — design the icon. Hint from the design brief: lime square background with a black `>` glyph. Drop the final PNG into `design_handoff_pulse_commit/screenshots/` as `app-icon-1024.png`.
4. Non-blocking: development can proceed without an icon. GitHub uses a default Octocat-style placeholder.

## Step 5 — Record the Client ID

1. Open `docs/operations/github-app-config.md`.
2. Replace `_to be filled after registration_` with the Client ID from Step 3.
3. If you used a fallback org name, also update the **Owner** row.
4. Commit the change. **Do not commit any secret** — the Client ID is public; there are no secrets for Device Flow apps.

Done. The App is live and ready for the iOS client to start OAuth Device Flow against it.
