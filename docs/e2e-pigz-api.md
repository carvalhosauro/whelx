# Rodando a pigz-api contra o whelx

Roteiro para validar ponta a ponta o **bot de pedidos** e o **disparo de campanhas** sem tocar na Meta.

## 1. Pré-requisitos

- pigz-api com o patch `feat/meta-graph-base-url` (o `MetaWhatsappApiClient` lê `META_GRAPH_BASE_URL`).
- whelx rodando e alcançável pela pigz-api:
  - pigz-api em Docker: rode o whelx no mesmo compose (`http://whelx:4000`) ou no host com `BIND_IP=0.0.0.0` e use `http://host.docker.internal:4000`.
  - O `WHELX_PUBLIC_URL` precisa ser a URL que **a pigz-api** usa para chegar no whelx, porque é a base das URLs de mídia que ela baixa.

## 2. Cenário no whelx

```bash
curl -s -X POST $WHELX/_whelx/seed -H 'content-type: application/json' -d '{
  "app": {"webhook_url": "http://pigz-api/api/webhook/whatsapp"},
  "wabas": [{"id": "200000000000001", "name": "Loja Teste", "subscribed": true,
             "phone_numbers": [{"id": "300000000000001", "display_phone_number": "+55 11 4000-1234", "verified_name": "Loja Teste"}]}],
  "tokens": [{"token": "EAApigzlocal", "wabas": "all"}],
  "settings": {"template_approval_policy": "manual"}
}'
curl -s -X POST $WHELX/_whelx/webhooks/verify   # espera {"ok": true}
```

Copie o bloco `.env` da tela **Config** (ou da tool MCP `env_block`) para o `.env.local` da pigz-api e reinicie os consumers (`whatsapp_webhook`, `whatsapp_outbound`, `whatsapp_batch`, `whatsapp_ai_turn`).

## 3. Conectar a loja

No painel da pigz-api, use a conexão manual com:
- WABA ID `200000000000001`
- phone number ID `300000000000001`
- token `EAApigzlocal`

A pigz-api chama `GET /{waba}` e `POST /{waba}/subscribed_apps`. As duas chamadas aparecem em **Logs**.

## 4. Bot de pedidos

1. Ligue a IA na linha da loja, no painel da pigz-api.
2. No whelx, em **Chat**, escolha o contato e mande "oi, quero uma pizza".
3. O esperado:
   - webhook `messages` entregue com 200 (Logs → Webhooks)
   - read receipt com `typing_indicator` ("digitando…" aparece no chat)
   - resposta do bot: texto, lista ou botões
4. Toque nas opções. Cada clique gera `button_reply` ou `list_reply` com `context.id`.
5. Grave um áudio pelo microfone. A pigz-api baixa via `GET /{media_id}` e transcreve.
6. Ao fechar o pedido chega um `order_details` com o card do pedido e "Copiar código Pix".

Para dirigir sem UI:

```bash
curl -s -X POST $WHELX/_whelx/contacts/5511988887777/messages -H 'content-type: application/json' \
  -d '{"type":"text","text":"oi","phone_number_id":"300000000000001"}'
curl -s -X POST $WHELX/_whelx/wait -H 'content-type: application/json' \
  -d '{"kind":"outbound_message","contact":"5511988887777","timeout_ms":30000}'
```

## 5. Campanhas

1. Gere público: `POST /_whelx/contacts/bulk {"count": 500}`. Garanta que esses números existam como clientes da loja na pigz-api.
2. Crie o template pelo painel da pigz-api. Ele chega como `PENDING` em **Templates**.
3. Aprove no whelx.
4. Dispare a campanha pela pigz-api.
5. Acompanhe em **Campanhas**:
   - taxa perto de `WHATSAPP_RATE_LIMIT_PER_SECOND` (75)
   - status evoluindo para delivered
   - `130429` se passar de 80 msg/s por número

## 6. Caos

Aplique o preset `flaky` (ou `hostile`) em **Caos** e repita os passos 4 e 5. A pigz-api precisa lidar com:
- `130429` e `131000` síncronos
- status `failed` (`131026`, `131049`)
- webhooks duplicados (dedup por `waba_message_id`)
- webhooks perdidos
- status fora de ordem (`sent` depois de `read`)

Com a mesma seed, os resultados se repetem.

## 7. Checklist rápido

- `python3 scripts/smoke.py --base $WHELX` passa (48 checks) com o whelx isolado.
- Logs → Graph API sem linhas vermelhas ("erro interno").
- Logs → Webhooks sem `retrying` ou `failed`, a não ser que o caos esteja ligado.
