# whelx — núcleo (sub-projeto 1): design

- **Data:** 2026-09-24
- **Status:** aprovado em conversa, aguardando revisão da spec escrita
- **Escopo deste documento:** sub-projeto 1 (mensagens + webhooks + templates + mídia)

## 1. Contexto e objetivo

A pigz-api integra com a WhatsApp Cloud API da Meta (Graph API) para o livechat, o bot de pedidos com IA,
templates e campanhas. Testar essa integração hoje exige um app real na Meta, números reais e tokens reais;
criar um app de teste é trabalhoso e não há ambiente isolado.

**whelx** é um emulador local da Graph API do WhatsApp, no espírito do floci/LocalStack para AWS:

- a pigz-api aponta a base URL da Graph para o whelx e funciona sem saber que não está falando com a Meta;
- o whelx simula clientes do WhatsApp (contatos fake) por uma UI estilo WhatsApp Web;
- o whelx entrega webhooks assinados de volta para a pigz-api;
- o Claude conduz tudo por uma API REST de controle e por MCP, sem precisar da UI.

**Prioridades de teste ponta a ponta:**

1. Bot de pedidos (IA): conversa, botões/listas, pedido Pix (`order_details`), áudio transcrito.
2. Disparo de campanhas: templates, aprovação, envio em volume, status de entrega.

**Decisões tomadas na conversa:**

| Tema | Decisão |
|---|---|
| Escopo v1 | Mensagens texto/interactive + webhooks + templates + mídia |
| Realismo | Caminho feliz + falhas controladas + modo caos probabilístico com seed |
| Execução | `mix phx.server` para desenvolver o whelx + imagem Docker para uso diário |
| Controle | REST `/_whelx/*` como base + MCP fino por cima |
| Persistência | SQLite; `reset` zera dados de teste e preserva configuração |
| Arquitetura | Monolito Phoenix com contexts; validação de payload com schemas escritos à mão para o subset usado |

## 2. Contrato de referência (extraído da pigz-api)

Fonte: leitura de `pigz-api` (worktree `01-dev`) e do doc "WhatsApp ↔ Meta na pigz-api". Fatos que o
whelx precisa respeitar:

- Sucesso de envio = **HTTP 200 exato** + `messages[0].id` presente. Nada de 201.
- A pigz-api só inspeciona status HTTP e presença de `error`; não olha `error.code`. Mesmo assim o whelx
  devolve o shape real completo (`message`, `type`, `code`, `error_subcode`, `error_user_title`,
  `error_user_msg`, `fbtrace_id`) para permitir evolução na v2.
- Token de onboarding precisa começar com `EAA`.
- `GET /{waba}/phone_numbers` recebe `access_token` na query; demais chamadas usam `Authorization: Bearer`.
- Upload resumable: `POST /{app_id}/uploads` com `file_name`, `file_length`, `file_type`, `access_token`
  na query → `{"id":"upload:XXX"}`; depois `POST /upload:XXX` com `Authorization: OAuth <token>`,
  `file_offset: 0` e corpo binário → `{"h":"..."}`.
- Download de mídia: `GET /{media_id}` (Bearer) → `url`, `mime_type`, `file_name`; depois `GET <url>` com o
  mesmo Bearer. Sem restrição de host.
- Templates: status lido só pelo `GET /{waba}/message_templates` (primeira página, `limit=100`,
  `fields=name,status,category,language,components`). Nenhum webhook de status de template é consumido.
  A única comparação literal é `APPROVED`; `PENDING` é o default quando o create não devolve status.
- Interactive enviados: `order_details` (Pix, `payment_type: br`, `pix_dynamic_code`) e `cta_url`
  montados em PHP; `button` e `list` chegam por pass-through do orquestrador de IA.
- Read receipt + typing: `{"messaging_product":"whatsapp","status":"read","message_id":"..",
  "typing_indicator":{"type":"text"}}`, timeout de 2s no cliente.
- Webhook: `GET` com `hub.mode`, `hub.verify_token`, `hub.challenge`; `POST` com
  `X-Hub-Signature-256: sha256=<hex HMAC-SHA256 do corpo bruto com app secret>`.
- Webhook `statuses`: a pigz-api lê só `id`, `status`, `errors` (`errors[0].title` / `.message`).
- Webhook `messages`: lê `metadata.phone_number_id`, `contacts[].wa_id`/`profile.name` e, por mensagem,
  `id`, `from`, `type`, `timestamp`, `context.id` e o corpo do tipo (`text.body`, `{media}.id/mime_type/
  caption/filename`, `interactive.button_reply|list_reply`, `button.text|payload`, `location.*`,
  `reaction.emoji|message_id`).
- Versão da Graph: `v25.0` no cliente principal; o whelx aceita qualquer `vNN.N`.

**Bloqueio conhecido:** `MetaWhatsappApiClient.php:32` tem o host `https://graph.facebook.com` hardcoded.
Ver seção 10.

## 3. Arquitetura

Processo único Phoenix 1.8 (Elixir 1.18 / OTP 28), SQLite via `ecto_sqlite3`, jobs via Oban com engine
Lite (SQLite), mídia em disco sob `DATA_DIR/media/`.

```
            ┌─────────── whelx (Phoenix) ───────────┐
pigz-api ──▶│ GraphRouter /v{N}/...   (Meta fake)    │
            │ ControlRouter /_whelx/... (REST)       │──▶ contexts ──▶ SQLite
Claude ────▶│ MCP /_whelx/mcp                        │        │
Pessoa ────▶│ LiveView UI                            │     Oban Lite
            └────────────────────────────────────────┘        │
pigz-api ◀── POST de webhook assinado ─────────────────────────┘
```

As três portas de entrada (Graph, controle, UI/MCP) chamam os mesmos contexts; nenhuma regra de negócio
vive em controller ou LiveView.

**Contexts:**

| Context | Responsabilidade |
|---|---|
| `Accounts` | Apps, WABAs, números, tokens, segredos, assinatura de webhook (`subscribed_apps`) |
| `Contacts` | Contatos fake, comportamento forçado, presença, política de leitura |
| `Messaging` | Conversas, mensagens de entrada/saída, janela de 24h, ciclo de status, throughput |
| `Templates` | CRUD, validação de components, política de aprovação, paginação |
| `Media` | Armazenamento de binários, sessões de upload resumable, handles |
| `Webhooks` | Montagem de payload, assinatura, entrega, retry, log, verificação |
| `Chaos` | Perfis, presets, decisões determinísticas por seed |
| `Graph.Validation` | Schemas do subset de payloads usado pela pigz-api e erros no formato da Meta |

## 4. Modelo de dados

**Configuração** (sobrevive ao reset):

| Entidade | Campos principais |
|---|---|
| `App` | `app_id`, `app_secret`, `verify_token`, `webhook_url` |
| `Waba` | `id`, `app_id`, `name`, `subscribed` |
| `PhoneNumber` | `id` (phone_number_id), `waba_id`, `display_phone_number`, `verified_name`, `quality_rating`, `throughput_mps` (padrão 80) |
| `AccessToken` | `token` (`EAA…`), WABAs com acesso, `expires_at` |
| `ChaosProfile` | `seed`, preset, percentuais por erro, faixa de latência, percentuais de reorder/duplicate/drop/batch |
| `Settings` | perfil de retry de webhook (`fast`/`realistic`), política de aprovação de template, delays d1/d2 de status |

**Dados de teste** (zerados pelo reset):

| Entidade | Campos principais |
|---|---|
| `Contact` | `wa_id`, `profile_name`, `behavior` (`normal`, `invalid_number`, `blocked`), `online`, `read_policy` (`on_open`, `auto`, `never`), `read_after_ms` |
| `Conversation` | `phone_number_id`, `contact_id`, `window_expires_at` |
| `Message` | `wamid`, `direction`, `type`, `payload` (JSON), `status`, `errors`, `context_wamid`, timestamps por status |
| `Template` | `waba_id`, `id`, `name`, `language`, `category`, `components`, `status`, `rejected_reason` |
| `Media` | `id`, `mime_type`, `file_name`, `sha256`, `file_size`, `path` |
| `UploadSession` | `id` (`upload:XXX`), `file_name`, `file_length`, `file_type`, `offset`, `handle` |
| `WebhookDelivery` | `payload`, `signature`, `attempts`, `last_status`, `last_response_body`, `latency_ms`, `chaos_tag` |
| `GraphRequestLog` | `method`, `path`, `headers` (token mascarado), `body`, `response_status`, `response_body`, `chaos_tag` |

`POST /_whelx/reset?keep=contacts,templates` preserva as entidades listadas em `keep`.

**Formatos de id:** ids numéricos de 15–16 dígitos; `wamid.HBgN…` (base64); tokens `EAA…`; sessões
`upload:<id>`; handles `h` no formato `N:<base64>`.

## 5. API Graph fake

**Roteamento:** qualquer prefixo `/vNN.N/`. Token aceito em `Authorization: Bearer`, `Authorization: OAuth`
ou `?access_token=`.

**Erros de auth:** token inválido → HTTP 401, `code: 190`, `type: OAuthException`. Token sem acesso ao
WABA/número → HTTP 403, `code: 200`.

**Endpoints do v1:**

| Endpoint | Comportamento |
|---|---|
| `GET /{waba}` (`fields=id`) | Devolve `{"id": waba}` se o token tiver acesso |
| `GET /{waba}/phone_numbers` | Lista números respeitando `fields` |
| `POST /{waba}/subscribed_apps` | Marca `subscribed = true`, devolve `{"success": true}` |
| `DELETE /{waba}/subscribed_apps` | Marca `subscribed = false`, devolve `{"success": true}` |
| `POST /{phone}/messages` | `text`, `template`, `interactive` (`order_details`, `cta_url`, `button`, `list`), `status: read` (+ `typing_indicator`) |
| `POST /{waba}/message_templates` | Cria; valida nome (`^[a-z0-9_]+$`), duplicidade nome+idioma, components; devolve `id`, `status`, `category` |
| `GET /{waba}/message_templates` | Lista com `fields`, `limit`, `name`, `status`; paginação por cursor (`paging.cursors`, `paging.next`) |
| `DELETE /{waba}/message_templates?name=` | Remove todas as línguas do nome; `{"success": true}` |
| `GET /{media_id}` | `{"messaging_product","url","mime_type","sha256","file_size","id"}` |
| `GET /_media/{id}` | Binário; exige Bearer válido |
| `POST /{app_id}/uploads` | Cria sessão resumable |
| `POST /upload:XXX` | Recebe binário com `file_offset`; devolve `{"h": ...}` quando completo |
| `GET /upload:XXX` | Devolve `{"id", "file_offset"}` |

Tipo de mensagem ou endpoint fora do suporte → erro `100` com mensagem iniciando por
`whelx: não suportado`, registrado no log. Nunca sucesso silencioso.

**Resposta de envio:**

```json
{"messaging_product":"whatsapp",
 "contacts":[{"input":"5511999999999","wa_id":"5511999999999"}],
 "messages":[{"id":"wamid.HBgN...","message_status":"accepted"}]}
```

**Regras reproduzidas:**

| Situação | Resposta síncrona | Efeito assíncrono |
|---|---|---|
| `text`/`interactive` fora da janela de 24h | 200 + wamid | status `failed`, erro `131047` |
| Template inexistente, não aprovado ou idioma inexistente | erro `132001` | — |
| Quantidade de parâmetros do template divergente | erro `132000` | — |
| Payload inválido segundo o schema | erro `100` (`error_subcode` e `error_user_msg` descritivos) | — |
| Contato com `behavior: invalid_number` | 200 + wamid | status `failed`, erro `131026` |
| Contato com `behavior: blocked` | 200 + wamid | status `failed`, erro `131031`* |
| Número de destino desconhecido | cria contato `normal` automaticamente | ciclo normal |
| Throughput do número excedido (janela de 1s) | erro `130429` (HTTP 400) | — |
| `status: read` | 200 `{"success": true}` | mensagem de entrada fica lida; UI mostra "digitando…" por até 25s ou até a próxima mensagem de saída |

\* código a confirmar contra a documentação pública da Meta durante a implementação; se não houver código
específico, usar `131026`.

**Validação de payload** (`Graph.Validation`): schemas para `text`, `template.components` (body/header/
button com `sub_type` `url`/`quick_reply`/`order_details`), `interactive.order_details` (valores em
centavos com `offset: 100`, itens, `payment_settings` com `pix_dynamic_code`), `interactive.cta_url`
(limites de 1024/20 caracteres), `interactive.button` (até 3 botões, título até 20), `interactive.list`
(até 10 linhas no total, título até 24). Limites conferidos contra a documentação pública da Meta na
implementação.

**Aprovação de template:** política global em `Settings`: `manual` (padrão), `auto_approve` após N
segundos, `auto_reject` com motivo. Aprovar/rejeitar manualmente pela UI ou pela API de controle.

## 6. Webhooks e ciclo de status

**Envelope:**

```json
{"object":"whatsapp_business_account",
 "entry":[{"id":"<waba_id>","changes":[{"field":"messages",
   "value":{"messaging_product":"whatsapp",
            "metadata":{"display_phone_number":"...","phone_number_id":"..."},
            "contacts":[{"profile":{"name":"..."},"wa_id":"..."}],
            "messages":[...]}}]}]}
```

`statuses` completos: `id`, `status`, `timestamp`, `recipient_id`, `conversation` (`id`, `origin.type`),
`pricing` (`billable`, `pricing_model`, `category`) e `errors` (`code`, `title`, `message`,
`error_data.details`) quando `failed`.

**Entrega** (fila Oban `webhooks`):

- `POST webhook_url` com `Content-Type: application/json`, `X-Hub-Signature-256: sha256=<hex>` calculado
  sobre os bytes exatos enviados, `User-Agent: facebookexternalua`.
- Sucesso = HTTP 200. Outro status ou timeout de 10s → retry com backoff:
  - `fast` (padrão): 1s, 2s, 4s, 8s, 16s, 32s, 64s, 128s (8 tentativas);
  - `realistic`: escala crescente até horas, aproximando o comportamento da Meta.
- Só entrega se o WABA estiver `subscribed`.
- Ordem por conversa preservada por padrão (sem caos).
- Toda entrega é registrada em `WebhookDelivery`; UI e API permitem reentregar.
- Verificação: `POST /_whelx/webhooks/verify` (e botão na UI) faz
  `GET webhook_url?hub.mode=subscribe&hub.verify_token=..&hub.challenge=<aleatório>` e confere o eco.

**Ciclo de status de saída:**

```
accepted ──d1──▶ sent ──d2 (só se contato online)──▶ delivered ──política de leitura──▶ read
     └──────────────── failed (regras da seção 5 ou caos) ────────────────┘
```

- `read_policy: on_open` (padrão): `read` quando a conversa é aberta na UI ou por
  `POST /_whelx/conversations/{id}/open`.
- `auto`: `read` após `read_after_ms`.
- `never`: não emite `read`.
- Contato offline acumula mensagens em `sent`; ao ficar online, emite `delivered` para todas.

**Mensagens de entrada** (UI ou `POST /_whelx/contacts/{wa_id}/messages`):

- tipos: `text`, `reaction`, `location`, `image`, `audio`, `document`; áudio pode ser gravado no navegador
  (MediaRecorder) e é armazenado como mídia servida por `GET /{media_id}`;
- clique em botão/lista de uma mensagem `interactive` → `interactive.button_reply` / `list_reply` com os
  ids originais e `context.id` apontando para a mensagem clicada;
- clique em quick reply de template → `button` com `text` e `payload`;
- `order_details` é renderizado como card do pedido com ação "Copiar código Pix"; nenhuma confirmação de
  pagamento é emitida (vem do PSP, não da Meta);
- toda mensagem de entrada renova `window_expires_at = agora + 24h`;
- `POST /_whelx/conversations/{id}/expire-window` força a janela vencida.

## 7. Caos

Perfil único ativo, com `seed`. Mesma seed + mesma sequência de operações = mesmas decisões.

| Camada | Injeções |
|---|---|
| Graph síncrona | latência (faixa em ms); erros `130429`, `131000`, HTTP 500, HTTP 503 por percentual |
| Status assíncrono | `failed` aleatório (com código escolhido de uma lista), reordenação, duplicação |
| Webhook | `drop` (nunca entrega), `duplicate`, `batch` (vários eventos num POST), atraso extra |

Presets: `off` (padrão), `flaky` (percentuais baixos), `hostile` (percentuais altos). Toda injeção é
marcada com `chaos_tag` no log correspondente, com a regra que disparou.

## 8. UI (LiveView)

Atualização em tempo real via PubSub. Telas:

1. **Chat:** seletor de linha; lista de contatos (última mensagem, não lidas, badge da janela); conversa
   na perspectiva do cliente com renderização de texto, interactive, templates (parâmetros substituídos,
   mídia no header), ticks e "digitando…"; composer com texto, anexo, áudio, localização, reação; painel
   lateral com JSON cru e entregas de webhook da mensagem.
2. **Contatos:** criar/editar, comportamento, online/offline, política de leitura, "gerar N contatos".
3. **Templates:** lista por WABA, preview, aprovar/rejeitar, política de aprovação.
4. **Campanhas:** envios `template` agrupados por nome e janela de tempo; contagem por status; msgs/s;
   contagem de `130429`.
5. **Config:** app (gerar/revelar secret, verify token, webhook URL, verificar), WABAs, números, tokens,
   bloco `.env` pronto para a pigz-api.
6. **Caos:** presets, sliders, seed.
7. **Logs:** requisições Graph e entregas de webhook, filtros, stream ao vivo; erros internos em destaque.

Bloco `.env` gerado:

```
META_APP_ID=<app_id>
META_APP_SECRET=<app_secret>
META_GRAPH_BASE_URL=<WHELX_PUBLIC_URL>
META_GRAPH_API_VERSION=v25.0
WHATSAPP_WEBHOOK_VERIFY_TOKEN=<verify_token>
```

## 9. API de controle e MCP

REST JSON sob `/_whelx`:

| Método e rota | Função |
|---|---|
| `POST /seed` | Cenário declarativo (app, WABAs, números, tokens, contatos, templates); idempotente |
| `POST /reset?keep=` | Zera dados de teste |
| `GET`/`PUT /config` | Lê/altera configuração |
| `POST /tokens` | Gera token `EAA…` |
| `PUT /chaos` | Altera perfil de caos |
| `GET`/`POST`/`PATCH`/`DELETE /contacts[/{wa_id}]` | CRUD de contatos |
| `POST /contacts/bulk` | Gera N contatos |
| `POST /contacts/{wa_id}/messages` | Mensagem de entrada de qualquer tipo suportado |
| `POST /contacts/{wa_id}/reply-interactive` | `{wamid, id}` → clique em botão/lista/quick reply |
| `GET /messages` | Filtros: direção, linha, contato, tipo, status, `since` |
| `GET /conversations/{id}` | Conversa com mensagens |
| `POST /conversations/{id}/open` | Marca aberta (dispara `read` com `on_open`) |
| `POST /conversations/{id}/expire-window` | Força janela vencida |
| `POST /templates/{id}/approve` · `/reject` | Muda status do template |
| `GET /webhooks/deliveries` · `POST /webhooks/deliveries/{id}/redeliver` | Log e reentrega |
| `POST /webhooks/verify` | Handshake de verificação |
| `GET /requests` | Log da Graph |
| `POST /wait` | Long-poll até condição (`outbound_message`, `status`, `webhook_delivery`) ou timeout |

`POST /wait` exemplo:

```json
{"kind":"outbound_message","contact":"5511999999999","after":"<wamid ou timestamp>","timeout_ms":30000}
```

Resposta: a mensagem que satisfez a condição, ou HTTP 408 com o estado observado.

**MCP:** Streamable HTTP em `/_whelx/mcp`; tools espelham a API REST (`seed`, `reset`, `send_as_contact`,
`reply_interactive`, `wait_for`, `list_messages`, `approve_template`, `set_chaos`, `list_webhook_deliveries`,
`redeliver_webhook`). Biblioteca (`hermes_mcp` ou implementação JSON-RPC mínima) decidida no plano.

**Segurança:** UI e API de controle sem autenticação, uso estritamente local. Bind padrão em `127.0.0.1`;
imagem Docker usa `0.0.0.0` para funcionar dentro da rede do compose. README alerta para não expor a porta,
pois a UI revela o app secret. Tokens são mascarados em `GraphRequestLog`.

## 10. Pré-requisito na pigz-api

Item separado, repositório `pigz-api`, PR próprio:

- `MetaWhatsappApiClient` passa a receber `$graphBaseUrl` (env `META_GRAPH_BASE_URL`, default
  `https://graph.facebook.com`) e monta `baseUrl` a partir dele, como `PigzNotificationsWhatsappClient`
  já faz.
- Ajuste em `config/services.yaml` e teste unitário cobrindo a base configurável.
- O cliente legado (`Messengers\WhatsappService`) fica fora.

## 11. Erros internos

Exceção no whelx → HTTP 500 com `{"error":{"message":"An unknown error occurred","type":"OAuthException",
"code":1,"fbtrace_id":"..."}}`, registrada como erro interno (destaque vermelho nos logs da UI), distinta de
injeções de caos (`chaos_tag`).

## 12. Testes

- ExUnit por context; Oban em `testing: :manual`.
- Testes de contrato (ConnTest) com shapes tirados dos testes da pigz-api: resumable (`OAuth`,
  `file_offset`, `upload:XXX`, `h`), `messages[0].id` com HTTP 200, token `EAA`, create template com
  `status: PENDING`, erro de create com objeto `error` completo.
- Assinatura de webhook verificada com HMAC calculado independentemente no teste.
- Caos: mesma seed produz a mesma sequência de decisões.
- LiveView: enviar mensagem como cliente, clicar em botão interativo, aprovar template.

## 13. Critérios de pronto

1. **Bot de pedidos** contra a pigz-api real: seed → contato envia "oi" → whelx registra read+typing e a
   resposta do bot → contato clica em botão/lista → bot envia `order_details` Pix → áudio gravado é baixado
   pela pigz-api via `GET /{media_id}` e transcrito.
2. **Campanha** contra a pigz-api real: template criado pelo painel → aprovado no whelx → disparo para
   500 contatos gerados → monitor mostra ~75 msgs/s → status progridem → com preset `flaky`, falhas
   aparecem nos logs/contadores da pigz-api.
3. Os fluxos 1 e 2 conduzíveis exclusivamente via REST e via MCP.
4. `docker run` da imagem sobe o whelx com dados persistidos em volume.

## 14. Distribuição

- Desenvolvimento: `mix setup && mix phx.server`.
- Imagem: `Dockerfile` multi-stage com release; snippet de `docker-compose` para a pigz-api.
- Variáveis: `PORT` (padrão 4000), `WHELX_PUBLIC_URL` (base das URLs de mídia, alcançável pela pigz-api,
  ex.: `http://whelx:4000`), `DATA_DIR` (SQLite + mídia), `BIND_IP`.

## 15. Fora do escopo do sub-projeto 1

- Embedded Signup, `oauth/access_token`, `debug_token` → sub-projeto 3.
- Webhooks de coexistência (`smb_message_echoes`, `history`, `smb_app_state_sync`, `account_update`)
  → sub-projeto 2.
- Cliente legado da pigz-api (Graph v13/v18).
- Envio de mídia pelo business (`image`/`document`/`audio` outbound) e `POST /{phone}/media`.
- WhatsApp Flows, business profile, registro de número, analytics, webhook de status de template.
- Snapshots nomeados; conformidade automatizada com a OpenAPI da Meta.
- Autenticação na UI/API de controle.
