---
description: "Smoke-test the Telegram chatbot channel end-to-end. Use when Telegram stops responding or after any change to channels-src/telegram/."
---

# Smoke Test: Telegram Channel

Run the four levels in order. Stop and investigate at the first level that fails.

## Pre-flight

Check that the Telegram WASM binary exists and is recent:

```powershell
# Windows
Test-Path "~/.ironclaw/channels/telegram.wasm"
(Get-Item "~/.ironclaw/channels/telegram.wasm").LastWriteTime
```

```bash
# Linux/macOS
ls -lh ~/.ironclaw/channels/telegram.wasm
```

If the file is missing or older than your last `channels-src/telegram/` change, rebuild first:

```bash
cargo build --manifest-path channels-src/telegram/Cargo.toml --target wasm32-wasip2 --release
cp channels-src/telegram/target/wasm32-wasip2/release/telegram_channel.wasm \
   ~/.ironclaw/channels/telegram.wasm
```

## Level 1 — WASM unit tests

No runtime, no DB, no network. Should pass in under 10 seconds.

```bash
cargo test --manifest-path channels-src/telegram/Cargo.toml -- --nocapture
```

**Passes?** Proceed to Level 2. **Fails?** The Telegram Rust source has a regression — check `channels-src/telegram/src/lib.rs`.

## Level 2 — E2E message routing

Uses a fake in-process channel to verify the agent routes `message` tool calls to Telegram correctly.

```bash
cargo test --no-default-features --features libsql \
  --test e2e_telegram_message_routing -- --nocapture
```

**Passes?** Proceed to Level 3. **Fails?** Look at `tests/e2e_telegram_message_routing.rs` — likely a change in `OutgoingResponse` shape or the `message` tool dispatcher.

## Level 3 — Full auth + webhook integration

Requires the WASM binary to be built at `channels-src/telegram/target/wasm32-wasip2/release/telegram_channel.wasm` (or a worktree sibling). Runs a fake Telegram API server and exercises the full WASM channel runtime.

```bash
# Build WASM if not already done
cargo build --manifest-path channels-src/telegram/Cargo.toml --target wasm32-wasip2 --release

# Run all auth integration tests
cargo test --features integration \
  --test telegram_auth_integration -- --nocapture
```

Key scenarios covered:
- `dm_policy` enforcement (`pairing` / `open` / `allowlist`)
- `allow_from` / `owner_id` checks in group and private chats
- Duplicate `update_id` deduplication
- Attachments (documents, photos, voice)
- Long-message splitting

**Passes?** Bot channel is healthy. **Fails?** Check which test fails for the specific auth or routing behaviour that regressed.

## Level 4 — Thread-scope regression (targeted)

Single test that prevents chat_id vs thread scope confusion (past regression):

```bash
cargo test --features integration \
  --test telegram_auth_integration \
  test_private_messages_use_chat_id_as_thread_scope -- --exact --nocapture
```

## Validate bot token

Quick API check without running any Rust code:

```bash
curl -s "https://api.telegram.org/bot$(grep TELEGRAM_BOT_TOKEN ~/.ironclaw/.env | cut -d= -f2)/getMe" | python3 -m json.tool
```

A healthy response contains `"ok": true` and the bot's `username`.

## Windows-specific note

Smart App Control may block fresh Rust test executables. If `cargo test` exits with `os error 4551` or similar:

1. Use Docker as the validation path: `docker compose up -d --build ironclaw`
2. Or follow `docs/plans/2026-04-14-windows-rust-runtime-unblock.md` and `scripts/sign-rust-artifacts.ps1`

## When everything passes but the bot still doesn't respond

Check runtime config in the workspace state:

```bash
# Using ironclaw CLI
ironclaw memory read channels/telegram/state/dm_policy
ironclaw memory read channels/telegram/state/allow_from
ironclaw memory read channels/telegram/state/last_update_id
```

If `dm_policy` is `allowlist` and `allow_from` is `[]`, all messages are dropped. Re-run the channel setup wizard (`ironclaw setup`) to repopulate.
