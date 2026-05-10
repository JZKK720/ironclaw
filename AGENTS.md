# Agent Rules

## Purpose and Precedence

- `AGENTS.md` is the quick-start contract for coding agents. It is not the full architecture spec.
- Read the relevant subsystem spec before changing a complex area. When a repo spec exists, treat it as authoritative.
- Start with these deeper docs as needed:
  - `CLAUDE.md`
  - `src/agent/CLAUDE.md`
  - `src/channels/web/CLAUDE.md`
  - `src/db/CLAUDE.md`
  - `src/llm/CLAUDE.md`
  - `src/setup/README.md`
  - `src/tools/README.md`
  - `src/workspace/README.md`
  - `src/NETWORK_SECURITY.md`
  - `tests/e2e/CLAUDE.md`

## Project Overview

IronClaw is a secure personal AI assistant written in Rust. It is designed to run locally (or on your own infrastructure), keeping all data under user control with encrypted local storage and zero telemetry. The project supports multiple LLM providers, multi-channel messaging (Telegram, Slack, Discord, web gateway, REPL, TUI), sandboxed tool execution via WASM and Docker, persistent memory with hybrid search, and background automation via routines.

The repository is a Cargo workspace with the main binary at the root and several supporting crates under `crates/`. It also contains WASM extension sources under `channels-src/` and `tools-src/`.

## Technology Stack

- **Language:** Rust (edition 2024, minimum version 1.92)
- **Async runtime:** Tokio (multi-thread)
- **Web framework:** Axum (gateway), Tower (middleware)
- **WebSocket/SSE:** tokio-tungstenite, eventsource-stream
- **Database:** Dual backend — PostgreSQL 15+ with pgvector (default) and libSQL/Turso (embedded)
- **Migrations:** refinery (PostgreSQL), incremental SQL (libSQL)
- **Serialization:** serde, serde_json, toml
- **LLM integration:** rig-core (OpenAI, Anthropic, Ollama), plus native providers for NEAR AI, AWS Bedrock, GitHub Copilot, OpenAI Codex
- **WASM runtime:** wasmtime with component-model support
- **Docker sandbox:** bollard (Docker API client)
- **Cryptography:** aes-gcm, hkdf, hmac, sha2, blake3, ed25519-dalek
- **Embeddings:** OpenAI, AWS Bedrock, or local providers
- **Vector search:** pgvector (PostgreSQL) or libsql_vector_idx (libSQL)
- **Full-text search:** PostgreSQL tsvector/ts_rank_cd or SQLite FTS5
- **Testing:** Built-in Rust tests, pytest + Playwright for E2E browser tests
- **CI/CD:** GitHub Actions, cargo-dist for releases
- **Release targets:** Linux (x86_64, aarch64, glibc + musl), macOS (x86_64, aarch64), Windows (x86_64 MSI + zip)

## Architecture Mental Model

- **Channels** normalize external input into `IncomingMessage`; `ChannelManager` merges all active channel streams.
- **Agent** owns session/thread/turn handling, submission parsing, the LLM/tool loop, approvals, routines, and background runtime behavior.
- **AppBuilder** (`src/app.rs`) is the composition root that wires database, secrets, LLMs, tools, workspace, extensions, skills, hooks, and cost controls before the agent starts.
- The **web gateway** is a browser-facing API/UI layered on top of the same agent/session/tool systems, not a separate product path.
- **Ownership model:** Single-user system with explicit instance owner scope for persistent routines, secrets, jobs, settings, extensions, and workspace memory.

### Key Data Model

```
Session (per user)
└── Thread (per conversation — can have many)
    └── Turn (per request/response pair)
        ├── user_input: String
        ├── response: Option<String>
        ├── tool_calls: Vec<ToolCall>
        └── state: TurnState (Pending | Running | Complete | Failed)
```

### Network Surfaces

| Listener | Default Port | Default Bind | Auth |
|----------|-------------|-------------|------|
| Web Gateway | 3000 | `127.0.0.1` | Bearer token (constant-time) |
| HTTP Webhook Server | 8080 | `0.0.0.0` | Shared secret (body field) |
| Orchestrator Internal API | 50051 | loopback / `0.0.0.0` (Linux) | Per-job bearer token |
| OAuth Callback Listener | 9876 | `127.0.0.1` | None (ephemeral, 5-min timeout) |
| Sandbox HTTP Proxy | OS-assigned | `127.0.0.1` | None (loopback only) |

## Code Organization

### Workspace Members

| Crate | Path | Role |
|-------|------|------|
| `ironclaw` | `.` | Main binary — agent, channels, web gateway, CLI |
| `ironclaw_common` | `crates/ironclaw_common` | Shared types and utilities |
| `ironclaw_engine` | `crates/ironclaw_engine` | Thread-capability-CodeAct execution engine v2 |
| `ironclaw_gateway` | `crates/ironclaw_gateway` | Gateway frontend assets, layout, widgets |
| `ironclaw_safety` | `crates/ironclaw_safety` | Prompt injection defense, sanitization, leak detection |
| `ironclaw_skills` | `crates/ironclaw_skills` | Skill selection, scoring, catalog, registry |
| `ironclaw_tui` | `crates/ironclaw_tui` | Ratatui-based terminal UI (optional feature) |

### Main Source Modules (`src/`)

| Module | Role |
|--------|------|
| `agent/` | Core agent logic: event loop, dispatcher, session manager, scheduler, compaction, heartbeat, routines, cost guard |
| `auth/` | NEAR AI auth, OAuth flows, session tokens, device login |
| `bridge/` | Claude Code bridge (Docker sandbox worker orchestration) |
| `channels/` | Channel system: `ChannelManager`, web gateway, HTTP webhooks, WASM channel runtime, relay, Signal |
| `cli/` | CLI argument parsing, commands, formatting |
| `config/` | Configuration layer: env var loading, DB-backed settings reload, precedence (DB > env > default) |
| `context/` | Context management for agent turns |
| `db/` | Dual-backend database abstraction (PostgreSQL + libSQL) |
| `document_extraction/` | PDF and ZIP text extraction |
| `estimation/` | Token/cost estimation |
| `evaluation/` | Trace evaluation and replay testing |
| `extensions/` | Extension lifecycle: install, authenticate, activate, remove |
| `gate/` | Tool approval / gate resolution system |
| `history/` | PostgreSQL store/repository layer (conversations, jobs, routines) |
| `hooks/` | Hook registry and bootstrap hooks |
| `llm/` | Multi-provider LLM integration, circuit breaker, retry, failover, caching |
| `observability/` | Tracing, metrics, health checks |
| `orchestrator/` | Docker sandbox orchestrator API |
| `ownership/` | Typed identities, DB-backed pairing, ownership cache |
| `pairing/` | Channel pairing (DM ownership claim flow) |
| `registry/` | Extension registry (WASM tools, channels, MCP servers) |
| `safety/` | Safety layer integration (delegates to `ironclaw_safety` crate) |
| `sandbox/` | Docker sandbox execution, proxy, reaper |
| `secrets/` | Encrypted secrets storage, keychain integration, credential injection |
| `setup/` | Onboarding wizard (database, security, LLM, channels, extensions) |
| `skills/` | Skill loading and runtime integration |
| `testing/` | Test infrastructure and helpers |
| `tools/` | Tool registry, built-in tools, WASM tool runtime, MCP client, builder |
| `tunnel/` | Network tunnel support |
| `webhooks/` | Webhook routing and state |
| `worker/` | Background job worker, container worker, job delegate |
| `workspace/` | Persistent memory: filesystem-like storage, hybrid search (FTS + vector), embeddings |

### WASM Extension Sources

- `channels-src/<name>/` — Sandboxable channel implementations (Telegram, Slack, Discord, WhatsApp, Feishu)
- `tools-src/<name>/` — Sandboxable tool implementations (GitHub, Gmail, Google suite, Slack, Telegram, web-search, Composio, llm-context)
- `wit/tool.wit` — WIT interface for WASM tools
- `wit/channel.wit` — WIT interface for WASM channels

## Build and Test Commands

### Basic Build

```bash
# Development build (default: PostgreSQL + libSQL + TUI + html-to-markdown)
cargo build

# Release build
cargo build --release

# Full release with bundled WASM channels
./scripts/build-all.sh
```

### Feature-Specific Builds

```bash
# libSQL only (no PostgreSQL)
cargo build --no-default-features --features libsql

# All product features (no test-only integration feature)
cargo build --no-default-features --features postgres,libsql,html-to-markdown,bedrock,import

# With AWS Bedrock support
cargo build --features bedrock

# With TUI (default)
cargo build --features tui
```

### Testing

```bash
# Unit tests only (no external services required)
cargo test

# Integration tests (requires PostgreSQL)
cargo test --features integration

# Heavy integration tests (separate CI job)
cargo test --no-default-features --features libsql,integration --test e2e_thread_scheduling

# Specific test file
cargo test --test workspace_integration

# Live tests (requires PostgreSQL + LLM API keys)
cargo test --features integration -- --ignored

# Check architecture boundaries
bash scripts/check-boundaries.sh
```

### E2E Tests (Python/Playwright)

```bash
cd tests/e2e
python -m venv .venv
source .venv/bin/activate  # .venv\Scripts\activate on Windows
pip install -e .
playwright install chromium
pytest scenarios/
```

### Code Quality

```bash
# Formatting
cargo fmt --all -- --check

# Clippy (zero warnings policy)
cargo clippy --all --benches --tests --examples --all-features -- -D warnings

# Cargo deny (license/advisory check)
cargo deny check

# Panic check in production code
python scripts/check_no_panics.py
```

## Code Style Guidelines

- **Edition:** Rust 2024, minimum toolchain 1.92.
- **Clippy:** Must pass with zero warnings (`-D warnings`).
- **Formatting:** Use `cargo fmt`.
- **Error handling:** Avoid `.unwrap()` and `.expect()` in production; prefer proper error handling. They are acceptable in tests and for truly infallible invariants (e.g., literals/regexes) with a safety comment.
- **Imports:** Prefer `crate::` imports for cross-module references.
- **Types:** Use strong types and enums over stringly-typed control flow when the shape is known.
- **Feature flags:** Keep feature-flag branching inside the module that owns the abstraction whenever possible.
- **Module ownership:** Keep `src/main.rs` and `src/app.rs` orchestration-focused. Do not move module-owned logic into entrypoints. Module-specific initialization should live in the owning module behind a public factory/helper.

## Testing Instructions

### Test Tiers

| Tier | Command | External deps |
|------|---------|---------------|
| Unit | `cargo test` | None |
| Integration | `cargo test --features integration` | Running PostgreSQL |
| Live | `cargo test --features integration -- --ignored` | PostgreSQL + LLM API keys |

### Key Testing Rules

- Unit tests live in `mod tests {}` at the bottom of each file.
- Async tests use `#[tokio::test]`.
- Prefer real implementations or stubs over mocks.
- Use the `tempfile` crate for test directories; never hardcode `/tmp/`.
- Every bug fix must include a regression test (enforced by commit-msg hook).
- **Test through the caller, not just the helper.** When a predicate/classifier/transform helper gates a side effect (HTTP, DB write, OAuth flow, UI mutation, tool execution) and has any wrapper or computed input between it and that side effect, a unit test on the helper alone is not sufficient regression coverage. Add a test that drives the actual call site (`*_handler`, `factory::create_*`, `manager::*`) at the integration tier or higher. See `.claude/rules/testing.md` for the full rule and bug examples.
- Integration tests requiring external services must be gated behind `#![cfg(all(feature = "postgres", feature = "integration"))]`.
- Tests must fail loudly when prerequisites are missing; do not silently skip with `try_connect().is_none() { return; }` patterns.

### Test Infrastructure

- `tests/e2e/` — Python/Playwright browser automation tests against a live ironclaw instance.
- `tests/fixtures/` — Test data and traces.
- `tests/support/` — Shared Rust test helpers.
- `testcontainers-modules` is used for PostgreSQL integration tests.
- `insta` is used for snapshot testing.

## Security Considerations

### Threat Model

IronClaw operates across four trust boundaries:

| Boundary | Trust Level | Examples |
|----------|------------|---------|
| Local user | Fully trusted | TUI, web gateway (loopback), CLI commands |
| Browser client | Authenticated | Web UI connected via bearer token; subject to CORS, Origin validation, CSRF protections |
| Docker containers | Untrusted (sandboxed) | Worker containers executing user jobs; isolated via per-job tokens, allowlisted egress, dropped capabilities |
| External services | Untrusted | Webhook senders (Telegram, Slack); authenticated via shared secret |

### Critical Security Rules

- **Review any change touching listeners, routes, auth, secrets, sandboxing, approvals, or outbound HTTP with a security mindset.**
- Do not weaken bearer-token auth, webhook auth, CORS/origin checks, body limits, rate limits, allowlists, or secret-handling guarantees.
- Treat Docker containers and external services as untrusted.
- Session/thread/turn state matters. Submission parsing happens before normal chat handling.
- Skills are selected deterministically. Tool approval and auth flows are special paths and must not be mixed into normal chat history carelessly.
- Persistent memory is the workspace system, not just transcript storage; preserve file-like semantics, chunking/search behavior, and identity/system-prompt loading.

### Secrets and Credentials

- Secrets are encrypted at rest using AES-GCM with a master key.
- The master key is stored in the OS keychain (macOS) or environment variable (`SECRETS_MASTER_KEY`).
- **Zero-exposure model:** WASM tools and Docker containers never see raw credential values. Credentials are injected at the host boundary (HTTP proxy or env var injection) at transit time.
- Secret leak detection scans tool outputs and LLM responses for 15+ secret patterns.

### Sandbox Security

- **WASM sandbox:** Untrusted tools run in wasmtime with component-model isolation. Fresh instance per execution. Capabilities are opt-in via `capabilities.json`.
- **Docker sandbox:** Per-job tokens, network allowlisting, dropped capabilities, and orchestrator/worker pattern. Containers are treated as adversarial.
- **HTTP proxy for sandbox:** All outbound HTTP from sandboxed tools goes through a host-side proxy that injects credentials and scans responses for leaks.

## Database Rules

- **All new persistence behavior must support both PostgreSQL and libSQL.**
- Add new DB operations to the shared `Database` trait first, then implement both backends.
- The `Database` supertrait is composed of seven sub-traits (`ConversationStore`, `JobStore`, `SandboxStore`, `RoutineStore`, `ToolFailureStore`, `SettingsStore`, `WorkspaceStore`). Leaf consumers should depend on the narrowest sub-trait they need.
- **Migration numbering:** Always base your migration number on what is already in `origin/main` or `origin/staging`, not your local branch. Migrations that have reached staging may already be deployed to production. Never reuse or insert before an existing version number.
- PostgreSQL migrations live in `migrations/VN__description.sql` (managed by refinery).
- libSQL migrations are consolidated in `src/db/libsql_migrations.rs` as incremental `INCREMENTAL_MIGRATIONS`.

## Configuration and Setup

- **Config precedence:** DB-backed settings > environment variables > defaults.
- **Bootstrap layer:** `~/.ironclaw/.env` stores bootstrap vars like `DATABASE_BACKEND`. Loaded before `Config::from_env()`.
- **Profiles:** `profiles/local.toml`, `profiles/server.toml`, etc. Loaded via `IRONCLAW_PROFILE` env var.
- **Onboarding:** `ironclaw onboard` runs a wizard. First-run auto-detection triggers quick mode when no database is configured. Use `--no-onboard` to suppress.
- Do not break config precedence, bootstrap env loading, DB-backed config reload, or post-secrets LLM re-resolution.

## Extension and Tool Development

### Built-in Tools (Rust)

1. Create `src/tools/builtin/my_tool.rs`
2. Implement the `Tool` trait
3. Add `mod my_tool;` and `pub use` in `src/tools/builtin/mod.rs`
4. Register in `ToolRegistry::register_builtin_tools()` in `registry.rs`
5. Add tests

### WASM Tools (Recommended)

1. Create a new crate in `tools-src/<name>/`
2. Implement the WIT interface (`wit/tool.wit`)
3. Create `<name>.capabilities.json` declaring required permissions
4. Build with `cargo build --target wasm32-wasip2 --release`
5. Install with `ironclaw tool install path/to/tool.wasm`

### WASM Channels

1. Create a new crate in `channels-src/<name>/`
2. Implement the WIT interface (`wit/channel.wit`)
3. Build with `cargo build --target wasm32-wasip2 --release`

### MCP Servers

Connect to external Model Context Protocol servers for additional capabilities. MCP server URLs are operator-configured and treated as trusted destinations.

## Release Alignment Workflow

- `origin/main` is the promoted runtime baseline and the only push target. `upstream` points at `nearai/ironclaw` and is fetch-only; never plan or execute pushes to `upstream`.
- If local git config exposes a push URL for `upstream`, treat it as accidental capability and do not use it. Keep all publishing on `origin/main`.
- Before proposing update work, compare `origin/main` with `upstream/main` and `upstream/staging`, then selectively pull in missing upstream commits.
- For fresh-install or rebuild work, treat `upstream/staging` as the clean baseline candidate.
- Assume historical Docker/setup/polling/cutover patches are disposable until proven necessary on the fresh baseline. Prefer replaying the smallest verified subset over preserving legacy compatibility changes.
- When the running container and local git history disagree, verify which checkout and commit the container actually mounts before changing code. Use container labels, mounts, `docker-compose.yml`, `docker-compose.build.yml`, `docker-compose.override.yml`, `scripts/bootstrap.sh`, and `scripts/Bootstrap.ps1` as the runtime source-of-truth references.
- Record which upstream commits were cherry-picked, skipped, or deferred when staging diverges from main, and which fork-local commits were intentionally kept or dropped during rebuild work.

## Risk and Change Discipline

- Keep changes scoped; avoid broad refactors unless the task truly requires them.
- Security, database schema, runtime, worker, CI, and secrets changes are high-risk. Call out rollback risks, compatibility concerns, and hidden side effects.
- Preserve existing defaults unless the task explicitly changes them.
- Avoid unrelated file churn and generated-file edits unless required.
- Respect a dirty worktree and never revert user changes you did not make.

## Before Finishing

- Confirm whether behavior changes require updates to `FEATURE_PARITY.md`, specs, API docs, or `CHANGELOG.md`.
- Run the most targeted tests/checks that cover the change.
- Re-check security-sensitive paths when touching auth, secrets, network listeners, sandboxing, or approvals.
- Keep the final diff scoped to the task.
