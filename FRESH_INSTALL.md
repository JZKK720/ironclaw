# IronClaw — Fresh Machine Deploy (v0.19.0)

Personal reference for setting up a clean IronClaw instance on a new machine
from the fork `JZKK720/ironclaw` at branch `replay/setup-env-0.19` (version `0.19.0-dev`).

---

## 1. Prerequisites

Install on the **host** (not inside Docker):

- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [Git](https://git-scm.com/)
- [Ollama](https://ollama.com/) — then pull the required model:

```powershell
ollama pull qwen3.5:9b-q8_0
```

---

## 2. Clone the repo

```powershell
git clone https://github.com/JZKK720/ironclaw.git
cd ironclaw
git checkout replay/setup-env-0.19
```

---

## 3. Create the `.env` file

```powershell
copy .env.example .env
```

Open `.env` and fill in / confirm the following values:

```dotenv
# --- Core ---
SECRETS_MASTER_KEY=<same key as other machines, for consistent secret decryption>
ONBOARD_COMPLETED=true
IRONCLAW_IN_DOCKER=true
IRONCLAW_SKIP_KEYCHAIN=true

# --- Gateway ---
GATEWAY_ENABLED=true
GATEWAY_HOST=0.0.0.0
GATEWAY_PORT=3000
GATEWAY_AUTH_TOKEN=<your personal token>
GATEWAY_USER_ID=default

# --- LLM (legacy single-model, bypasses wizard) ---
LLM_BACKEND=ollama
OLLAMA_BASE_URL=http://host.docker.internal:11434
OLLAMA_MODEL=qwen3.5:9b-q8_0

# --- Database (docker-compose default, no change needed) ---
DATABASE_URL=postgres://ironclaw:ironclaw@postgres:5432/ironclaw

# --- Telegram (only one machine should have polling enabled at a time) ---
TELEGRAM_BOT_TOKEN=<your bot token>
TELEGRAM_POLLING_ENABLED=true

# --- Tunnel (Cloudflare — one active tunnel per token) ---
TUNNEL_PROVIDER=cloudflare
TUNNEL_CF_TOKEN=<your cloudflare tunnel token>
TUNNEL_URL=https://<your-tunnel-domain>/

# --- Extensions ---
EXTENSIONS_DIR=/app/extensions
PUBLIC_GATEWAY_URL=http://localhost:3231
```

> **Note:** `SECRETS_MASTER_KEY` must be **identical** across all machines if you
> ever share or restore database data. Different keys = unreadable secrets.

> **Note:** `TELEGRAM_POLLING_ENABLED=true` on **two machines at once** will
> cause Telegram to alternate between them. Disable on the machine not in use.

---

## 4. Build and start

```powershell
docker compose build
docker compose up -d
```

First build takes ~5–10 minutes (Rust compile). Subsequent builds are faster
due to Docker layer cache.

---

## 5. Verify

```powershell
docker compose ps          # postgres and app should show "running"
docker compose logs -f app # watch startup — look for "listening on 0.0.0.0:3000"
```

---

## 6. Access

| What | URL |
|---|---|
| Web UI | `http://localhost:3231` |
| HTTP webhook | `http://localhost:8281` |
| Auth | `GATEWAY_AUTH_TOKEN` from your `.env` |

---

## 7. Ports

| Host port | Container | Service |
|---|---|---|
| `5432` | `5432` | PostgreSQL (localhost only) |
| `3231` | `3000` | IronClaw web gateway |
| `8281` | `8080` | HTTP webhook endpoint |

---

## 8. Update to a newer version

```powershell
git pull
docker compose build
docker compose up -d
```

The `pgdata` Docker volume persists the database — no data loss on rebuild.

---

## 9. Stop / clean up

```powershell
docker compose down          # stop, keep database volume
docker compose down -v       # stop AND delete database (fresh slate)
```

---

## Branch summary (what's included in this build vs upstream v0.19.0)

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
