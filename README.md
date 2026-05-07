<p align="center">
  <img src="ironclaw.png?v=2" alt="IronClaw" width="200"/>
</p>

<h1 align="center">IronClaw</h1>

<p align="center">
  <strong>Your secure personal AI assistant, always on your side</strong>
</p>

<p align="center">
  <a href="#license"><img src="https://img.shields.io/badge/license-MIT%20OR%20Apache%202.0-blue.svg" alt="License: MIT OR Apache-2.0" /></a>
  <a href="https://t.me/ironclawAI"><img src="https://img.shields.io/badge/Telegram-%40ironclawAI-26A5E4?style=flat&logo=telegram&logoColor=white" alt="Telegram: @ironclawAI" /></a>
  <a href="https://www.reddit.com/r/ironclawAI/"><img src="https://img.shields.io/badge/Reddit-r%2FironclawAI-FF4500?style=flat&logo=reddit&logoColor=white" alt="Reddit: r/ironclawAI" /></a>
  <a href="https://gitcgr.com/nearai/ironclaw">
    <img src="https://gitcgr.com/badge/nearai/ironclaw.svg" alt="gitcgr" />
  </a>
</p>

<p align="center">
  <a href="README.md">English</a> |
  <a href="README.zh-CN.md">简体中文</a> |
  <a href="README.ru.md">Русский</a> |
  <a href="README.ja.md">日本語</a> |
  <a href="README.ko.md">한국어</a>
</p>

<p align="center">
  <a href="#philosophy">Philosophy</a> •
  <a href="#features">Features</a> •
  <a href="#installation">Installation</a> •
  <a href="#configuration">Configuration</a> •
  <a href="#security">Security</a> •
  <a href="#architecture">Architecture</a>
</p>

---

## Philosophy

IronClaw is built on a simple principle: **your AI assistant should work for you, not against you**.

In a world where AI systems are increasingly opaque about data handling and aligned with corporate interests, IronClaw takes a different approach:

- **Your data stays yours** - All information is stored locally, encrypted, and never leaves your control
- **Transparency by design** - Open source, auditable, no hidden telemetry or data harvesting
- **Self-expanding capabilities** - Build new tools on the fly without waiting for vendor updates
- **Defense in depth** - Multiple security layers protect against prompt injection and data exfiltration

IronClaw is the AI assistant you can actually trust with your personal and professional life.

## Features

### Security First

- **WASM Sandbox** - Untrusted tools run in isolated WebAssembly containers with capability-based permissions
- **Credential Protection** - Secrets are never exposed to tools; injected at the host boundary with leak detection
- **Prompt Injection Defense** - Pattern detection, content sanitization, and policy enforcement
- **Endpoint Allowlisting** - HTTP requests only to explicitly approved hosts and paths

### Always Available

- **Multi-channel** - REPL, HTTP webhooks, WASM channels (Telegram, Slack), and web gateway
- **Docker Sandbox** - Isolated container execution with per-job tokens and orchestrator/worker pattern
- **Web Gateway** - Browser UI with real-time SSE/WebSocket streaming
- **Routines** - Cron schedules, event triggers, webhook handlers for background automation
- **Heartbeat System** - Proactive background execution for monitoring and maintenance tasks
- **Parallel Jobs** - Handle multiple requests concurrently with isolated contexts
- **Self-repair** - Automatic detection and recovery of stuck operations

### Self-Expanding

- **Dynamic Tool Building** - Describe what you need, and IronClaw builds it as a WASM tool
- **MCP Protocol** - Connect to Model Context Protocol servers for additional capabilities
- **Plugin Architecture** - Drop in new WASM tools and channels without restarting

### Persistent Memory

- **Hybrid Search** - Full-text + vector search using Reciprocal Rank Fusion
- **Workspace Filesystem** - Flexible path-based storage for notes, logs, and context
- **Identity Files** - Maintain consistent personality and preferences across sessions

## Installation

### Prerequisites

- Rust 1.92+
- PostgreSQL 15+ with [pgvector](https://github.com/pgvector/pgvector) extension
- NEAR AI account (authentication handled via setup wizard)

## Download or Build

Visit [Releases page](https://github.com/JZKK720/ironclaw/releases/) to see the latest updates.

<details>
  <summary>Install via Windows Installer (Windows)</summary>

Download the [Windows Installer](https://github.com/JZKK720/ironclaw/releases/latest/download/ironclaw-x86_64-pc-windows-msvc.msi) and run it.

</details>

<details>
  <summary>Install via powershell script (Windows)</summary>

```sh
irm https://github.com/JZKK720/ironclaw/releases/latest/download/ironclaw-installer.ps1 | iex
```

</details>

<details>
  <summary>Install via shell script (macOS, Linux, Windows/WSL)</summary>

```sh
curl --proto '=https' --tlsv1.2 -LsSf https://github.com/JZKK720/ironclaw/releases/latest/download/ironclaw-installer.sh | sh
```
</details>

<details>
  <summary>Install via Homebrew (macOS/Linux)</summary>

```sh
brew install ironclaw
```

</details>

<details>
  <summary>Install via Docker — recommended for Windows and hands-off auto-upgrades</summary>

**Prerequisites:** one of:
- **Windows (native):** [Docker Desktop for Windows](https://www.docker.com/products/docker-desktop/) — uses WSL2 backend automatically
- **Windows (WSL2 distro):** install Docker Engine + Compose plugin inside your WSL2 distribution ([Docker docs](https://docs.docker.com/engine/install/ubuntu/))
- **macOS:** [Docker Desktop for Mac](https://www.docker.com/products/docker-desktop/)
- **Linux:** Docker Engine + Compose plugin

1. **Clone the repository** (provides `docker-compose.yml` and `.env.example`):
   ```bash
   git clone https://github.com/JZKK720/ironclaw.git
   cd ironclaw
   ```

2. **Create your environment file:**
   ```bash
   cp .env.example .env
   ```
   Open `.env` and set at minimum:
   ```env
  DATABASE_BACKEND=postgres

   # Generate with: openssl rand -hex 32
   GATEWAY_AUTH_TOKEN=<your-random-hex-token>
   SECRETS_MASTER_KEY=<your-random-hex-token>

   # Your LLM provider — e.g. Anthropic:
   LLM_BACKEND=anthropic
   ANTHROPIC_API_KEY=sk-ant-...
   ```

  Docker/local state note:
  The repo compose file keeps state in two places. `IRONCLAW_HOME_DIR` controls the bind-mounted `~/.ironclaw`-style home directory (config, channels, legacy libsql files), while the external Docker volume `ironclaw-pgdata` stores PostgreSQL history. Create that volume once with `docker volume create ironclaw-pgdata`. Keep `DATABASE_BACKEND=postgres` set when this compose stack should stay on PostgreSQL; if it is unset and the mounted home contains `ironclaw.db`, IronClaw can auto-detect libsql instead.

3. **Authenticate with GHCR** (one-time, required for Watchtower auto-updates):
   ```bash
   # Create a Personal Access Token with read:packages scope at https://github.com/settings/tokens
   docker login ghcr.io -u <your-github-username> -p <your-PAT>
   ```

4. **Start all services:**
   ```bash
   docker compose up -d
   ```
   This starts three services:

   | Service | Purpose | URL |
   |---------|---------|-----|
   | `postgres` | pgvector-enabled database | internal |
   | `ironclaw` | AI assistant | http://localhost:3231 (web UI) · http://localhost:8281 (gateway) |
   | `watchtower` | Hourly auto-upgrade | — |

5. **Tail the logs:**
   ```bash
   docker compose logs -f ironclaw
   ```

6. **Upgrade later without rebuilding locally:**
  ```bash
  docker compose pull ironclaw ironclaw-worker
  docker compose up -d --no-build postgres ironclaw
  ```
  This keeps the named Postgres volume and the mounted `IRONCLAW_HOME_DIR` intact while refreshing the runtime images.

> **Windows note:** Windows Smart App Control blocks freshly compiled Rust binaries. Docker (Docker Desktop, or Docker Engine inside WSL2) is the recommended install path on Windows — no Rust toolchain needed.

</details>

<details>
  <summary>Compile the source code (Cargo on Windows, Linux, macOS)</summary>

Install it with `cargo`, just make sure you have [Rust](https://rustup.rs) installed on your computer.

```bash
# Clone the repository
git clone https://github.com/JZKK720/ironclaw.git
cd ironclaw

# Build
cargo build --release

# Run tests
cargo test
```

For **full release** (after modifying channel sources), run `./scripts/build-all.sh` to rebuild channels first.

</details>

### Database Setup

```bash
# Create database
createdb ironclaw

# Enable pgvector
psql ironclaw -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

## Configuration

Run the setup wizard to configure IronClaw:

```bash
ironclaw onboard
```

The wizard handles database connection, NEAR AI authentication (via browser OAuth),
and secrets encryption (using your system keychain). Settings are persisted in the
connected database; bootstrap variables (e.g. `DATABASE_URL`, `LLM_BACKEND`) are
written to `~/.ironclaw/.env` so they are available before the database connects.

### Alternative LLM Providers

IronClaw defaults to NEAR AI but supports many LLM providers out of the box.
Built-in providers include **Anthropic**, **OpenAI**, **GitHub Copilot**, **Google Gemini**, **MiniMax**,
**Mistral**, and **Ollama** (local). OpenAI-compatible services like **OpenRouter**
(300+ models), **Together AI**, **Fireworks AI**, and self-hosted servers (**vLLM**,
**LiteLLM**) are also supported.

Select your provider in the wizard, or set environment variables directly:

```env
# Example: MiniMax (built-in, 204K context)
LLM_BACKEND=minimax
MINIMAX_API_KEY=...

# Example: OpenAI-compatible endpoint
LLM_BACKEND=openai_compatible
LLM_BASE_URL=https://openrouter.ai/api/v1
LLM_API_KEY=sk-or-...
LLM_MODEL=anthropic/claude-sonnet-4
```

See [docs/capabilities/llm-providers.md](docs/capabilities/llm-providers.md) for a full provider guide.

## Security

IronClaw implements defense in depth to protect your data and prevent misuse.

### WASM Sandbox

All untrusted tools run in isolated WebAssembly containers:

- **Capability-based permissions** - Explicit opt-in for HTTP, secrets, tool invocation
- **Endpoint allowlisting** - HTTP requests only to approved hosts/paths
- **Credential injection** - Secrets injected at host boundary, never exposed to WASM code
- **Leak detection** - Scans requests and responses for secret exfiltration attempts
- **Rate limiting** - Per-tool request limits to prevent abuse
- **Resource limits** - Memory, CPU, and execution time constraints

```
WASM ──► Allowlist ──► Leak Scan ──► Credential ──► Execute ──► Leak Scan ──► WASM
         Validator     (request)     Injector       Request     (response)
```

### Prompt Injection Defense

External content passes through multiple security layers:

- Pattern-based detection of injection attempts
- Content sanitization and escaping
- Policy rules with severity levels (Block/Warn/Review/Sanitize)
- Tool output wrapping for safe LLM context injection

### Data Protection

- All data stored locally in your PostgreSQL database
- Secrets encrypted with AES-256-GCM
- No telemetry, analytics, or data sharing
- Full audit log of all tool executions

## Architecture

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

### Core Components

| Component | Purpose |
|-----------|---------|
| **Agent Loop** | Main message handling and job coordination |
| **Router** | Classifies user intent (command, query, task) |
| **Scheduler** | Manages parallel job execution with priorities |
| **Worker** | Executes jobs with LLM reasoning and tool calls |
| **Orchestrator** | Container lifecycle, LLM proxying, per-job auth |
| **Web Gateway** | Browser UI with chat, memory, jobs, logs, extensions, routines |
| **Routines Engine** | Scheduled (cron) and reactive (event, webhook) background tasks |
| **Workspace** | Persistent memory with hybrid search |
| **Safety Layer** | Prompt injection defense and content sanitization |

## Usage

Engine v2 is opt-in right now. If you want to run the new engine instead of the legacy agent loop, start IronClaw with `ENGINE_V2=true`. See [Engine v2 architecture](docs/internal/engine-v2-architecture.md#enabling-engine-v2) for more details.

```bash
# First-time setup (configures database, auth, etc.)
ironclaw onboard

# Start interactive REPL
cargo run

# Start interactive REPL with engine v2
ENGINE_V2=true cargo run

# Engine v2 with debug logging
ENGINE_V2=true RUST_LOG=ironclaw=debug cargo run
```

## Development

```bash
# Format code
cargo fmt

# Lint
cargo clippy --all --benches --tests --examples --all-features

# Run tests
createdb ironclaw_test
cargo test

# Run specific test
cargo test test_name
```

- **Channels**: See [docs/channels/overview.mdx](docs/channels/overview.mdx) for setup of Telegram, Discord, and other channels.
- **Changing channel sources**: Run `./channels-src/telegram/build.sh` before `cargo build` so the updated WASM is bundled.

## Upgrading

### Docker — Automatic (Watchtower)

If you started with `docker compose up -d`, **Watchtower** is already running alongside IronClaw. It checks GHCR every hour and automatically hot-swaps the `ironclaw` container when a new image is published — no manual steps needed.

Verify Watchtower activity:
```bash
docker compose ps watchtower
docker compose logs watchtower
```

### Docker — Manual

Pull the latest image and recreate the container:
```bash
docker compose pull ironclaw
docker compose up -d ironclaw
```

To verify which image digest is currently running:
```bash
docker inspect ghcr.io/jzkk720/ironclaw:latest --format '{{.Created}}'
```

### Binary / Cargo

Re-run the installer script or `cargo install` command from the [Installation](#installation) section.

## OpenClaw Heritage

IronClaw is a Rust reimplementation inspired by [OpenClaw](https://github.com/openclaw/openclaw). See [FEATURE_PARITY.md](FEATURE_PARITY.md) for the complete tracking matrix.

Key differences:

- **Rust vs TypeScript** - Native performance, memory safety, single binary
- **WASM sandbox vs Docker** - Lightweight, capability-based security
- **PostgreSQL vs SQLite** - Production-ready persistence
- **Security-first design** - Multiple defense layers, credential protection

## License

Licensed under either of:

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE))
- MIT License ([LICENSE-MIT](LICENSE-MIT))

at your option.
