# IronClaw — Copilot Instructions

IronClaw is a secure, self-expanding personal AI assistant written in Rust (tokio async, axum, wasmtime). See [AGENTS.md](../AGENTS.md) for the authoritative agent contract and [CLAUDE.md](../CLAUDE.md) for the full development guide.

## Build & Test

```bash
cargo fmt
cargo clippy --all --benches --tests --examples --all-features  # zero warnings required
cargo test                                        # unit tests
cargo test --features integration                 # + PostgreSQL tests
RUST_LOG=ironclaw=debug cargo run                 # run with logging
```

**Windows — Smart App Control blocks freshly compiled binaries.** Use Docker as the authoritative build path:
```powershell
docker compose up -d --build ironclaw
```

## Docker Build Modes

- For deploy-like validation, stay in pull mode: `docker compose pull` and then `docker compose up -d --no-build postgres ironclaw`.
- `ironclaw-worker` is still a required runtime image for orchestrated job containers, but its compose service is build-only; do not start it with `docker compose up` unless you are explicitly testing that image build.
- Engine v2 `/project/` sandboxing is a different container path driven by [crates/Dockerfile.sandbox](../crates/Dockerfile.sandbox) and [docs/plans/2026-04-10-engine-v2-sandbox.md](../docs/plans/2026-04-10-engine-v2-sandbox.md). Do not remove `Dockerfile.worker` or the `SANDBOX_IMAGE` path without first auditing [src/config/sandbox.rs](../src/config/sandbox.rs), [src/orchestrator/job_manager.rs](../src/orchestrator/job_manager.rs), [src/cli/mod.rs](../src/cli/mod.rs), and [src/bridge/sandbox/](../src/bridge/sandbox/).

## Non-Negotiable Invariants

| Rule | Scope |
|------|-------|
| No `.unwrap()` / `.expect()` in production code | All `src/` |
| Zero clippy warnings — fix before committing | All changes |
| All mutations from handlers/CLI go through `ToolDispatcher::dispatch()` | Handlers, CLI, channels |
| New DB features must support both PostgreSQL **and** libSQL | `src/db/`, `migrations/` |
| Check `FEATURE_PARITY.md` when any tracked behavior changes | All PRs |
| Regression test with every bug fix | All PRs |
| Use `crate::` for cross-module imports, `super::` only intra-module | All `src/` |

## Module Specs (read before touching a subsystem)

| Subsystem | Spec |
|-----------|------|
| `src/agent/` | [src/agent/CLAUDE.md](../src/agent/CLAUDE.md) |
| `src/channels/web/` | [src/channels/web/CLAUDE.md](../src/channels/web/CLAUDE.md) |
| `src/db/` | [src/db/CLAUDE.md](../src/db/CLAUDE.md) |
| `src/llm/` | [src/llm/CLAUDE.md](../src/llm/CLAUDE.md) |
| `src/tools/` | [src/tools/README.md](../src/tools/README.md) |
| `src/workspace/` | [src/workspace/README.md](../src/workspace/README.md) |
| `crates/ironclaw_engine/` | [crates/ironclaw_engine/CLAUDE.md](../crates/ironclaw_engine/CLAUDE.md) |

## Extracted Crates

Safety logic lives in `crates/ironclaw_safety/`; skills in `crates/ironclaw_skills/`. Import directly — `src/safety/mod.rs` and `src/skills/mod.rs` are thin shims that no longer glob-re-export. Use `use ironclaw_safety::SafetyLayer` not `crate::safety::SafetyLayer`.

## Subsystem Rules (auto-applied by file pattern)

Detailed rules live in [.claude/rules/](../.claude/rules/) and are surfaced as VS Code instructions:

- [database.instructions.md](instructions/database.instructions.md) → `src/db/**`, `migrations/**`
- [testing.instructions.md](instructions/testing.instructions.md) → `src/**/*.rs`, `tests/**`
- [tools-and-dispatch.instructions.md](instructions/tools-and-dispatch.instructions.md) → `src/tools/**`, `src/channels/**`, `src/cli/**`
- [safety-and-sandbox.instructions.md](instructions/safety-and-sandbox.instructions.md) → `src/safety/**`, `src/sandbox/**`, `src/secrets/**`
- [ci-cd.instructions.md](instructions/ci-cd.instructions.md) → `.github/workflows/**`, `Dockerfile*`, `docker-compose.yml`
- [telegram-channel.instructions.md](instructions/telegram-channel.instructions.md) → `channels-src/telegram/**`

## Useful Prompts

| Prompt | Purpose |
|--------|---------|
| `/smoke-test-telegram` | Smoke-test the Telegram WASM channel end-to-end |
| `/check-pr-ready` | Run the pre-commit discipline checklist before opening a PR |
| `/sync-upstream` | Step-by-step guide to manually merge upstream/main into fork/main |
| `/validate-ghcr-upgrade` | Audit whether upstream changes are safe to publish to fork GHCR and whether downstream update/install channels will actually pick them up |
| `/validate-installer-release-channel` | Audit whether PowerShell, shell, MSI, cargo-dist releases, and embedded registry URLs actually resolve to the fork-owned release channel |
| `/add-wasm-channel` | Scaffold a new WASM channel from scratch |
