# IronClaw — Copilot Workspace Instructions

> Quick-start guide focused on local setup, Docker post-container configuration,
> channel/MCP/tools wiring, and webhook verification.
> For full architecture and code conventions see `AGENTS.md` and `CLAUDE.md`.

---

## 1. First-Time Local Setup (Docker Compose)

### Prerequisites

- Docker Desktop (or Docker Engine + Compose plugin)
- A working LLM API key **or** a local Ollama instance
- (Optional) Cloudflare / ngrok account for public webhook exposure

### Steps

```powershell
# 1. Copy and fill the env file — this is the ONLY config source for Docker
cp .env.example .env
# Edit .env with your LLM key, tunnel token, channel tokens (see §3 below)

# 2. Pull and start (skips interactive wizard because command: ["--no-onboard"] is set)
docker compose up -d

# 3. Verify the boot screen printed correctly
docker compose logs -f ironclaw
# Look for:  Web Gateway → http://localhost:3231
#            Webhook     → http://localhost:8281
```

> **Why `--no-onboard`?** The `docker-compose.yml` passes `--no-onboard`,
> so the wizard is skipped entirely. Everything must be pre-configured in `.env`.
> If you need the interactive wizard inside the container:
> ```bash
> docker exec -it ironclaw-ironclaw-1 ironclaw onboard
> ```

---

## 2. Critical Docker-specific `.env` Variables

These differ from a native install — set them **before** `docker compose up`:

```dotenv
# --- Required for Docker ---
# DB uses the internal Docker network alias, not localhost
DATABASE_URL=postgres://ironclaw:ironclaw@postgres:5432/ironclaw

# Bypass OS keychain (unavailable inside containers)
IRONCLAW_SKIP_KEYCHAIN=true

# Master encryption key — change this from the default!
# Must be ≥32 chars; all secrets in the DB are encrypted with this key.
SECRETS_MASTER_KEY=my-super-secret-32-char-master-key!!

# Enables the /restart command inside the container
IRONCLAW_IN_DOCKER=true

# Bind the gateway to all interfaces inside Docker so host port 3231 works
GATEWAY_HOST=0.0.0.0

# Makes the boot screen show the correct host-side URL
PUBLIC_GATEWAY_URL=http://localhost:3231
```

> **Security note:** Never commit `.env` or `SECRETS_MASTER_KEY` to git.
> Rotate `SECRETS_MASTER_KEY` only when starting fresh (rotating it
> invalidates all encrypted secrets in the database).

---

## 3. Configuring Channels (Post-Container)

Channels are WASM modules loaded at startup. Each reads its credentials
from the encrypted secrets store (written by the wizard) **or** from env vars.

### Option A — Set via `.env` (recommended for Docker)

```dotenv
# Telegram
TELEGRAM_BOT_TOKEN=1234567890:ABCdef...   # from @BotFather

# Slack
SLACK_BOT_TOKEN=xoxb-...
SLACK_APP_TOKEN=xapp-...
SLACK_SIGNING_SECRET=...

# HTTP Webhook (shared server for all channels)
HTTP_HOST=0.0.0.0
HTTP_PORT=8080
HTTP_WEBHOOK_SECRET=some-random-secret
```

Restart the container after editing `.env`:
```
docker compose restart ironclaw
```

### Option B — Re-run the channel wizard inside the container

```bash
docker exec -it ironclaw-ironclaw-1 ironclaw onboard --channels-only
```

This stores tokens encrypted in the database — no `.env` entry needed.
Useful when migrating an existing setup to a new machine.

### Telegram: Webhook vs Polling

| Mode | Requirement | Latency |
|------|-------------|---------|
| Webhook | Public URL (tunnel required) | Instant |
| Polling | None — works offline | ~30 s |

If no tunnel is configured, IronClaw falls back to polling automatically.

---

## 4. Tunnel Setup (Webhooks to the Public Internet)

Without a tunnel, external services (Telegram, Slack, GitHub) cannot reach
the webhook server on `localhost:8281`.

### Cloudflare Tunnel (recommended for Docker)

```dotenv
# .env
TUNNEL_PROVIDER=cloudflare
TUNNEL_CF_TOKEN=<token from https://dash.cloudflare.com/profile/api-tokens>
```

The tunnel container in `docker-compose.yml` reaches the webhook server via
`host.docker.internal:8281`. Cloudflare provides a random `*.trycloudflare.com`
URL that is injected into channel webhook registration automatically.

### ngrok

```dotenv
TUNNEL_PROVIDER=ngrok
TUNNEL_NGROK_TOKEN=<token from ngrok dashboard>
# TUNNEL_NGROK_DOMAIN=custom.ngrok.dev   # optional paid feature
```

### Static URL (reverse proxy / existing public host)

```dotenv
# Skip managed tunnel; provide the URL directly
TUNNEL_URL=https://ironclaw.example.com
```

### Verify the tunnel is working

```bash
# Check logs for the resolved public URL
docker compose logs ironclaw | grep -i tunnel

# Manual webhook probe (Telegram example)
curl https://<your-tunnel-url>/telegram/<bot-token>
# Expected: 200 or "not found" (any HTTP response proves the path is reachable)
```

---

## 5. MCP (Model Context Protocol) Server Setup

MCP servers are configured per-installation and stored in
`~/.ironclaw/mcp_servers.json` (inside the container volume `ironclaw-data`).

### Add via CLI (inside container)

```bash
# HTTP/SSE transport (most common for hosted servers)
docker exec -it ironclaw-ironclaw-1 \
  ironclaw mcp add notion https://mcp.notion.com

# With an API token header
docker exec -it ironclaw-ironclaw-1 \
  ironclaw mcp add github https://mcp.github.com \
  --header "Authorization:Bearer ghp_yourtoken"

# stdio transport (local binary)
docker exec -it ironclaw-ironclaw-1 \
  ironclaw mcp add my-tool --transport stdio \
  --command /usr/local/bin/my-mcp-server \
  --env API_KEY=abc123

# List configured MCP servers
docker exec -it ironclaw-ironclaw-1 ironclaw mcp list

# Test connectivity
docker exec -it ironclaw-ironclaw-1 ironclaw mcp test notion
```

### Persist MCP config across container rebuilds

MCP config lives in the `ironclaw-data` Docker volume. To back it up:
```bash
docker exec ironclaw-ironclaw-1 cat ~/.ironclaw/mcp_servers.json > mcp_servers.json
```

To pre-seed it on a new machine, copy the file into the volume before first start.

---

## 6. Tool Configuration

### Built-in tools

Always available, no configuration required:
`file`, `shell`, `memory_*`, `http_request`, `web_fetch`, `time`, `echo`,
`job_*`, `routine_*`, `skill_*`, `secrets_*`

### WASM tools (from registry)

```bash
# List available tools in the registry
docker exec -it ironclaw-ironclaw-1 ironclaw registry list

# Install a tool
docker exec -it ironclaw-ironclaw-1 ironclaw registry install <tool-name>

# After install, verify it loaded
docker exec -it ironclaw-ironclaw-1 ironclaw tool list
```

Tools that need API credentials: grant secrets via `ironclaw secrets set <name> <value>`
or pass them via `.env` (the tool description in the registry lists required env vars).

---

## 7. Verifying Everything Works

### Health check commands

```bash
# Quick one-line status
docker exec -it ironclaw-ironclaw-1 ironclaw status

# Deep diagnostic with actionable failure messages
docker exec -it ironclaw-ironclaw-1 ironclaw doctor
```

`doctor` checks: settings file, NEAR AI session, LLM config, database,
workspace dir, embeddings, routines, gateway, MCP servers, skills, secrets,
Docker daemon, cloudflared, ngrok.

### LLM connectivity

```bash
# Send a test message via the REPL inside the container
docker exec -it ironclaw-ironclaw-1 ironclaw
# Type: hello
# If you get a response, LLM + agent loop are working.
```

### Webhook reachability (Telegram example)

```bash
# Check Telegram's registered webhook URL
curl "https://api.telegram.org/bot<TOKEN>/getWebhookInfo"
# "url" should match your tunnel URL + /telegram/<TOKEN>
# "last_error_message" should be empty

# Force re-register the webhook (if URL changed)
docker exec -it ironclaw-ironclaw-1 ironclaw onboard --channels-only
```

### Web Gateway UI

Open `http://localhost:3231` in a browser. If the page loads and shows the
chat interface, the web gateway is running correctly.

---

## 8. Moving Setup to a New Machine

1. **Copy `.env`** — contains all LLM keys, tunnel tokens, channel tokens
2. **Export secrets from volumes** (if using Option B channel setup):
   ```bash
   # On old machine
   docker run --rm -v ironclaw_ironclaw-data:/data alpine \
     tar czf - /data > ironclaw-data.tar.gz

   # On new machine (before first start)
   docker run --rm -v ironclaw_ironclaw-data:/data alpine \
     tar xzf - < ironclaw-data.tar.gz
   ```
3. **Re-run tunnel setup** — Cloudflare/ngrok tokens are machine-independent;
   the tunnel URL may change (update any hardcoded webhook URLs)
4. **Verify with `ironclaw doctor`** after first start

---

## 9. Common Pitfalls

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Container starts but LLM fails | Wrong/missing API key in `.env` | Check `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, etc. |
| `SECRETS_MASTER_KEY` warning in logs | Using the demo key from `docker-compose.yml` | Set a unique 32+ char key in `.env` |
| Telegram not receiving messages | Webhook not registered or tunnel down | Run `ironclaw onboard --channels-only`; check tunnel logs |
| MCP server "connection refused" | Server URL wrong or auth header missing | `ironclaw mcp test <name>`; re-add with correct `--header` |
| `database: not configured` in status | `DATABASE_URL` points to wrong host | In Docker, use `@postgres:5432`, not `@localhost` |
| Channel loads but no messages arrive | DM pairing required | Send `/start` to the bot; `ironclaw pairing list <channel>` to approve |
| Port 3231 not accessible | Gateway bound to container loopback or port conflict | Check `GATEWAY_HOST=0.0.0.0`, `PUBLIC_GATEWAY_URL`, and `docker compose ps` |
| Secrets unavailable after container rebuild | Volume not mounted or `SECRETS_MASTER_KEY` changed | Verify `ironclaw-data` volume is mounted; keep master key consistent |

---

## 10. Key File Locations (inside container)

| Path | Purpose |
|------|---------|
| `~/.ironclaw/.env` | Bootstrap config written by wizard (`ONBOARD_COMPLETED`, `DATABASE_URL`) |
| `~/.ironclaw/session.json` | NEAR AI OAuth session token |
| `~/.ironclaw/settings.json` | Agent settings (model, embeddings, channels, etc.) |
| `~/.ironclaw/mcp_servers.json` | MCP server registry |
| `~/.ironclaw/ironclaw.db` | libSQL database (if not using PostgreSQL) |
| `~/.ironclaw/extensions/` | Installed WASM tools |
| `~/.ironclaw/channels/` | Installed WASM channels |
| `~/.ironclaw/skills/` | Trusted user skills |

---

## 11. Build & Lint Reference

```bash
cargo fmt --all
cargo clippy --all --benches --tests --examples --all-features -- -D warnings
cargo test
cargo test --features integration   # requires PostgreSQL at DATABASE_URL
```

- No `.unwrap()` / `.expect()` in production code
- All persistence changes must support **both** PostgreSQL and libSQL backends
- Complexity thresholds in `clippy.toml`: cognitive 15, fn lines 100, args 7
