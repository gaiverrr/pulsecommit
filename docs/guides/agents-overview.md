# Connect Pulse Commit to an AI agent

Status: not yet tested end to end.

Pulse Commit has no AI service and no backend. It sends your Health export to destinations you own, and your agent reads it from there. There are three ways in.

| Way in | The agent gets | Use it when |
|---|---|---|
| Telegram chat | The daily message text and a ZIP of the JSON files, in a chat the agent is part of | The agent already lives in Telegram and you want the day in the conversation |
| GitHub repo | One commit per day with `summary.json`, `summary.md`, samples, workouts and routes | The agent can read a repository and you want history, raw samples and routes |
| Webhook | One JSON `POST` per day with the summary and a file manifest | The agent has an HTTP endpoint (OpenClaw, Hermes) and you want it to react right away |

The webhook destination is specified in [the webhook spec](../specs/2026-11-26-webhook-destination.md) for release 1.0.2. Until it ships in the app, use Telegram or GitHub. The webhook payload carries `summary` and `summary_markdown` only; raw samples, workouts and GPX stay in GitHub exports.

## Which one

- Want the agent to answer in a chat when the export lands: Telegram, or webhook with delivery to Telegram.
- Want long-term analysis over weeks of raw data: GitHub. See [the SKILL.md for reading the repo](skills/pulse-commit-health/SKILL.md).
- Want a trigger with no chat in between: webhook.
- You can enable several destinations. Each one receives the export independently.

## Guides

- [OpenClaw](openclaw.md)
- [Hermes Agent](hermes.md)
- [Telegram bot-to-bot](telegram-bot-to-bot.md)
- [SKILL.md: read the GitHub export](skills/pulse-commit-health/SKILL.md)

## Privacy

Whoever runs the receiving agent can read what it receives. Pulse Commit cannot delete data after it is sent. Check where the agent sends your data before you connect it.
