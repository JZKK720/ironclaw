---
description: "Scaffold a new WASM channel from scratch for IronClaw. Use when adding a new chat platform integration (Discord, WhatsApp, Signal, etc.) as a WASM component."
---

# Scaffold a New WASM Channel

Reference: [src/channels/wasm/CLAUDE context](../../src/channels/wasm/), existing example: `channels-src/telegram/`

## Step 1 — Create the channel crate

```bash
cargo new channels-src/<name> --lib
```

Update `channels-src/<name>/Cargo.toml`:
```toml
[package]
name = "<name>-channel"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
wit-bindgen = "0.43"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
```

## Step 2 — Implement the WIT bindings

Copy the WIT interface from `wit/` and implement the channel protocol in `channels-src/<name>/src/lib.rs`.

Key entry points to implement:
- `init(config: Config) -> Result<(), String>` — validate config, store state
- `on_message(raw: &str) -> Result<Option<OutgoingResponse>, String>` — parse platform webhook, return response
- `send(response: OutgoingResponse) -> Result<(), String>` — deliver message back to user

Look at `channels-src/telegram/src/lib.rs` as the canonical example.

## Step 3 — Create the capabilities file

Create `channels-src/<name>/<name>.capabilities.json`:
```json
{
  "name": "<name>",
  "version": "0.1.0",
  "http": {
    "allowed_domains": ["api.<platform>.com"],
    "rate_limit": { "requests_per_minute": 60 }
  },
  "secrets": ["<NAME>_BOT_TOKEN"],
  "default_config": {
    "dm_policy": "pairing"
  }
}
```

## Step 4 — Build the WASM binary

```bash
# Linux/macOS
cd channels-src/<name>
cargo build --target wasm32-wasip2 --release

# Windows — use Docker
docker compose exec ironclaw bash -c "cd channels-src/<name> && cargo build --target wasm32-wasip2 --release"
```

## Step 5 — Install locally

```bash
cp channels-src/<name>/target/wasm32-wasip2/release/<name>_channel.wasm \
   ~/.ironclaw/channels/<name>.wasm
cp channels-src/<name>/<name>.capabilities.json \
   ~/.ironclaw/channels/
```

## Step 6 — Register in the host

Check `src/channels/wasm/bundled.rs` — if the channel should be discovered automatically, add an entry here. Otherwise it's loaded dynamically by name.

Verify `src/channels/wasm/setup.rs` can resolve the channel name correctly.

## Step 7 — Add tests

Create unit tests in `channels-src/<name>/src/lib.rs` that cover:
- Config parsing (including optional/numeric field edge cases — see Telegram for the `owner_id` numeric deserialization pattern)
- Message parsing for each platform event type
- Auth/signature verification

## Step 8 — Smoke test

After starting the agent with the new channel installed, run:
```bash
cargo test --manifest-path channels-src/<name>/Cargo.toml -- --nocapture
```

Then trigger a real message via the platform to confirm the full round-trip.
