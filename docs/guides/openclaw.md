# OpenClaw

Status: not yet tested end to end.

OpenClaw is a self-hosted agent gateway: [repository](https://github.com/openclaw/openclaw), [docs](https://docs.openclaw.ai). Two setups: a webhook route that feeds the daily summary to the agent, and a Telegram group where the agent chats.

The webhook destination ships in Pulse Commit 1.0.2 (see [the spec](../specs/2026-11-26-webhook-destination.md)). The payload field `summary_markdown` is the text of `summary.md`.

## A. Webhook route

Sources: [Inbound webhooks](https://docs.openclaw.ai/automation/cron-jobs/webhooks), [Hooks config reference](https://docs.openclaw.ai/gateway/config-hooks).

1. Create a token used only for hooks. The docs say to use "a token dedicated to hooks, not the Gateway auth token or password".
2. Enable hooks in the OpenClaw config. Hooks are off by default. Add a mapping for the path `pulse-commit`:

   ```json5
   {
     hooks: {
       enabled: true,
       token: "<long-random-hook-token>",
       path: "/hooks",
       mappings: [
         {
           id: "pulse-commit",
           match: { path: "pulse-commit" },
           action: "agent",
           name: "Pulse Commit",
           messageTemplate: "Apple Health export:\n\n{{payload.summary_markdown}}",
         },
       ],
     },
   }
   ```

   `enabled`, `token`, `path`, `mappings`, `match.path`, `action`, `name` and `messageTemplate` are documented keys. Templates use `{{payload.field}}`, and `messageTemplate` must render non-empty. Custom mappings run before presets and the first match wins. The mapping above is assembled from the documented field list, not copied from a documented example.
3. The hook URL is `<your gateway address>/hooks/pulse-commit`. In Pulse Commit, open Destinations, Webhook, and enter that URL.
4. Put the same token in the app. OpenClaw accepts `Authorization: Bearer <token>` (recommended) or `x-openclaw-token: <token>`. The query string `?token=...` is rejected. The app sends the Bearer header by default.
5. The URL must be HTTPS with a publicly trusted certificate, because the app refuses plain HTTP and local network hosts ([spec, Transport](../specs/2026-11-26-webhook-destination.md)). How you expose the gateway (reverse proxy, tunnel) is up to you and not covered here.
6. Body limit: the docs state the normal body limit is 1 MiB with a 30-second body-read timeout; larger bodies return `413`. The webhook payload omits raw samples to stay under it.
7. Press Send test in the app. A `200` means accepted (for agent actions this is admission, not completion). `401` means a wrong token or a proxy that drops the auth header. `404` means hooks disabled, wrong path or no matching mapping.

Sending the agent's reply to Telegram: the mapping keys `deliver`, `channel` and `to` are documented (direct channel delivery needs both `channel` and `to`; `channel: "last"` with a partial destination returns `400`). The exact `channel` value for Telegram and the `to` format for a group are not verified here. Check the [config reference](https://docs.openclaw.ai/gateway/config-hooks) before using them.

## B. Telegram group

Sources: [Telegram setup](https://docs.openclaw.ai/channels/telegram/setup), [access control](https://docs.openclaw.ai/channels/telegram/access-control).

1. Create a bot with @BotFather and copy the token.
2. Configure the channel:

   ```json5
   {
     channels: {
       telegram: {
         enabled: true,
         botToken: "<bot-token>",
         dmPolicy: "pairing",
         groups: { "*": { requireMention: true } },
       },
     },
   }
   ```

   The docs also show `openclaw channels add --channel telegram --token <bot-token>`.
3. Add the bot to your group. Group policy defaults to `allowlist`, so all groups are blocked until you add `groups` entries (explicit chat IDs or `"*"`).
4. Group chat IDs go under `channels.telegram.groups`, not in `groupAllowFrom`. `groupAllowFrom` takes numeric user IDs and filters who in the group can talk to the bot.
5. Mentions: group replies require a mention by default. Plain group messages do not trigger the bot while `requireMention: true`.
6. To react to messages without a mention, set `requireMention: false` for that group and make sure Telegram delivers ordinary group messages: turn off privacy mode in @BotFather or make the bot a group admin. After changing privacy mode, remove and re-add the bot to the group.
7. To find the group chat ID, the docs suggest forwarding a group message to `@userinfobot` or `@getidsbot`, reading `getUpdates`, or running `/whoami@<bot_username>` once the group is allowed.

Pulse Commit sends to Telegram as a bot too. For a bot-to-bot setup, read [telegram-bot-to-bot.md](telegram-bot-to-bot.md). OpenClaw's own setting for accepting messages from other bots is not covered by the pages above and is not documented here.
