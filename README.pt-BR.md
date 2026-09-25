<h1 align="center">whelx</h1>

<p align="center"><strong>Pare de mandar mensagem para o seu próprio celular para testar o seu bot de WhatsApp.</strong></p>

<p align="center">
  Uma cópia local e fiel da WhatsApp Cloud API da Meta: mesmos endpoints, mesmo JSON, mesmos códigos de erro, webhooks assinados,<br/>
  e um chat estilo WhatsApp Web em que <strong>você</strong> é o cliente.
</p>

<p align="center">
  <a href="README.md">🇺🇸 Read in English</a>
</p>

<p align="center">
  <img src="docs/assets/demo.gif" alt="Um cliente pede uma pizza no chat do whelx: o bot responde com um cardápio, o cliente escolhe e recebe o card do pedido com Pix" width="860"/>
</p>

```bash
docker run -p 4000:4000 ghcr.io/carvalhosauro/whelx
```

Aponte a sua aplicação para `http://localhost:4000` em vez de `https://graph.facebook.com`, abra http://localhost:4000 e mande um "oi".

---

## Por quê

Hoje, testar um bot de WhatsApp exige um app na Meta, um número de teste e um túnel ngrok. Você manda mensagem para si mesmo e torce para o webhook chegar. Reproduzir um `131047` (janela de 24 h fechada) significa esperar 24 horas. Fazer teste de carga de uma campanha pode queimar um número de verdade.

O whelx roda a Cloud API inteira no seu computador. A sua aplicação não percebe a diferença.

| | Número de teste da Meta | Mock feito à mão (WireMock etc.) | **whelx** |
|---|---|---|---|
| Precisa de conta, app e número na Meta | sim | não | **não** |
| Webhooks assinados de verdade (`X-Hub-Signature-256`) | sim, via túnel | não | **sim** |
| Status `sent → delivered → read → failed` | sim, sem controle | escrito à mão | **sim, controlável** |
| Erros reais (`130429`, `131047`, `132001`, `131056`…) | difíceis de provocar | inventados | **sob demanda** |
| Limite de 80 msg/s por número | real, arriscado de testar | não | **emulado** (200 requests → 80 aceitos, 120 × `130429`) |
| Janela de 24 h | esperar 24 h | não | **vence com um clique** |
| Caos: webhook perdido, duplicado, fora de ordem | não | não | **sim, determinístico por seed** |
| Dirigido por agente de código (MCP) | não | não | **sim** |
| Custo e risco | conversas pagas, número pode ser sinalizado | grátis, mas se distancia da realidade | **grátis e local** |

## O que tem dentro

- **Graph API fake** em `/vNN.N/...`, qualquer versão. Cobre:
  - mensagens: texto, template e interactive (botões, lista, CTA URL, `order_details`)
  - read receipt com "digitando…"
  - templates: criação, listagem paginada, remoção e revisão
  - mídia (`GET /{media_id}` e download) e upload resumable
  - WABAs, números e `subscribed_apps`, com override de callback por WABA e por número
- **Webhooks assinados** de mensagens recebidas e de status, no formato atual da Meta (v24+). Têm retry com backoff, e cada entrega fica registrada com payload, assinatura e resposta.
- **Chat** em que você é o cliente: texto, áudio gravado no navegador, imagem e documento, localização, reações, cliques em botões e listas, e o card de pedido com Pix. Cada mensagem pode ser inspecionada em JSON, junto com os webhooks que gerou.
- **Painel de campanhas**: envios de template agrupados por nome, msg/s, evolução dos status e quantidade de rate limit.
- **API de controle** (`/_whelx/*`) e **servidor MCP** (`/_whelx/mcp`): testes e agentes de código fazem o papel do cliente e esperam a resposta do seu bot.
- **Caos determinístico**: latência, erros síncronos, falhas assíncronas, e webhooks perdidos, duplicados, reordenados ou agrupados. Pode ser global ou limitado a números específicos.

## Fiel à Meta

- Sucesso é HTTP 200 com `messages[0].id` (`wamid.…`). `message_status: "accepted"` só aparece em envio de template.
- Os erros seguem o envelope da Meta: `{"error": {message, type, code, error_subcode, error_user_msg, error_data, fbtrace_id}}`. Objeto desconhecido devolve `code 100 / subcode 33`, `GraphMethodException`.
- **Janela de 24 h:** mensagem livre fora da janela recebe 200 e depois um webhook `failed` com `131047`, como em produção.
- **Templates:** template inexistente ou não aprovado dá `132001`. Número de parâmetros errado dá `132000`. Nome e idioma duplicados dão `2388024`.
- **Limites:** throughput por número dá `130429` (HTTP 400). O pair rate limit opcional (mesmo cliente: burst de 45, depois 1 msg a cada 6 s) dá `131056`.
- **Webhooks de status:** sem o objeto `conversation` (v24+), com `pricing` PMP e `errors[].href`.
- **`order_details`:** validado com as regras da Meta:
  - a soma dos itens precisa bater com o subtotal
  - o total precisa ser subtotal + tax + shipping − discount
  - `reference_id`, `retailer_id` e a chave Pix são conferidos
- Tudo o que o whelx ainda não emula devolve `code 100` com `whelx: not supported`, nunca um sucesso silencioso.

## Usando com a sua aplicação

1. Torne a base URL da Graph API configurável na sua aplicação. Normalmente é a única mudança de código.
2. Copie o bloco `.env` da tela **Config**: base URL, app secret, verify token, access token, id do WABA e id do número.
3. Configure a URL do seu webhook em **Config** e clique em **Verificar webhook**.

O passo a passo completo, com Docker Compose, campanhas e caos, está em [docs/testing-your-app.md](docs/testing-your-app.md) (em inglês).

### Dirigindo por testes ou CI

```bash
# o cliente manda "oi"
curl -s -X POST localhost:4000/_whelx/contacts/5511988887777/messages \
  -H 'content-type: application/json' -d '{"type":"text","text":"oi"}'

# espera a resposta do seu bot (sem sleep)
curl -s -X POST localhost:4000/_whelx/wait -H 'content-type: application/json' \
  -d '{"kind":"outbound_message","contact":"5511988887777","timeout_ms":30000}'
```

Todos os endpoints de controle estão na [tabela do README em inglês](README.md#drive-it-from-tests-or-ci).

### Deixando o seu agente de código testar

```bash
claude mcp add --transport http whelx http://localhost:4000/_whelx/mcp
```

## Configuração

| Variável | Padrão | Uso |
|---|---|---|
| `PORT` | `4000` | porta HTTP |
| `BIND_IP` | `0.0.0.0` no Docker, `127.0.0.1` em dev | interface |
| `WHELX_PUBLIC_URL` | `http://localhost:$PORT` | base das URLs de mídia e de paginação; precisa ser alcançável pela sua aplicação |
| `DATA_DIR` | `/data` no Docker | banco SQLite e arquivos de mídia (monte um volume para persistir) |
| `SECRET_KEY_BASE` | aleatório por boot | só assina sessões da UI |

## Desenvolvimento

```bash
mix setup
mix phx.server          # http://localhost:4000
mix test
python3 scripts/smoke.py --base http://localhost:4000   # ponta a ponta, simula uma aplicação cliente (apaga os dados)
```

Feito com Elixir, Phoenix LiveView, SQLite e Oban.

## Licença

[MIT](LICENSE)

## Segurança

O whelx é uma ferramenta de teste local. A UI e a API de controle **não têm autenticação** (só rejeitam requisições vindas de outros sites), e a tela de Config mostra o seu app secret. Não exponha a porta em uma rede em que você não confia.

---

<p align="center">
  Inspirado no <a href="https://github.com/floci-io/floci">floci</a>, que faz o mesmo para a AWS.<br/>
  Sem afiliação, endosso ou patrocínio da Meta. WhatsApp é marca registrada da Meta Platforms, Inc.<br/>
  ⭐ Dê uma estrela se ele te poupou de mandar mensagem para você mesmo.
</p>
