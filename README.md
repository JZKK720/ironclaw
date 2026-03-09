<p align="center">
  <img src="ironclaw.png?v=2" alt="IronClaw" width="200"/>
</p>

<h1 align="center">IronClaw Docker &amp; Shell Edition</h1>

<p align="center">
  <strong>Your secure personal AI assistant, always on your side</strong>
</p>

<p align="center">
  <a href="#license"><img src="https://img.shields.io/badge/license-MIT%20OR%20Apache%202.0-blue.svg" alt="License: MIT OR Apache-2.0" /></a>
  <a href="https://t.me/ironclawAI"><img src="https://img.shields.io/badge/Telegram-%40ironclawAI-26A5E4?style=flat&logo=telegram&logoColor=white" alt="Telegram: @ironclawAI" /></a>
  <a href="https://www.reddit.com/r/ironclawAI/"><img src="https://img.shields.io/badge/Reddit-r%2FironclawAI-FF4500?style=flat&logo=reddit&logoColor=white" alt="Reddit: r/ironclawAI" /></a>
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

- **Docker Desktop** (Windows/macOS/Linux)
- **PowerShell** (Windows) or **Bash** (macOS/Linux) for setup scripts
- LLM provider account (OpenAI, Anthropic, or OpenAI-compatible endpoint)

### Quick Start (Windows - One Command)

```powershell
# Clone and setup in one go
git clone https://github.com/YOUR_USERNAME/ironclaw.git
cd ironclaw
.\scripts\full-setup.ps1
```

This will:
1. Pull Docker base images
2. Build the IronClaw Docker image (15-25 min)
3. Start PostgreSQL and IronClaw services

After setup completes, access IronClaw at **http://localhost:3231**

### Step-by-Step Setup (Windows)

<details>
  <summary>Click to expand Windows setup steps</summary>

**Step 1: Build Docker Image** (one time, 15-25 min)
```powershell
.\scripts\build.ps1
```

**Step 2: Configure IronClaw** (interactive onboarding)
```powershell
.\scripts\setup.ps1
```

Inside the container shell, run:
```bash
ironclaw onboard  # Configure LLM provider and authentication
```

**Step 3: Start Services**
```powershell
.\scripts\start.ps1
```

Access URLs:
- **Web Gateway**: http://localhost:3231
- **HTTP Webhook**: http://localhost:8281
- **PostgreSQL**: localhost:5433

**Stop Services**
```powershell
.\scripts\stop.ps1
```

</details>

### macOS / Linux Setup

<details>
  <summary>Click to expand macOS/Linux setup steps</summary>

**Option 1: Docker Setup (Recommended)**

```bash
# Build Docker image
docker build --platform linux/amd64 -t ironclaw:latest .

# Start services
docker compose up -d

# For interactive onboarding
docker run -it --rm \
    -p 3231:3000 \
    -p 8281:8080 \
    -e DATABASE_URL=postgres://ironclaw:ironclaw@host.docker.internal:5433/ironclaw \
    -v ironclaw-data:/home/ironclaw/.ironclaw \
    ironclaw:latest
# Then run: ironclaw onboard
```

**Option 2: Native Development Setup**

For development without Docker:

```bash
# Run developer setup script
./scripts/dev-setup.sh

# This will:
# - Install wasm32-wasip2 target
# - Install wasm-tools
# - Run cargo check and tests
# - Install git hooks

# Then build and run
cargo build --release
cargo run
```

</details>

### Development Setup (No Docker Required)

<details>
  <summary>Click to expand development setup</summary>

For contributors who want to develop without Docker:

**Prerequisites:**
- Rust 1.85+
- PostgreSQL 15+ with [pgvector](https://github.com/pgvector/pgvector) extension (optional, libsql used by default)

```bash
# Run the developer setup script
./scripts/dev-setup.sh

# Or manually:
rustup target add wasm32-wasip2
cargo install wasm-tools --locked
cargo check
cargo test
```

For **full release** (after modifying channel sources), run `./scripts/build-all.sh` to rebuild channels first.

</details>

## Configuration

### First-Time Setup

After starting IronClaw for the first time, you need to configure your LLM provider:

**Option 1: Interactive Onboarding (Recommended)**

```bash
# If using Docker setup scripts, this runs inside the container
ironclaw onboard
```

The wizard will guide you through:
- Selecting your LLM provider (OpenAI, Anthropic, OpenRouter, etc.)
- Entering your API key
- Configuring optional features

**Option 2: Environment Variables**

Create a `.env` file in the project root:

```env
# OpenAI
LLM_BACKEND=openai
LLM_API_KEY=sk-...
LLM_MODEL=gpt-4o

# Or Anthropic
LLM_BACKEND=anthropic
LLM_API_KEY=sk-ant-...
LLM_MODEL=claude-sonnet-4-20250514

# Or OpenAI-compatible (OpenRouter, Together AI, etc.)
LLM_BACKEND=openai_compatible
LLM_BASE_URL=https://openrouter.ai/api/v1
LLM_API_KEY=sk-or-...
LLM_MODEL=anthropic/claude-sonnet-4
```

### Available Scripts

| Script | Purpose | Platform |
|--------|---------|----------|
| `scripts/full-setup.ps1` | One-click full setup | Windows |
| `scripts/build.ps1` | Build Docker image | Windows |
| `scripts/setup.ps1` | Interactive onboarding container | Windows |
| `scripts/start.ps1` | Start all services | Windows |
| `scripts/stop.ps1` | Stop all services | Windows |
| `scripts/dev-setup.sh` | Native dev environment | macOS/Linux |

See [scripts/README.md](scripts/README.md) for detailed script documentation.

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

```bash
# Interactive REPL (native build)
cargo run

# With debug logging
RUST_LOG=ironclaw=debug cargo run

# View Docker logs
docker compose logs -f

# Check service status
docker compose ps
```

## Development

```bash
# Format code
cargo fmt

# Lint
cargo clippy --all --benches --tests --examples --all-features

# Run tests
cargo test

# Run specific test
cargo test test_name
```

- **Telegram channel**: See [docs/TELEGRAM_SETUP.md](docs/TELEGRAM_SETUP.md) for setup and DM pairing.
- **Changing channel sources**: Run `./channels-src/telegram/build.sh` before `cargo build` so the updated WASM is bundled.

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
