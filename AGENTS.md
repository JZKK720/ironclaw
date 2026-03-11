# Agent Rules for IronClaw

## Project Overview

**IronClaw** is a secure personal AI assistant written in Rust, developed by NEAR AI. It is designed with a security-first philosophy: your data stays local, encrypted, and under your control.

### Key Design Principles

- **User-first security** - All data stored locally, encrypted, with no telemetry
- **Self-expanding capabilities** - Build new WASM tools on the fly without vendor updates
- **Defense in depth** - Multiple security layers: WASM sandbox, prompt injection defense, credential leak detection
- **Multi-channel access** - REPL, HTTP webhooks, WASM channels (Telegram, Signal), Web Gateway with SSE/WebSocket
- **Proactive execution** - Background heartbeat and routine-based automation

### Architecture Highlights

```
┌────────────────────────────────────────────────────────────────┐
│                          Channels                              │
│  ┌──────┐  ┌──────┐   ┌─────────────┐  ┌─────────────┐         │
│  │ REPL │  │ HTTP │   │WASM Channels│  │ Web Gateway │         │
│  └──┬───┘  └──┬───┘   └──────┬──────┘  │ (SSE + WS)  │         │
│     │         │              │         └──────┬──────┘         │
│     └─────────┴──────────────┴────────────────┘                │
│                              │                                 │
│                    ┌─────────▼─────────┐                       │
│                    │    Agent Loop     │  Intent routing       │
│                    └────┬──────────┬───┘                       │
│                         │          │                           │
│              ┌──────────▼────┐  ┌──▼───────────────┐           │
│              │  Scheduler    │  │ Routines Engine  │           │
│              │(parallel jobs)│  │(cron, event, wh) │           │
│              └──────┬────────┘  └────────┬─────────┘           │
│                     │                    │                     │
│       ┌─────────────┼────────────────────┘                     │
│       │             │                                          │
│   ┌───▼─────┐  ┌────▼────────────────┐                         │
│   │ Local   │  │    Orchestrator     │                         │
│   │Workers  │  │  ┌───────────────┐  │                         │
│   │(in-proc)│  │  │ Docker Sandbox│  │                         │
│   └───┬─────┘  │  │   Containers  │  │                         │
│       │        │  │ ┌───────────┐ │  │                         │
│       │        │  │ │Worker / CC│ │  │                         │
│       │        │  │ └───────────┘ │  │                         │
│       │        │  └───────────────┘  │                         │
│       │        └─────────┬───────────┘                         │
│       └──────────────────┤                                     │
│                          │                                     │
│              ┌───────────▼──────────┐                          │
│              │    Tool Registry     │                          │
│              │  Built-in, MCP, WASM │                          │
│              └──────────────────────┘                          │
└────────────────────────────────────────────────────────────────┘
```

## Technology Stack

| Component | Technology |
|-----------|------------|
| Language | Rust 1.92+ (Edition 2024) |
| Async Runtime | Tokio |
| HTTP Server | Axum (Web Gateway), Hyper (sandbox proxy) |
| Database | PostgreSQL 15+ with pgvector (default) OR libSQL/Turso (embedded) |
| WASM Runtime | Wasmtime with component model |
| LLM Integration | rig-core (multi-provider abstraction) |
| Container Runtime | Docker (for sandbox execution) |
| Serialization | serde, serde_json |
| Error Handling | thiserror, anyhow |
| Logging | tracing, tracing-subscriber |
| Cryptography | AES-256-GCM, HKDF, HMAC, SHA2, BLAKE3 |
| Build Tool | Cargo with custom build.rs |

## Project Structure

```
src/
├── main.rs              # Entry point, CLI args, startup orchestration
├── lib.rs               # Library root, module declarations
├── app.rs               # AppBuilder for component initialization
├── bootstrap.rs         # Base directory (~/.ironclaw), .env loading
├── boot_screen.rs       # Startup status display
├── settings.rs          # User settings persistence
├── service.rs           # OS service management (launchd/systemd)
├── tracing_fmt.rs       # Custom tracing formatter
├── util.rs              # Shared utilities
├── testing.rs           # Test utilities
│
├── agent/               # Core agent loop, scheduler, sessions
│   ├── agent_loop.rs    # Main message handling loop
│   ├── scheduler.rs     # Parallel job execution
│   ├── worker.rs        # Job execution with LLM reasoning
│   ├── router.rs        # Intent classification
│   ├── session.rs       # Turn-based session management
│   ├── session_manager.rs
│   ├── routine*.rs      # Scheduled/reactive background tasks
│   ├── heartbeat.rs     # Proactive periodic execution
│   ├── self_repair.rs   # Stuck job detection and recovery
│   └── ...
│
├── channels/            # Multi-channel input system
│   ├── channel.rs       # Channel trait
│   ├── manager.rs       # ChannelManager merges streams
│   ├── repl.rs          # Interactive REPL
│   ├── http.rs          # HTTP webhook channel
│   ├── webhook_server.rs # Unified webhook server
│   ├── signal.rs        # Signal messenger integration
│   ├── wasm/            # WASM channel runtime
│   │   ├── runtime.rs   # Wasmtime-based execution
│   │   ├── loader.rs    # Dynamic loading
│   │   ├── host.rs      # Host functions
│   │   └── ...
│   └── web/             # Web gateway (browser UI)
│       ├── server.rs    # Axum server
│       ├── handlers/    # API endpoints
│       ├── sse.rs       # Server-Sent Events
│       └── ws.rs        # WebSocket support
│
├── cli/                 # CLI subcommands (clap)
│   ├── mod.rs           # Cli struct, Command enum
│   ├── config.rs        # Configuration management
│   ├── tool.rs          # Tool CLI commands
│   ├── registry.rs      # Extension registry commands
│   ├── mcp.rs           # MCP protocol commands
│   ├── memory.rs        # Memory/workspace CLI
│   ├── pairing.rs       # Channel pairing commands
│   ├── service.rs       # OS service installation
│   ├── doctor.rs        # Diagnostics
│   └── ...
│
├── config/              # Environment-based configuration
│   ├── mod.rs           # Top-level Config struct
│   ├── agent.rs, llm.rs, channels.rs, database.rs
│   ├── sandbox.rs, skills.rs, heartbeat.rs, routines.rs
│   └── ...
│
├── db/                  # Dual-backend persistence
│   ├── mod.rs           # Database trait
│   ├── postgres.rs      # PostgreSQL implementation
│   └── libsql/          # libSQL/Turso implementation
│
├── llm/                 # Multi-provider LLM integration
│   ├── provider.rs      # LlmProvider trait
│   ├── rig_adapter.rs   # rig-core integration
│   ├── nearai_chat.rs   # NEAR AI provider
│   ├── anthropic_oauth.rs
│   ├── bedrock.rs       # AWS Bedrock (optional feature)
│   └── ...
│
├── tools/               # Extensible tool system
│   ├── tool.rs          # Tool trait, ToolOutput
│   ├── registry.rs      # ToolRegistry
│   ├── builtin/         # Built-in tools (file, shell, memory, http, etc.)
│   ├── wasm/            # WASM sandbox for untrusted tools
│   ├── mcp/             # Model Context Protocol client
│   └── builder/         # Dynamic tool building
│
├── workspace/           # Persistent memory with hybrid search
│   ├── search.rs        # FTS + vector search (RRF)
│   ├── embeddings.rs    # Vector embedding generation
│   └── ...
│
├── safety/              # Prompt injection defense
│   ├── sanitizer.rs     # Pattern detection, content escaping
│   ├── leak_detector.rs # Secret exfiltration detection
│   ├── validator.rs     # Input validation
│   └── policy.rs        # Policy rules with severity levels
│
├── secrets/             # Encryption and keychain
│   ├── crypto.rs        # AES-256-GCM encryption
│   ├── keychain.rs      # OS keychain integration
│   └── store.rs         # Secrets store
│
├── sandbox/             # Docker container management
│   ├── container.rs     # Container lifecycle
│   ├── proxy/           # Network proxy with allowlist
│   └── ...
│
├── orchestrator/        # Internal API for sandbox containers
│   ├── api.rs           # Axum endpoints for LLM proxy, events
│   ├── auth.rs          # Per-job bearer token store
│   └── job_manager.rs   # Container lifecycle
│
├── worker/              # Runs inside Docker containers
│   ├── runtime.rs       # Worker execution loop
│   ├── claude_bridge.rs # Claude Code integration
│   └── proxy_llm.rs     # LLM proxy through orchestrator
│
├── skills/              # SKILL.md prompt extension system
├── hooks/               # Lifecycle hooks (6 points)
├── registry/            # Extension registry catalog
├── extensions/          # Extension manager
├── context/             # Job context isolation
├── estimation/          # Cost/time/value estimation with EMA learning
├── evaluation/          # Success evaluation
├── history/             # Persistence and analytics
├── tunnel/              # Public exposure (Cloudflare, ngrok, Tailscale)
├── transcription/       # Audio transcription
└── observability/       # Event/metric recording

tests/                   # Integration tests
├── support/             # Test utilities
├── e2e/                 # Python/Playwright E2E tests
└── *.rs                 # Rust integration tests

channels-src/            # WASM channel source code
├── telegram/            # Telegram channel (MTProto)
└── ...                  # Other channel implementations

registry/                # Bundled extension registry
├── tools/               # Tool manifests
└── channels/            # Channel manifests

wit/                     # WebAssembly Interface Types
└── channel.wit          # Channel interface definition

migrations/              # Database schema migrations
```

## Build Requirements

- **Rust**: 1.92+ (specified in `Cargo.toml`)
- **WASM Target**: `wasm32-wasip2` (for channel builds)
- **Tools**: `wasm-tools` (for WASM component model)
- **Database** (optional): PostgreSQL 15+ with pgvector extension
- **Docker** (optional): For sandbox container execution

## Build Commands

```bash
# Standard development build
cargo build

# Release build (includes WASM channel compilation)
cargo build --release

# Build with all features
cargo build --release --all-features

# Check without building
cargo check
cargo check --all --benches --tests --examples --all-features

# Format code
cargo fmt --all

# Lint (zero warnings policy)
cargo clippy --all --benches --tests --examples --all-features -- -D warnings

# Run tests (see Testing section below)
cargo test
cargo test --features integration
cargo test --all-features

# Run with logging
RUST_LOG=ironclaw=debug cargo run
RUST_LOG=ironclaw=trace cargo run  # verbose

# Build WASM channels only
./scripts/build-wasm-extensions.sh

# Full release (rebuilds channels first)
./scripts/build-all.sh
```

## Developer Setup

For native development without Docker:

```bash
# Run the developer setup script
./scripts/dev-setup.sh

# Or manually:
rustup target add wasm32-wasip2
cargo install wasm-tools --locked
cargo check
cargo test
```

This script:
1. Adds the `wasm32-wasip2` target
2. Installs `wasm-tools`
3. Runs `cargo check` and `cargo test`
4. Installs git hooks for commit message validation

## Code Style Guidelines

Enforced via `clippy.toml` and CI:

- **No `.unwrap()` or `.expect()`** in production code (tests are fine)
- Use `thiserror` for error types
- Map errors with context: `.map_err(|e| SomeError::Variant { reason: e.to_string() })?`
- Prefer strong types over strings (enums, newtypes)
- Prefer `crate::` for cross-module imports; `super::` is fine in tests
- No `pub use` re-exports unless exposing to downstream consumers
- Keep functions focused, extract helpers when logic is reused
- Comments for non-obvious logic only

### Complexity Thresholds (clippy.toml)

```
cognitive-complexity-threshold = 15
too-many-lines-threshold = 100
too-many-arguments-threshold = 7
type-complexity-threshold = 250
```

## Testing Strategy

### Test Tiers

| Tier | Command | External Dependencies |
|------|---------|----------------------|
| Unit | `cargo test` | None (uses libsql temp DB) |
| Integration | `cargo test --features integration` | Running PostgreSQL |
| Live | `cargo test --features integration -- --ignored` | PostgreSQL + LLM API keys |
| E2E | `pytest tests/e2e/` | Compiled binary + Playwright |

### Test Organization

```
tests/
├── support/              # Shared test utilities
│   ├── mod.rs
│   ├── test_channel.rs   # Mock channel for tests
│   ├── instrumented_llm.rs
│   └── ...
├── e2e/                  # Python/Playwright E2E tests
│   ├── scenarios/        # Test scenarios
│   └── conftest.py       # pytest fixtures
├── workspace_integration.rs
├── wasm_channel_integration.rs
├── provider_chaos.rs     # Chaos engineering tests
└── ...
```

### Key Testing Patterns

- Unit tests in `mod tests {}` at the bottom of each file
- Async tests with `#[tokio::test]`
- No mocks, prefer real implementations or stubs
- Use `tempfile` crate for test directories, never hardcode `/tmp/`
- Regression test required with every bug fix (enforced by commit-msg hook)
- Integration tests require PostgreSQL; skipped if DB is unreachable

### Running Tests

```bash
# Unit tests only (no external deps)
cargo test

# With PostgreSQL integration tests
cargo test --features integration

# Run specific test
cargo test test_name

# Run with output
cargo test -- --nocapture

# Check test tier boundaries
./scripts/check-boundaries.sh
```

## Database

Dual-backend persistence: PostgreSQL + libSQL/Turso.

**All new persistence features must support both backends.**

### PostgreSQL (default, production)

```bash
# Local development with docker-compose
docker-compose up -d postgres

# Default connection (from docker-compose.yml)
DATABASE_URL=postgres://ironclaw:ironclaw@localhost:5433/ironclaw
```

### libSQL (development, embedded)

Used automatically when PostgreSQL is not available. No setup required.

### Database Migrations

Located in `migrations/` directory. Applied automatically on startup via `refinery`.

## Configuration

Configuration is loaded from (in order of priority):

1. **Environment variables** (highest priority)
2. **`.env` file** in project root
3. **`~/.ironclaw/.env`** (bootstrap config, mainly for DATABASE_URL)
4. **Database settings** (persisted config, loaded after DB connection)

### First-Time Setup

```bash
# Interactive onboarding wizard
ironclaw onboard

# Or with specific sections only
ironclaw onboard --provider-only
ironclaw onboard --channels-only
```

### Key Environment Variables

See `.env.example` for full list. Key variables:

```bash
# LLM Provider (required)
LLM_BACKEND=nearai  # or openai, anthropic, ollama, openai_compatible
NEARAI_MODEL=zai-org/GLM-5-FP8
NEARAI_BASE_URL=https://private.near.ai

# Or for OpenAI
OPENAI_API_KEY=sk-...

# Or for Anthropic
ANTHROPIC_API_KEY=sk-ant-...
# OR ANTHROPIC_OAUTH_TOKEN (from `claude login`)

# Database
DATABASE_URL=postgres://user:pass@localhost/ironclaw

# Agent
AGENT_NAME=ironclaw
AGENT_MAX_PARALLEL_JOBS=5

# Web Gateway
PUBLIC_GATEWAY_URL=http://localhost:3000
```

## Security Considerations

### WASM Sandbox

All untrusted tools run in isolated WebAssembly containers:

- **Capability-based permissions** - Explicit opt-in for HTTP, secrets, tool invocation
- **Endpoint allowlisting** - HTTP requests only to approved hosts/paths
- **Credential injection** - Secrets injected at host boundary, never exposed to WASM
- **Leak detection** - Scans requests/responses for secret exfiltration
- **Rate limiting** - Per-tool request limits
- **Resource limits** - Memory, CPU, and execution time constraints

### Prompt Injection Defense

External content passes through multiple security layers:

- Pattern-based detection of injection attempts
- Content sanitization and escaping
- Policy rules with severity levels (Block/Warn/Review/Sanitize)
- Tool output wrapping for safe LLM context injection

### Secrets Management

- AES-256-GCM encryption for secrets at rest
- OS keychain integration for master key (macOS Keychain, Linux secret-service)
- Master key can be overridden with `SECRETS_MASTER_KEY` env var (Docker deployments)
- Secrets never exposed to WASM tools; injected at host boundary

### Data Protection

- All data stored locally in your database
- No telemetry, analytics, or data sharing
- Full audit log of all tool executions

## Deployment

### Docker (Recommended for Production)

```bash
# Build
docker build --platform linux/amd64 -t ironclaw:latest .

# Run
docker run --env-file .env -p 3000:3000 ironclaw:latest
```

### Docker Compose (Local Development)

```bash
# Start PostgreSQL and IronClaw
docker-compose up -d

# Access URLs:
# - Web Gateway: http://localhost:3231
# - HTTP Webhook: http://localhost:8281
# - PostgreSQL: localhost:5433
```

### Windows PowerShell Scripts

```powershell
# One-click full setup
.\scripts\full-setup.ps1

# Individual steps
.\scripts\build.ps1      # Build Docker image
.\scripts\setup.ps1      # Interactive onboarding
.\scripts\start.ps1      # Start services
.\scripts\stop.ps1       # Stop services
```

### Release Builds

Releases are built with [cargo-dist](https://github.com/axodotdev/cargo-dist) and published to GitHub Releases.

Supported platforms:
- aarch64-apple-darwin (Apple Silicon macOS)
- x86_64-apple-darwin (Intel macOS)
- x86_64-unknown-linux-gnu (Linux AMD64)
- aarch64-unknown-linux-gnu (Linux ARM64)
- x86_64-pc-windows-msvc (Windows)

## Feature Flags

| Feature | Default | Description |
|---------|---------|-------------|
| `postgres` | ✅ | PostgreSQL database support |
| `libsql` | ✅ | libSQL/Turso embedded database support |
| `html-to-markdown` | ✅ | HTML to Markdown conversion tools |
| `bedrock` | ❌ | AWS Bedrock LLM provider |
| `integration` | ❌ | Integration tests requiring PostgreSQL |

## CI/CD Workflows

### Pull Request Checks

- **test.yml**: Unit tests (multiple feature combinations), Windows build check, WASM WIT compatibility, Docker build
- **code_style.yml**: Formatting (rustfmt) and linting (clippy on Linux and Windows)
- **e2e.yml**: Python/Playwright E2E tests (runs when web gateway or e2e tests change)

### Release Process

- **release.yml**: Triggered on version tags, builds artifacts with cargo-dist
- **release-plz.yml**: Automated version bumping and release PRs

### Other Workflows

- **coverage.yml**: Code coverage reporting
- **staging-ci.yml**: Staging branch validation

## Module Specifications

Several modules have detailed specification files that should be read before modifying:

| Module | Spec |
|--------|------|
| `src/agent/` | `src/agent/CLAUDE.md` |
| `src/channels/web/` | `src/channels/web/CLAUDE.md` |
| `src/db/` | `src/db/CLAUDE.md` |
| `src/llm/` | `src/llm/CLAUDE.md` |
| `src/setup/` | `src/setup/README.md` |
| `src/tools/` | `src/tools/README.md` |
| `src/workspace/` | `src/workspace/README.md` |
| `tests/e2e/` | `tests/e2e/CLAUDE.md` |
| Safety/Sandbox | `.claude/rules/safety-and-sandbox.md` |
| Testing | `.claude/rules/testing.md` |
| Skills | `.claude/rules/skills.md` |
| Database | `.claude/rules/database.md` |

## Git Hooks

Installed by `scripts/dev-setup.sh`:

- **commit-msg**: Enforces regression test references in commit messages for bug fixes
- **pre-commit**: Checks for UTF-8, case-sensitivity issues, `/tmp` usage, and credential redaction

## Common Tasks

### Adding a New LLM Provider

1. Add config in `src/config/llm.rs`
2. Implement provider in `src/llm/`
3. Update `docs/LLM_PROVIDERS.md`
4. Add to `LlmBackend` enum

### Adding a New Channel

1. Create `src/channels/my_channel.rs`
2. Implement the `Channel` trait
3. Add config in `src/config/channels.rs`
4. Wire up in `src/main.rs` channel setup section
5. For WASM channels: implement in `channels-src/<name>/`

### Adding a New Tool

1. **Built-in**: Add to `src/tools/builtin/`
2. **WASM**: Place `.wasm` in extensions directory
3. **MCP**: Use `ironclaw mcp add` command

### Adding a New Database Backend

1. Implement `Database` trait from `src/db/mod.rs`
2. Add feature flag in `Cargo.toml`
3. Update `src/db/mod.rs` connection logic
4. Ensure all existing migrations/queries work with new backend

## Feature Parity

See `FEATURE_PARITY.md` for tracking implementation status vs. OpenClaw (TypeScript reference implementation).

**Policy**: If you change implementation status for any feature, update `FEATURE_PARITY.md` in the same branch.

## Debugging

```bash
# Verbose logging
RUST_LOG=ironclaw=trace cargo run

# Agent module only
RUST_LOG=ironclaw::agent=debug cargo run

# With HTTP request logging
RUST_LOG=ironclaw=debug,tower_http=debug cargo run

# JSON logging (production)
RUST_LOG=ironclaw=info cargo run -- --json-logs
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| WASM build fails | Run `rustup target add wasm32-wasip2` and `cargo install wasm-tools` |
| PostgreSQL connection fails | Check `DATABASE_URL` and ensure PostgreSQL is running |
| Docker sandbox unavailable | Verify Docker is installed and running |
| LLM authentication fails | Run `ironclaw onboard` to reconfigure credentials |
| Stale PID lock | Remove `~/.ironclaw/ironclaw.pid` |

## Resources

- **Repository**: https://github.com/nearai/ironclaw
- **Documentation**: See `docs/` directory
- **Community**: Telegram @ironclawAI, Reddit r/ironclawAI
- **License**: MIT OR Apache-2.0
