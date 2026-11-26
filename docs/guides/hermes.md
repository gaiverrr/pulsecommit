# Hermes Agent

Status: not yet tested end to end.

Hermes Agent is by Nous Research: [webhooks](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/webhooks), [Telegram](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/telegram). Two setups: a webhook route that turns the daily summary into an agent prompt, and a Telegram group.

The webhook destination ships in Pulse Commit 1.0.2 (see [the spec](../specs/2026-11-26-webhook-destination.md)). The payload field `summary_markdown` is the text of `summary.md`.

## A. Webhook route

Source: [Hermes webhooks](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/webhooks).

1. Enable the webhook platform with `hermes gateway setup`, or set in `~/.hermes/.env`: `WEBHOOK_ENABLED=true`, `WEBHOOK_PORT=8644` (the default) and `WEBHOOK_SECRET=<secret>`.
2. Check it runs: `curl http://localhost:8644/health` returns `{"status": "ok", "platform": "webhook"}` per the docs.
3. Define a route in `config.yaml` under `platforms.webhook.extra.routes`. Use the `gitlab` pin, which compares a plain secret in the `X-Gitlab-Token` header (not an HMAC), so the app can send it as its token header:

   ```yaml
   platforms:
     webhook:
       enabled: true
       extra:
         port: 8644
         routes:
           pulse-commit:
             secret: "<long-random-secret>"
             signature: gitlab
             prompt: "Apple Health export for {date}:\n\n{summary_markdown}"
             deliver: "telegram"
   ```

   `signature` accepts `generic`, `github`, `gitlab` and `linear`. Every route needs a secret, on the route or global; otherwise the adapter fails at startup. In prompts, `{field}` reads from the payload with dot notation, and a missing key stays as the literal `{key}`. Nested values are truncated at 2000 characters, so use the top-level `summary_markdown`. The route above is assembled from documented keys, not copied from a documented example.
4. Route URL: `http://<server>:8644/webhooks/pulse-commit`. Pulse Commit needs an HTTPS URL with a publicly trusted certificate ([spec, Transport](../specs/2026-11-26-webhook-destination.md)); how you expose the server is up to you and not covered here.
5. In Pulse Commit, Destinations, Webhook: enter the URL, set the header name to `X-Gitlab-Token` and the token to the route secret.
6. Delivery: with `deliver: "telegram"` and no `chat_id`, delivery goes to the platform's home channel. To pick a chat or forum topic, set `chat_id` (and optionally `message_thread_id`) in `deliver_extra`.
7. Press Send test in the app. The test body has `event_type: "test"` and no Health data.

Routes also support `events` and `filters`. The docs example uses `events` with GitHub-style event names; this guide does not use it.

## B. Telegram group

Source: [Hermes Telegram](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/telegram).

1. Message @BotFather, send `/newbot`, and copy the token.
2. In `~/.hermes/.env`: `TELEGRAM_BOT_TOKEN=<token>` and `TELEGRAM_ALLOWED_USERS=<numeric user IDs, comma-separated>`. Or run `hermes gateway setup` and pick Telegram. Start with `hermes gateway`.
3. Privacy mode is on by default: the bot sees only `/` commands, replies to its own messages, service messages and messages in channels where it is an admin. To turn it off: @BotFather, `/mybots`, your bot, Bot Settings, Group Privacy, Turn off, then remove and re-add the bot to the group. Promoting the bot to group admin is the alternative.
4. `telegram.require_mention: true` in `config.yaml` makes the bot answer in groups only to replies, `@botusername` mentions, `/command@botusername` and `mention_patterns` matches. Unset or false, it answers every group message it can see.
5. Messages from other bots: the docs list the environment variable `TELEGRAM_ALLOW_BOTS` with values `mentions` or `all`, and `bots_require_mention: true` (env `TELEGRAM_BOTS_REQUIRE_MENTION`) so another bot's message counts only if it mentions this bot. The docs text read for this guide shows no `config.yaml` key `telegram.allow_bots` and no default, so this guide does not claim one.

For the Telegram side of a bot-to-bot setup, read [telegram-bot-to-bot.md](telegram-bot-to-bot.md).
