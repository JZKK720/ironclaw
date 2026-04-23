---
applyTo: "channels-src/telegram/**,tests/telegram_auth_integration.rs,tests/e2e_telegram_message_routing.rs,src/channels/wasm/**"
description: "Telegram WASM channel: architecture, common failure modes, and smoke testing. Apply when modifying the Telegram channel or diagnosing why it stopped working."
---

# Telegram Channel — Quick Reference

## What it is

The Telegram channel is a WASM component (`channels-src/telegram/`) built with the WIT component model and loaded at runtime from `~/.ironclaw/channels/telegram.wasm`. It is **not** a native Rust module — changes require rebuilding the WASM binary separately from the main crate.

Key files:
- `channels-src/telegram/src/lib.rs` — all channel logic (parsing, auth, API calls, split/send)
- `channels-src/telegram/telegram.capabilities.json` — HTTP allowlist, secret names, rate limits, default config
- `src/channels/wasm/setup.rs` — where the host loads and names WASM channels; the name must match `"telegram"` exactly

## Build

```powershell
# From repo root — builds the WASM binary and places telegram.wasm in channels-src/telegram/
cd channels-src/telegram
cargo build --target wasm32-wasip2 --release
# To also produce the loadable component (strips + component-wraps):
./build.sh    # Linux/macOS
```

On Windows, use Docker as the authoritative build path (see [build-validation-notes](../../memories/repo/build-validation-notes.md)):
```powershell
docker compose up -d --build ironclaw
```

After rebuilding, copy updated artifacts to the install location:
```powershell
cp channels-src/telegram/target/wasm32-wasip2/release/telegram_channel.wasm ~/.ironclaw/channels/telegram.wasm
cp channels-src/telegram/telegram.capabilities.json ~/.ironclaw/channels/
```

## Configuration knobs

Set in the channel's `config` block (persisted in workspace `channels/telegram/state/`):

| Key | Default | Notes |
|-----|---------|-------|
| `dm_policy` | `"pairing"` | `pairing` / `open` / `allowlist` — controls who can DM |
| `allow_from` | `[]` | Telegram user IDs allowed when `dm_policy = "allowlist"` |
| `owner_id` | `null` | Owner gets instance-global access; others become channel-scoped guests |
| `polling_enabled` | `false` | Long-poll mode (no public URL needed) |
| `webhook_enabled` | `false` | Webhook mode (requires `tunnel_url` to be set) |
| `respond_to_all_group_messages` | `false` | If false, bot only responds when @mentioned in groups |

## Common failure modes

1. **Channel not loading at startup** — The WASM binary at `~/.ironclaw/channels/telegram.wasm` is missing, stale, or built for the wrong target. Rebuild with `--target wasm32-wasip2`.

2. **Bot stops responding in groups** — The group message filter requires either `respond_to_all_group_messages: true` or an @mention of the configured `bot_username`. If `bot_username` is wrong/null, mention detection silently drops every message.

3. **Auth bypass / all messages dropped with `allowlist` policy** — `allow_from` is stored in workspace state (`channels/telegram/state/allow_from`). If the workspace was reset or the state file is missing, the allowlist is empty and all messages are dropped (including the owner's). Re-configure the channel.

4. **`HTTP_WEBHOOK_SECRET` not set** — Even in polling mode, the built-in HTTP channel requires this env var or it won't start. Telegram polling is unaffected but the startup log shows a warning. Set `HTTP_WEBHOOK_SECRET` in `~/.ironclaw/.env` or `SANDBOX_ENABLED=false` if Docker is not in use.

5. **Duplicate updates processed** — `update_id` deduplication state lives in workspace (`channels/telegram/state/last_update_id`). On fresh installs or workspace wipes this counter resets and the bot may replay old updates once.

6. **Webhook not receiving updates** — Webhook mode needs `tunnel_url` set AND `webhook_enabled: true` AND `polling_enabled: false`. All three must be set; partial config silently falls back to no-op.

7. **WASM channel name collision at startup** — The host loads channels by filename. If a file named `telegram.wasm` exists in the channels dir but is from a different version/build, the host may fail with a type mismatch on the WIT interface. Delete the stale file and reinstall.

## Smoke-testing hierarchy

Run these in order — each level takes longer but covers more:

### Level 1 — WASM unit tests (fastest, no WASM runtime needed)
```bash
cargo test --manifest-path channels-src/telegram/Cargo.toml
```
Covers: message splitting, text cleaning, entity parsing. No network or host calls.

### Level 2 — E2E message routing (libsql, no real Telegram API)
```bash
cargo test --no-default-features --features libsql --test e2e_telegram_message_routing -- --nocapture
```
Covers: `message` tool routing to Telegram, `RecordingTelegramChannel` captures.

### Level 3 — Full WASM auth integration (requires WASM build)
```bash
# Build WASM first:
cargo build --manifest-path channels-src/telegram/Cargo.toml --target wasm32-wasip2 --release
# Run tests:
cargo test --features integration --test telegram_auth_integration -- --nocapture
```
Covers: `dm_policy`, `allow_from`, `owner_id` enforcement, group/DM routing, dedup, attachments.

### Level 4 — Thread-scope regression (single targeted test)
```bash
cargo test --features integration --test telegram_auth_integration \
  test_private_messages_use_chat_id_as_thread_scope -- --exact --nocapture
```

> **Windows note**: Smart App Control may block freshly built test executables. Use `docker compose up -d --build ironclaw` for runtime validation, or see `docs/plans/2026-04-14-windows-rust-runtime-unblock.md` + `scripts/sign-rust-artifacts.ps1`.

## Validation endpoint

To verify a bot token is valid without running any tests:
```bash
curl "https://api.telegram.org/bot<YOUR_TOKEN>/getMe"
```
The token format is `<numeric_id>:<alphanumeric_string>` (e.g. `123456789:AABBccDDeeFFgg…`).
