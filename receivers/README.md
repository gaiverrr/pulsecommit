# Webhook receivers

The reference Cloudflare Worker for the Webhook destination lives in its own public repository: https://github.com/gaiverrr/pulsecommit-webhook-receiver

It has two Wrangler environments:

- `review` - checks the token and the body, answers 200 and discards the body. Used as the App Review endpoint.
- `inbox` - same checks, then keeps the latest 50 requests in Workers KV for 7 days, with a viewer page protected by a separate view token. For testing your own deliveries; it stores Health data in your Cloudflare account.

Deploy steps, the request format it accepts and curl examples are in that repository's README.
