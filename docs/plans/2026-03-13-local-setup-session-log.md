# 2026-03-13 Local Setup Session Log

## Objective

Stabilize the local Docker-based IronClaw setup on Windows, get onboarding and runtime working, make Telegram usable, fix gateway access, verify Ollama-backed LLM access, and clean up the broken WeChat-MCP configuration.

## Main Fixes Completed

### Docker and onboarding

- Created and populated `.env` from `.env.example`.
- Corrected Docker database config to use:
  - `DATABASE_URL=postgres://ironclaw:ironclaw@postgres:5432/ironclaw`
- Added Docker-specific runtime flags:
  - `IRONCLAW_SKIP_KEYCHAIN=true`
  - `IRONCLAW_IN_DOCKER=true`
  - `PUBLIC_GATEWAY_URL=http://localhost:3231`
- Fixed onboarding quick-mode database bug in [src/setup/wizard.rs](c:/Users/cubecloud-io/github-pr/ironclaw/src/setup/wizard.rs): PostgreSQL quick setup now initializes the DB pool and runs migrations before persisting settings.
- Fixed Docker volume permission issue in [Dockerfile](c:/Users/cubecloud-io/github-pr/ironclaw/Dockerfile): precreate `/home/ironclaw/.ironclaw` and `chown` it to UID 1000.

### Gateway

- Root cause of broken gateway was Docker bind scope.
- Fixed by binding the gateway to all interfaces in Docker:
  - `GATEWAY_HOST=0.0.0.0`
- Changes applied in:
  - [docker-compose.yml](c:/Users/cubecloud-io/github-pr/ironclaw/docker-compose.yml)
  - [.env](c:/Users/cubecloud-io/github-pr/ironclaw/.env)
  - [.env.example](c:/Users/cubecloud-io/github-pr/ironclaw/.env.example)
  - [.github/copilot-instructions.md](c:/Users/cubecloud-io/github-pr/ironclaw/.github/copilot-instructions.md)
- Verified:
  - `http://127.0.0.1:3231/api/health` returns `200 OK`
  - root page on `http://localhost:3231/` returns `200 OK`

### Telegram

- Telegram registry channel installed and working in polling mode.
- Bot token configured through `.env`.
- Telegram startup timeout fixed by changing WASM host HTTP execution from nested Tokio runtimes to blocking reqwest in:
  - [src/channels/wasm/wrapper.rs](c:/Users/cubecloud-io/github-pr/ironclaw/src/channels/wasm/wrapper.rs)
  - [src/tools/wasm/wrapper.rs](c:/Users/cubecloud-io/github-pr/ironclaw/src/tools/wasm/wrapper.rs)
  - [Cargo.toml](c:/Users/cubecloud-io/github-pr/ironclaw/Cargo.toml) updated to enable reqwest `blocking`
- Pairing was previously approved and Telegram message send/receive flow worked.

### LLM / Ollama

- Corrected Docker access to host Ollama by using `host.docker.internal` instead of `localhost`.
- Current model pool configuration uses local Ollama:
  - Primary: `qwen3.5:35b-a3b`
  - Fallback: `glm-4.7-flash:latest`
- Verified host Ollama is serving models on `http://127.0.0.1:11434/api/tags`.

### Shutdown loop fix

- Found a restart loop caused by Telegram replaying an old `/quit` message on startup.
- Root cause: `/quit` was treated as a global shutdown command in the shared agent loop, regardless of channel.
- Fixed in [src/agent/agent_loop.rs](c:/Users/cubecloud-io/github-pr/ironclaw/src/agent/agent_loop.rs): only the `repl` channel may shut down the agent with `/quit`.
- Cleared Telegram backlog once via Bot API to discard the stale `/quit` update.

### WeChat-MCP

- The configured MCP server `WeChat-MCP` pointed to:
  - `https://biboyqg.github.io/WeChat-MCP/`
- That URL is documentation, not an MCP JSON-RPC endpoint.
- Project docs show WeChat-MCP is normally a **local stdio MCP server** and requires **macOS Accessibility APIs**, so it is not usable on this Windows machine.
- Disabled the broken MCP entry with:
  - `ironclaw mcp toggle WeChat-MCP --disable`
- Verified startup no longer logs the old `405 Method Not Allowed` warning.

## Current Known-Good State

- `ironclaw-app` is up and stable.
- `ironclaw-postgres` is healthy.
- Gateway is healthy on port `3231`.
- HTTP webhook is healthy on port `8281`.
- IronClaw startup shows:
  - model `qwen3.5:35b-a3b via ollama`
  - channels `repl telegram http gateway`
- Latest observed gateway URL at the end of the session:
  - `http://localhost:3231?token=ce1be2573f881d4bb1cae6f82b3316ca86842602ac1852847c791e3a58bf84d0`

## Files Changed During This Session

- [docker-compose.yml](c:/Users/cubecloud-io/github-pr/ironclaw/docker-compose.yml)
- [.env](c:/Users/cubecloud-io/github-pr/ironclaw/.env)
- [.env.example](c:/Users/cubecloud-io/github-pr/ironclaw/.env.example)
- [Dockerfile](c:/Users/cubecloud-io/github-pr/ironclaw/Dockerfile)
- [Cargo.toml](c:/Users/cubecloud-io/github-pr/ironclaw/Cargo.toml)
- [src/setup/wizard.rs](c:/Users/cubecloud-io/github-pr/ironclaw/src/setup/wizard.rs)
- [src/channels/wasm/wrapper.rs](c:/Users/cubecloud-io/github-pr/ironclaw/src/channels/wasm/wrapper.rs)
- [src/tools/wasm/wrapper.rs](c:/Users/cubecloud-io/github-pr/ironclaw/src/tools/wasm/wrapper.rs)
- [src/agent/agent_loop.rs](c:/Users/cubecloud-io/github-pr/ironclaw/src/agent/agent_loop.rs)
- [.github/copilot-instructions.md](c:/Users/cubecloud-io/github-pr/ironclaw/.github/copilot-instructions.md)

## Suggested Next Steps

1. Re-verify Telegram with a fresh live message and confirm the reply path still works end-to-end.
2. Decide whether to remove `WeChat-MCP` entirely instead of keeping it disabled.
3. Review the installed `wechat-auto-reply` skill and remove it if it was only added during experimentation.
4. Optionally tighten Telegram access again if needed, since logs showed `owner_id` was not set and the bot was effectively open with pairing-based control.

## Useful Commands For Resume

```powershell
docker compose ps
docker compose logs ironclaw --tail 120
curl.exe -4 http://127.0.0.1:3231/api/health
docker exec ironclaw-app ironclaw mcp list --verbose
Invoke-RestMethod -Uri http://127.0.0.1:11434/api/tags | ConvertTo-Json -Depth 5
```