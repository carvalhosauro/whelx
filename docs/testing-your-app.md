# Testing your app against whelx

A step-by-step for running a real WhatsApp Cloud API app (a bot, a campaign sender, a support inbox) end to end against whelx, without touching Meta.

## 1. Make the Graph API base URL configurable

Most Cloud API clients hardcode `https://graph.facebook.com`. Read it from configuration instead, falling back to Meta's host:

```
GRAPH_API_BASE_URL=http://localhost:4000   # whelx
GRAPH_API_VERSION=v25.0                    # any vNN.N works
```

That is the only code change whelx needs. Everything else (paths, payloads, auth headers, webhook signatures) stays as it is in production.

## 2. Run whelx where your app can reach it

- App on your machine: `docker run -p 4000:4000 ghcr.io/carvalhosauro/whelx`.
- App in Docker Compose: add whelx as a service and use `http://whelx:4000`.

```yaml
services:
  whelx:
    image: ghcr.io/carvalhosauro/whelx
    ports: ["4000:4000"]
    environment:
      WHELX_PUBLIC_URL: http://whelx:4000
    volumes: ["whelx-data:/data"]
volumes:
  whelx-data:
```

`WHELX_PUBLIC_URL` must be the address **your app** uses to reach whelx. Media URLs returned by `GET /{media_id}` are built from it.

## 3. Create the scenario

```bash
curl -s -X POST localhost:4000/_whelx/seed -H 'content-type: application/json' -d '{
  "app":    {"webhook_url": "http://myapp:8000/webhooks/whatsapp"},
  "wabas":  [{"id": "200000000000001", "name": "Test Store", "subscribed": true,
              "phone_numbers": [{"id": "300000000000001", "display_phone_number": "+1 555 000 1234", "verified_name": "Test Store"}]}],
  "tokens": [{"token": "EAAlocaltesttoken", "wabas": "all"}],
  "templates": [{"waba_id": "200000000000001", "name": "order_update", "language": "en_US", "category": "UTILITY",
                 "components": [{"type": "BODY", "text": "Hi {{1}}, your order {{2}} is on its way."}]}]
}'
curl -s -X POST localhost:4000/_whelx/webhooks/verify   # {"ok": true} means your verify token matches
```

Copy the `.env` block from the **Config** page (or the MCP tool `env_block`) into your app's environment: base URL, app secret, verify token, access token, WABA id and phone number id.

## 4. Conversational flows (bots, support)

1. In the **Chat** page, pick a contact and send "hi".
2. Expect in **Logs**:
   - the `messages` webhook delivered with HTTP 200 and a valid `X-Hub-Signature-256`
   - your read receipt, with `typing_indicator` showing "typing…" in the chat
   - your reply: text, buttons, lists, CTA URL or `order_details`
3. Tap buttons and list rows. Each tap sends `button_reply` / `list_reply` with `context.id`, exactly like a phone would.
4. Record a voice note with the mic button. Your app downloads it through `GET /{media_id}` plus the media URL.

Headless, for CI or a coding agent:

```bash
curl -s -X POST localhost:4000/_whelx/contacts/15550001111/messages -H 'content-type: application/json' \
  -d '{"type":"text","text":"hi","phone_number_id":"300000000000001"}'
curl -s -X POST localhost:4000/_whelx/wait -H 'content-type: application/json' \
  -d '{"kind":"outbound_message","contact":"15550001111","timeout_ms":30000}'
```

## 5. Campaigns (templates at volume)

1. Generate an audience: `POST /_whelx/contacts/bulk {"count": 500}`.
2. Create the template from your app (`POST /{waba}/message_templates`). It arrives as `PENDING` on the **Templates** page. Approve it there, or set the policy to auto-approve.
3. Fire the campaign from your app.
4. Watch the **Campaigns** page: throughput in msg/s, status progression (sent → delivered → read) and `130429` responses once a number exceeds its throughput (80 msg/s by default).

## 6. Break things on purpose

Turn on the `flaky` or `hostile` preset on the **Chaos** page, or scope chaos to one number with `phone_number_ids`, and run the flows again. Your app should survive:

- synchronous `130429`, `131000` and 5xx responses
- `failed` statuses (`131026`, `131049`)
- duplicated webhooks (dedupe by message id)
- dropped webhooks
- statuses out of order (`sent` after `read`)
- pair rate limit `131056` (Config → pair rate limit)

The same seed reproduces the same number of injected failures.

## Checklist

- `python3 scripts/smoke.py --base http://localhost:4000` passes against a fresh whelx. It resets data, so don't point it at an instance someone else is using.
- **Logs → Graph API** has no red rows ("internal error").
- **Logs → Webhooks** has no `retrying` or `failed` rows unless chaos is on.
