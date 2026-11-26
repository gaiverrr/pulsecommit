# Telegram bot-to-bot

Status: not yet tested end to end.

When Pulse Commit posts to a Telegram group, it posts as a bot. For your agent (also a bot) to read that post, Telegram's Bot-to-Bot Communication Mode applies. Everything below comes from [Telegram: Bot-to-bot communication](https://core.telegram.org/api/bots/bot-to-bot) unless marked otherwise.

## Steps

1. In [@BotFather](https://t.me/BotFather), enable Bot-to-Bot Communication Mode for every bot that takes part. The docs say at least one of the two bots must have it on.
2. Put both bots in the group.
3. Choose how the receiving bot gets the message:
   - Without extra settings, a bot receives another bot's group message only if it includes a command mention for the receiving bot or directly replies to one of its messages.
   - To receive other bots' messages without a mention or reply, the receiving bot needs the mode enabled, must be an admin in the group, and must have Group Privacy Mode disabled in @BotFather.
4. Set the agent side to accept bot messages. The setting is agent specific: see [Hermes](hermes.md) and [OpenClaw](openclaw.md).
5. Private chats: the docs say both bots need the mode enabled; otherwise the call fails with `USER_BOT_TO_BOT_DISABLED`, which applies only to private chats.

## Loops

The page warns that reply loops can occur and recommends deduplication, per-chat and per-bot rate limits, depth limits and timeouts. Pulse Commit sends one message per export and does not reply to messages, but your agent might answer it. Make sure the agent's answer cannot trigger another reply loop.

## Own outgoing messages

Not verified. The expectation is that a bot does not receive the messages it sent itself, so an agent using the same bot token as Pulse Commit would never see the export. No official Telegram page found for this guide states it either way. The older [Bots FAQ](https://core.telegram.org/bots/faq) says bots cannot see other bots' messages "regardless of mode", which the bot-to-bot page above supersedes for groups. Use a separate bot token for Pulse Commit and for the agent, and test it.
