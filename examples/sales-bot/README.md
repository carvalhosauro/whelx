# Luigi's Pizza: an example sales bot

A tiny WhatsApp sales bot (Python, standard library only) to try whelx end to end. It is a regular Cloud API app: it verifies the webhook signature and answers through the Graph API. Only `GRAPH_API_BASE_URL` points at whelx.

**Funnel:** greeting → pizza menu (list) → drink upsell (buttons) → confirmation (buttons) → Pix order (`order_details`).

It ships with **one deliberate bug**. Let your coding agent find it before you read `bot.py`.

## Run it

```bash
# 1. whelx
docker run -p 4000:4000 ghcr.io/carvalhosauro/whelx

# 2. the scenario (business number, token, app secret, webhook → the bot)
curl -X POST localhost:4000/_whelx/seed -H 'content-type: application/json' \
  -d @examples/sales-bot/seed.json

# 3. the bot
python3 examples/sales-bot/bot.py
```

Open http://localhost:4000, pick Maya and say hi.

If whelx runs in Docker without host networking, set the seed's `webhook_url` to an address the container can reach (e.g. `http://host.docker.internal:8801/webhook`).

## Let your agent be the customer

```bash
claude mcp add --transport http whelx http://localhost:4000/_whelx/mcp
```

Then ask:

> Use the whelx MCP to test the Luigi's Pizza bot as three customers: one who buys a pizza with a drink, one who asks a question in the middle of the order, and one who gives up at the upsell. Wait for the bot's reply after every message and tell me where the funnel breaks.

The agent sends messages with `send_as_contact`, taps options with `reply_interactive` and waits for the bot with `wait_for`. You can watch the conversations happen live in the chat UI.

## Configuration

| Variable | Default |
|---|---|
| `GRAPH_API_BASE_URL` | `http://localhost:4000` |
| `GRAPH_API_VERSION` | `v25.0` |
| `WHATSAPP_ACCESS_TOKEN` | `EAAsalesbotdemotoken` |
| `WHATSAPP_PHONE_NUMBER_ID` | `300000000000001` |
| `META_APP_SECRET` | `0123456789abcdef0123456789abcdef` |
| `WEBHOOK_VERIFY_TOKEN` | `sales-bot-verify` |
| `PORT` | `8801` |

The defaults match `seed.json`.
