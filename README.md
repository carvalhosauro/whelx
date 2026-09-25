# whelx

Emulador local da **WhatsApp Cloud API** (Graph API da Meta). Ele está para a Meta como o LocalStack/floci está para a AWS: a pigz-api aponta a base URL da Graph para o whelx e roda o fluxo inteiro (bot de pedidos, templates, campanhas, mídia, webhooks) sem tocar na Meta.

- **Graph API fake** em `/vNN.N/...`: envio de mensagens, templates, mídia, upload resumable, contas. As respostas e os erros seguem o formato da Meta.
- **Webhooks assinados** (`X-Hub-Signature-256`) para a URL configurada, com retry e log.
- **UI estilo WhatsApp Web**: você é o cliente. Manda texto, áudio, localização, clica em botões e listas, vê o pedido Pix.
- **API de controle** (`/_whelx/*`) e **MCP** (`/_whelx/mcp`) para testes automatizados e para o Claude dirigir o fluxo.
- **Caos determinístico**: latência, erros síncronos (`130429`, `131000`, 5xx), falhas assíncronas, webhooks perdidos, duplicados, reordenados ou agrupados, tudo por seed.

## Subindo

### Docker (uso diário)

```bash
docker build -t whelx .
docker run -d --name whelx -p 4000:4000 -v whelx-data:/data \
  -e WHELX_PUBLIC_URL=http://localhost:4000 whelx
```

Abra http://localhost:4000. Os dados (SQLite e mídia) ficam no volume `/data`, e as migrations rodam no boot.

### Desenvolvimento

```bash
mix setup
mix phx.server
```

Por padrão faz bind em `127.0.0.1:4000`. Use `BIND_IP=0.0.0.0` para aceitar conexões vindas de containers.

### Variáveis

| Variável | Padrão | Uso |
|---|---|---|
| `PORT` | `4000` | porta HTTP |
| `BIND_IP` | `127.0.0.1` (dev) / `0.0.0.0` (Docker) | interface |
| `WHELX_PUBLIC_URL` | `http://localhost:$PORT` | base das URLs de mídia e de paginação; precisa ser alcançável pela pigz-api |
| `DATA_DIR` | `./data` (dev) / `/data` (Docker) | SQLite e arquivos de mídia |
| `SECRET_KEY_BASE` | aleatório por boot | só assina sessões do LiveView |

## Ligando a pigz-api

1. **Patch de base URL.** O `MetaWhatsappApiClient` precisa ler `META_GRAPH_BASE_URL`. Hoje o host `graph.facebook.com` está hardcoded. O patch fica na branch `feat/meta-graph-base-url` da pigz-api.
2. **Variáveis.** Em **Config** no whelx, copie o bloco `.env`:

   ```
   META_APP_ID=...
   META_APP_SECRET=...
   META_GRAPH_BASE_URL=http://whelx:4000
   META_GRAPH_API_VERSION=v25.0
   WHATSAPP_WEBHOOK_VERIFY_TOKEN=...
   ```

3. **Webhook.** Ainda em Config, preencha a *Webhook URL* com a rota da pigz-api (ex.: `http://pigz-api/api/webhook/whatsapp`) e clique em **Verificar webhook**.
4. **Conexão do número.** No painel da pigz-api use a conexão manual com o WABA ID, o phone number ID e um token `EAA…` gerado em Config.

Snippet para o `docker-compose.yml` da pigz-api:

```yaml
  whelx:
    image: whelx
    ports: ["4000:4000"]
    environment:
      WHELX_PUBLIC_URL: http://whelx:4000
    volumes: ["whelx-data:/data"]
```

## API de controle (`/_whelx`)

| Rota | O que faz |
|---|---|
| `POST /seed` | cenário declarativo e idempotente (`app`, `wabas[].phone_numbers`, `tokens`, `contacts`, `templates`, `settings`, `chaos`) |
| `POST /reset?keep=contacts,templates` | apaga dados de teste e mantém a configuração |
| `GET`/`PUT /config` | configuração (app, settings) |
| `POST /tokens` | gera token `EAA…` |
| `GET`/`PUT /chaos` | perfil de caos (`{"preset":"flaky"}` ou campos) |
| `/contacts`, `POST /contacts/bulk` | contatos fake |
| `POST /contacts/:wa_id/messages` | o contato manda `text`, `location`, `reaction`, `image`/`audio`/`document` (base64) |
| `POST /contacts/:wa_id/reply-interactive` | clica num botão, linha de lista ou quick reply (`{wamid, id}`) |
| `GET /messages` | filtros: `contact`, `direction`, `type`, `status`, `phone_number_id` |
| `GET /conversations/:id`, `POST .../open`, `POST .../expire-window` | conversa, leitura e janela de 24h |
| `GET /templates`, `POST /templates/:id/approve`, `POST /templates/:id/reject` | revisão de templates |
| `GET /webhooks/deliveries`, `POST /webhooks/deliveries/:id/redeliver`, `POST /webhooks/verify` | webhooks |
| `GET /requests` | log da Graph API (token mascarado) |
| `POST /wait` | long-poll até a resposta do bot, um status ou uma entrega (`kind`: `outbound_message`, `status`, `webhook_delivery`) |

Exemplo: o cliente manda "oi" e o teste espera a resposta do bot.

```bash
curl -s -X POST localhost:4000/_whelx/contacts/5511988887777/messages \
  -H 'content-type: application/json' -d '{"type":"text","text":"oi"}'
curl -s -X POST localhost:4000/_whelx/wait -H 'content-type: application/json' \
  -d '{"kind":"outbound_message","contact":"5511988887777","timeout_ms":30000}'
```

## MCP (Claude)

```bash
claude mcp add --transport http whelx http://localhost:4000/_whelx/mcp
```

Tools: `seed`, `reset`, `get_config`, `env_block`, `send_as_contact`, `reply_interactive`, `wait_for`, `list_messages`, `list_contacts`, `set_contact`, `bulk_contacts`, `list_templates`, `approve_template`, `reject_template`, `set_chaos`, `list_webhook_deliveries`, `redeliver_webhook`, `verify_webhook`, `expire_window`.

## Fidelidade com a Meta

- Sucesso é sempre HTTP 200 com `messages[0].id` (`wamid.…`). `message_status: accepted` só aparece em envios de template.
- Erros no formato `{"error": {message, type, code, error_subcode, error_user_msg, error_data, fbtrace_id}}`.
- Janela de 24h: texto ou interactive fora da janela recebe 200 e depois um webhook `failed` com `131047`, como a Meta faz.
- Template inexistente ou não aprovado dá `132001`. Parâmetros divergentes dão `132000`. Throughput por número (80 msg/s por padrão) dá `130429`.
- Status `sent → delivered → read` com o shape v24+ (sem `conversation`, `pricing` PMP) e `errors[].href` nos `failed`.
- `order_details` é validado com as regras da Meta: soma dos itens igual ao subtotal, total igual a subtotal + tax + shipping − discount, `reference_id`, `retailer_id` e chave Pix.
- Qualquer tipo que o whelx ainda não suporta devolve `100` com `whelx: não suportado`, em vez de sucesso silencioso.

## Testes

```bash
mix test                                           # suíte ExUnit
python3 scripts/smoke.py --base http://localhost:4000   # E2E contra uma instância rodando, fingindo ser a pigz-api
```

## Segurança

UI e API de controle **não têm autenticação** e a tela de Config mostra o app secret. Rode só localmente e não exponha a porta.
