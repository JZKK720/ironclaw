# IronClaw — Fresh Machine Deploy (v0.19.0)

Personal runbook for bringing up this fork on a new machine from `JZKK720/ironclaw`
branch `replay/setup-env-0.19` (`0.19.0-dev`).

This version is focused on Docker-first local hosting with Ollama, Telegram,
the web gateway, and HTTP webhooks.

---

## 1. Host prerequisites

Install on the host machine:

- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [Git](https://git-scm.com/)
- [Ollama](https://ollama.com/)
- Optional but useful: `cloudflared` if you want to test Cloudflare manually outside the container flow

Pull the required Ollama model:

```powershell
ollama pull qwen3.5:9b-q8_0
```

Useful Windows helpers added in this fork:

- `scripts/fresh-secrets.ps1` generates `.env`-ready secrets
- `scripts/fresh-logs.ps1` shows Docker Compose status and logs
- `scripts/fresh-check.ps1` runs local health and signed webhook checks

---

## 2. Clone the fork

```powershell
git clone https://github.com/JZKK720/ironclaw.git
cd ironclaw
git checkout replay/setup-env-0.19
```

---

## 3. Pre-setup checklist

Prepare these values before editing `.env`.

### Required for this forked setup

| Item | Why it matters | Action |
|---|---|---|
| `SECRETS_MASTER_KEY` | Decrypts stored secrets | Reuse the same key as your other machines if you want to read existing encrypted secrets or imported DB data. Generate a new one only for a fully isolated install. |
| `GATEWAY_AUTH_TOKEN` | Required for authenticated web gateway APIs | Generate a fresh token for this machine. |
| `HTTP_WEBHOOK_SECRET` | Required by the HTTP webhook channel startup path | Generate a fresh secret. If omitted, the HTTP webhook channel can fail to start. |
| `TELEGRAM_BOT_TOKEN` | Required for the Telegram channel | Reuse your bot token or create a new bot in BotFather. |
| `TUNNEL_CF_TOKEN` | Required for managed Cloudflare tunnel | Generate or reuse a valid Cloudflare tunnel token for the tunnel you want this machine to use. |
| `TUNNEL_URL` | Public HTTPS URL injected into channel runtime config | Set the public HTTPS URL you expect external systems to reach. |

### Telegram mode choice

Choose one mode deliberately:

- Polling mode: set `TELEGRAM_POLLING_ENABLED=true`; simplest, no Telegram webhook dependency, but only one active polling machine should exist per bot.
- Webhook mode: set `TELEGRAM_POLLING_ENABLED=false`; requires working HTTPS ingress and is the correct mode if you want immediate message delivery through a public URL.

### Additional Telegram hardening

Optional but recommended:

- `TELEGRAM_OWNER_ID=<your numeric Telegram user id>` to lock the bot to one owner at host config level.
- `telegram_webhook_secret` in the secret store if you run Telegram in webhook mode.

### Important notes from code review

- `PUBLIC_GATEWAY_URL` is currently only referenced inside this document and is not read by the application. Do not rely on it.
- Managed tunnel startup in the current code targets the gateway port (`3000`). Because of that, webhook-mode validation is mandatory before assuming Telegram or other webhook integrations are actually reachable through the public URL.
- `GATEWAY_AUTH_TOKEN` is optional in code because the app can auto-generate one at startup, but for a repeatable multi-machine setup you should set it explicitly.

### Generate fresh tokens in PowerShell

```powershell
# 32-byte hex secrets
[Convert]::ToHexString((1..32 | ForEach-Object { Get-Random -Minimum 0 -Maximum 256 }))
```

Or use the helper script:

```powershell
.\scripts\fresh-secrets.ps1
.\scripts\fresh-secrets.ps1 -IncludeMasterKey
```

Use separate generated values for:

- `GATEWAY_AUTH_TOKEN`
- `HTTP_WEBHOOK_SECRET`
- a new `SECRETS_MASTER_KEY` only if you intentionally want a brand-new isolated secrets domain

---

## 4. Create and fill `.env`

```powershell
Copy-Item .env.example .env
```

Open `.env` and set at least the following values:

```dotenv
# --- Core ---
SECRETS_MASTER_KEY=<same key as trusted machines, or a brand-new key for isolated install>
ONBOARD_COMPLETED=true
IRONCLAW_IN_DOCKER=true
IRONCLAW_SKIP_KEYCHAIN=true

# --- Gateway ---
GATEWAY_ENABLED=true
GATEWAY_HOST=0.0.0.0
GATEWAY_PORT=3000
GATEWAY_AUTH_TOKEN=<fresh token>

# --- HTTP webhook server ---
HTTP_HOST=0.0.0.0
HTTP_PORT=8080
HTTP_WEBHOOK_SECRET=<fresh secret>

# --- LLM ---
LLM_BACKEND=ollama
OLLAMA_BASE_URL=http://host.docker.internal:11434
OLLAMA_MODEL=qwen3.5:9b-q8_0

# --- Database ---
DATABASE_URL=postgres://ironclaw:ironclaw@postgres:5432/ironclaw

# --- Telegram ---
TELEGRAM_BOT_TOKEN=<bot token>
# Polling mode:
TELEGRAM_POLLING_ENABLED=true
# Or webhook mode:
# TELEGRAM_POLLING_ENABLED=false
# TELEGRAM_OWNER_ID=<your numeric telegram user id>

# --- Tunnel ---
TUNNEL_PROVIDER=cloudflare
TUNNEL_CF_TOKEN=<cloudflare tunnel token>
TUNNEL_URL=https://<your-public-hostname>/

# --- Extensions dir inside container ---
EXTENSIONS_DIR=/app/extensions
```

Notes:

- `SECRETS_MASTER_KEY` must be identical across machines if you ever move or share encrypted secrets data.
- `TELEGRAM_POLLING_ENABLED=true` on two machines with the same bot will cause message handling to bounce between them.
- If you stay in polling mode, the tunnel is not required for Telegram delivery, but you may still want it for other externally-triggered flows.

---

## 5. Optional secrets discovered in the repo

These are not required for the base bring-up, but they are required if you enable the corresponding bundled tools or channels.

| Integration | Secrets |
|---|---|
| GitHub tool | `github_token` |
| Brave-powered search/context tools | `brave_api_key` |
| Google tools | `google_oauth_client_id`, `google_oauth_client_secret`, `google_oauth_token` |
| Slack tool/channel | `slack_bot_token`, `slack_signing_secret`, optional `slack_oauth_client_secret` |
| Telegram tool (not the Telegram channel) | `telegram_api_id`, `telegram_api_hash` |
| Discord channel | `discord_bot_token` |
| Feishu channel | `feishu_app_id`, `feishu_app_secret`, `feishu_verification_token`, `feishu_tenant_access_token` |
| WhatsApp channel | `whatsapp_access_token`, `whatsapp_verify_token` |

If you do not use those integrations, you can ignore them.

---

## 6. Pre-launch checklist

Complete this checklist before the first `docker compose up` on a fresh machine.

| Check | Ready when |
|---|---|
| `.env` created | `.env` exists at repo root and is based on `.env.example` |
| Database config present | `DATABASE_URL=postgres://ironclaw:ironclaw@postgres:5432/ironclaw` is set |
| Onboarding bypass enabled | `ONBOARD_COMPLETED=true` is set |
| Secrets key present | `SECRETS_MASTER_KEY` is set to the reused key or an intentionally new isolated key |
| Docker mode enabled | `IRONCLAW_IN_DOCKER=true` is set |
| Gateway auth fixed | `GATEWAY_AUTH_TOKEN` is explicitly set, not left to auto-generate |
| HTTP webhook enabled | `HTTP_HOST`, `HTTP_PORT`, and `HTTP_WEBHOOK_SECRET` are set |
| Ollama model ready | host Ollama is running and `ollama pull qwen3.5:9b-q8_0` completed |
| Telegram mode chosen | `TELEGRAM_BOT_TOKEN` is set and `TELEGRAM_POLLING_ENABLED` is intentionally `true` or `false` |
| Tunnel decision made | `TUNNEL_PROVIDER`, `TUNNEL_CF_TOKEN`, and `TUNNEL_URL` are set if you expect public ingress |
| Optional integrations scoped | Any enabled GitHub, Slack, Google, WhatsApp, Discord, Feishu, or Brave tooling has its required secret populated |

Recommended one-shot validation before launch:

```powershell
.\scripts\fresh-secrets.ps1 -IncludeMasterKey
```

If you are reusing an existing machine key, do not replace `SECRETS_MASTER_KEY` with the generated value.

---

## 7. Build and start containers

```powershell
docker compose build
docker compose up -d postgres app
```

First build usually takes several minutes because Rust and bundled WASM assets are compiled.

---

## 8. Container logs and runtime checks

### Basic container status

```powershell
docker compose ps
docker compose logs --tail=200 app
docker compose logs --tail=200 postgres
```

Or use:

```powershell
.\scripts\fresh-logs.ps1
```

### Live logs while testing

```powershell
docker compose logs -f app postgres
```

Or use:

```powershell
.\scripts\fresh-logs.ps1 -Follow
```

### In-container diagnostic commands

```powershell
docker compose exec app ironclaw doctor
docker compose exec app ironclaw status
```

What to look for in logs:

- gateway listening on `0.0.0.0:3000`
- webhook server listening on `0.0.0.0:8080`
- no `HTTP webhook secret is required` startup error
- no Ollama connectivity error to `host.docker.internal:11434`
- if using polling mode, Telegram polling activity without auth or request errors
- if using tunnel mode, tunnel startup log and a concrete public URL

---

## 9. Access and local endpoints

| What | URL |
|---|---|
| Web UI | `http://localhost:3231` |
| Gateway health | `http://localhost:3231/api/health` |
| HTTP webhook health | `http://localhost:8281/health` |
| HTTP webhook POST endpoint | `http://localhost:8281/webhook` |

Ports exposed by Docker Compose:

| Host port | Container port | Service |
|---|---|---|
| `5432` | `5432` | PostgreSQL (localhost only) |
| `3231` | `3000` | IronClaw web gateway |
| `8281` | `8080` | HTTP webhook server |

---

## 10. Functional test checklist

Run these after the stack is up.

### 9.1 Gateway health

```powershell
Invoke-RestMethod http://localhost:3231/api/health
```

Or run the helper:

```powershell
.\scripts\fresh-check.ps1
```

Expected:

```json
{"status":"healthy","channel":"gateway"}
```

### 9.2 Gateway authenticated status

```powershell
$Headers = @{ Authorization = "Bearer <GATEWAY_AUTH_TOKEN>" }
Invoke-RestMethod http://localhost:3231/api/gateway/status -Headers $Headers
```

Or run:

```powershell
.\scripts\fresh-check.ps1 -GatewayAuthToken '<GATEWAY_AUTH_TOKEN>'
```

Check that you get JSON with version, uptime, connection counts, and `restart_enabled`.

### 9.3 HTTP webhook health

```powershell
Invoke-RestMethod http://localhost:8281/health
```

Expected:

```json
{"status":"healthy","channel":"http"}
```

### 9.4 Signed HTTP webhook request

```powershell
$Secret = "<HTTP_WEBHOOK_SECRET>"
$Body = '{"content":"fresh-install webhook test","wait_for_response":false}'
$Hmac = [System.Security.Cryptography.HMACSHA256]::new([Text.Encoding]::UTF8.GetBytes($Secret))
$SigBytes = $Hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($Body))
$SigHex = ([BitConverter]::ToString($SigBytes)).Replace('-', '').ToLower()
$Headers = @{ 'X-Hub-Signature-256' = "sha256=$SigHex"; 'Content-Type' = 'application/json' }
Invoke-RestMethod http://localhost:8281/webhook -Method Post -Headers $Headers -Body $Body
```

Or run:

```powershell
.\scripts\fresh-check.ps1 -GatewayAuthToken '<GATEWAY_AUTH_TOKEN>' -HttpWebhookSecret '<HTTP_WEBHOOK_SECRET>'
```

Expected result: accepted JSON response with a message id and status.

### 9.5 Telegram live test

Polling mode:

- DM the bot from Telegram.
- If pairing is still enabled, approve the pairing request.
- Run `docker compose exec app ironclaw pairing list telegram`.
- Approve pending requests with `docker compose exec app ironclaw pairing approve telegram <CODE>`.

Webhook mode:

- Ensure `TELEGRAM_POLLING_ENABLED=false`.
- Ensure `TUNNEL_URL` is reachable over HTTPS.
- Confirm Telegram can hit the public URL path you intend to use.
- Verify logs while sending a DM to the bot.

### 9.6 Cloudflare tunnel reachability

Open the configured public URL in a browser and confirm you reach the expected service.

Because the current managed tunnel startup code points at the gateway port, do not assume webhook traffic is correct until you explicitly test the required public path end to end.

---

## 11. Communication paths to verify before calling the machine ready

Check all of these:

1. Ollama reachable from the container.
2. PostgreSQL healthy and app migrations complete.
3. Gateway reachable on `3231` and accepts `GATEWAY_AUTH_TOKEN`.
4. HTTP webhook reachable on `8281` and accepts signed requests.
5. Telegram receives and emits messages in the selected mode.
6. Tunnel URL resolves publicly and reaches the expected service.
7. Any enabled optional integration has its corresponding secret populated.

---

## 12. Update workflow

```powershell
git pull
docker compose build
docker compose up -d
```

The `pgdata` volume persists the database across rebuilds.

---

## 13. Stop and clean up

```powershell
docker compose down
docker compose down -v
```

Use `-v` only when you intentionally want to delete the database volume and start over.

---

## Branch summary (fork-specific changes vs upstream v0.19.0)

| Change | File(s) |
|---|---|
| Docker networking guidance in `.env.example` | `.env.example` |
| WASM extension local fallback installs | `src/extensions/manager.rs`, `src/registry/installer.rs` |
| Soften Ollama model listing (no hard-fail) | `src/llm/mod.rs` |
| Telegram: preserve slash commands with args | `channels-src/telegram/src/lib.rs` |
| Recover bundled channel capabilities sidecars | `src/channels/wasm/bundled.rs` |
| Telegram polling override config | `src/config/channels.rs` |
| Fix yanked `uds_windows` dependency | `Cargo.toml`, `Cargo.lock` |
| Restore localhost-only Postgres binding | `docker-compose.yml` |
| Force HTTP/1.1 for WASM channel requests | `src/channels/wasm/wrapper.rs` |
| **Version: `0.19.0-dev`** (based on upstream `staging` v0.19.0) | `Cargo.toml` |
