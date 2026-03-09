# Agent Rules for IronClaw

## Project Overview

**IronClaw** is a secure personal AI assistant written in Rust. It features:
- Multi-channel input (REPL, HTTP webhooks, WASM channels, Web Gateway)
- WASM sandbox for untrusted tools with capability-based permissions
- Docker sandbox for isolated job execution
- Persistent memory with hybrid search (PostgreSQL + pgvector)
- Multi-provider LLM support (NEAR AI, OpenAI, Anthropic, Ollama, etc.)

## Build Requirements

- **Rust**: 1.92+ (specified in `Cargo.toml` and `Dockerfile`)
- **WASM Target**: `wasm32-wasip2` (for channel builds)
- **PostgreSQL**: 15+ with pgvector extension
- **Docker**: For sandbox container execution
- **Node.js/npm**: For building web gateway assets (if applicable)

## Build Commands

```bash
# Standard build
cargo build --release

# With all features
cargo build --release --all-features

# Run tests
cargo test

# Run with logging
RUST_LOG=ironclaw=debug cargo run

# Full release (rebuilds channels first)
./scripts/build-all.sh
```

## Docker & Deployment

### Local Development (docker-compose.yml)

The project includes a `docker-compose.yml` for local PostgreSQL:

```bash
# Start PostgreSQL with pgvector
docker-compose up -d postgres

# Database is ready when healthy
docker-compose ps
```

**Default credentials** (dev only):
- Database: `ironclaw`
- User: `ironclaw`
- Password: `ironclaw`
- Port: `5432`

### Production Deployment

**Main Application** (`Dockerfile`):
```bash
# Build
docker build --platform linux/amd64 -t ironclaw:latest .

# Run
docker run --env-file .env -p 3000:3000 ironclaw:latest
```

**Worker Container** (`Dockerfile.worker`):
- Used by the orchestrator for sandboxed job execution
- Includes development tools (Rust, Node.js, Python, Git, GitHub CLI)
- Built automatically by orchestrator or manually:
```bash
docker build -f Dockerfile.worker -t ironclaw-worker .
```

**Sandbox Container** (`docker/sandbox.Dockerfile`):
- Lightweight sandbox for WASM tool builds
- Minimal toolset for security

### Environment Configuration

1. **Copy example env**:
   ```bash
   cp .env.example .env
   ```

2. **Required for local development**:
   - `DATABASE_URL` - PostgreSQL connection string
   - LLM provider config (NEAR AI, OpenAI, Anthropic, or Ollama)

3. **First-time setup**:
   ```bash
   ironclaw onboard  # Interactive wizard
   ```

## Project Structure

```
src/
├── main.rs              # Entry point, CLI args
├── lib.rs               # Library root
├── app.rs               # Startup orchestration
├── bootstrap.rs         # Base directory (~/.ironclaw), .env loading
├── config/              # Environment-based configuration
├── agent/               # Core agent loop, scheduler, sessions
├── channels/            # Input channels (REPL, HTTP, web, WASM)
├── cli/                 # CLI subcommands (clap)
├── db/                  # Database layer (PostgreSQL, libSQL)
├── llm/                 # Multi-provider LLM integration
├── tools/               # Tool system (builtin, WASM, MCP)
├── sandbox/             # Docker container management
├── orchestrator/        # Internal API for sandbox containers
├── worker/              # Runs inside Docker containers
├── safety/              # Prompt injection defense
├── secrets/             # Encryption and keychain
├── workspace/           # Persistent memory and search
├── registry/            # Extension registry
├── skills/              # Skill system (SKILL.md)
├── hooks/               # Lifecycle hooks
├── tunnel/              # Public exposure (Cloudflare, ngrok, Tailscale)
└── observability/       # Event/metric recording
```

## Key Files for Agents

| File | Purpose |
|------|---------|
| `Cargo.toml` | Dependencies, features (default: postgres, libsql, html-to-markdown) |
| `docker-compose.yml` | Local PostgreSQL for development |
| `Dockerfile` | Main application container |
| `Dockerfile.worker` | Worker container for sandbox jobs |
| `.env.example` | Configuration template |
| `migrations/` | Database schema migrations |
| `registry/` | Bundled extension registry |
| `channels-src/` | WASM channel source code |

## Configuration Priorities

1. **Bootstrap** (`~/.ironclaw/.env`) - Loaded first for DATABASE_URL
2. **Database** - Main configuration storage after connection
3. **Environment** - Override via env vars

## Testing Strategy

| Tier | Command | Dependencies |
|------|---------|--------------|
| Unit | `cargo test` | None |
| Integration | `cargo test --features integration` | PostgreSQL |
| Live | `cargo test --features integration -- --ignored` | PostgreSQL + LLM API |

## Security Considerations

- Secrets are **never exposed** to WASM tools; injected at host boundary
- All WASM tools run in **isolated containers** with capability-based permissions
- **Prompt injection defense** with pattern detection and sanitization
- **Endpoint allowlisting** for HTTP requests from tools
- **Leak detection** scans requests/responses for credential exfiltration

## Feature Parity Update Policy

- If you change implementation status for any feature tracked in `FEATURE_PARITY.md`, update that file in the same branch.
- Do not open a PR that changes feature behavior without checking `FEATURE_PARITY.md` for needed status updates (`❌`, `🚧`, `✅`, notes, and priorities).

## Common Tasks

### Adding a new LLM provider
1. Add config in `src/config/llm.rs`
2. Implement provider in `src/llm/`
3. Update `docs/LLM_PROVIDERS.md`

### Adding a new channel
1. Implement in `channels-src/<name>/` as WASM component
2. Build with `./channels-src/<name>/build.sh`
3. Register in `src/channels/wasm/bundled.rs`

### Adding a new tool
1. Built-in: Add to `src/tools/builtin/`
2. WASM: Place `.wasm` in extensions directory
3. MCP: Use `ironclaw mcp add` command

## Deployment Checklist

- [ ] Database created with pgvector extension
- [ ] Environment variables configured (.env)
- [ ] LLM provider credentials set
- [ ] Docker socket accessible (for sandbox)
- [ ] Port 3000 available (web gateway)
- [ ] Persistent volume for `~/.ironclaw`
