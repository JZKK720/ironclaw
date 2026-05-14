# IronClaw v0.19 → v0.24 Fresh Build Plan

**Strategy**: Fresh v0.24 build with onboarding, then cherry-pick preserved settings from v0.19 backup.

**Timeline**: 
- Pre-flight checks: 10 min
- Backup & build: 15-20 min  
- Fresh onboarding & validation: 20-30 min
- Selective restore & smoke tests: 15-20 min
- **Total**: ~1 hour

**EXECUTION STATUS (2026-04-02)**:
- ✅ Phase 1: Complete - Backup created at `C:\Users\ninex\git-pr\ironclaw0.19-backup`
- ✅ Phase 2: Complete - v0.24 Docker image built (224MB, ironclaw:v0.24)
- ⏳ Phase 3: Partial - Onboarding wizard functional but Docker stdin issues on final steps
  - ✓ Database connection: PostgreSQL working
  - ✓ Security: SECRETS_MASTER_KEY env var configured (bypassed keychain issue)
  - ✗ Wizard completion: Docker I/O errors prevent full stdin piping (Windows Docker Desktop limitation)
  - Note: Workaround documented below - see "Docker Stdin/TTY Limitations"
- ⏳ Phase 4: Pending - Cherry-pick restore from backup
- ⏳ Phase 5: Pending - Smoke tests

---

## Phase 1: Pre-Flight & Backup (5-10 min)

### 1.1 Identify v0.19 Runtime & Configuration

**Current State:**
- Running container: `ironclaw` (v0.19, probably)
- Local git: `c:\Users\ninex\git-pr\ironclaw` (currently on fork's branch, may be v0.19 or mixed)
- IronClaw home: `~/.ironclaw/` (likely on Windows: `C:\Users\ninex\.ironclaw\`)

**Verify container version:**
```powershell
docker ps --filter "name=ironclaw" --format="table {{.Names}}\t{{.Image}}\t{{.Status}}"
docker inspect <container-id> | grep -i "version\|labels"  # Check image labels
docker exec <container-id> ironclaw --version  # If available
```

**Locate running container's mounted volumes:**
```powershell
docker inspect <container-id> --format='{{json .Mounts}}' | ConvertFrom-Json | Select Source, Destination
```

### 1.2 Backup v0.19 Environment & Credentials

**Create backup directory:**
```powershell
# Windows
$backupPath = "C:\Users\ninex\git-pr\ironclaw0.19-backup"
New-Item -ItemType Directory -Path $backupPath -Force

# Backup entire ~/.ironclaw (contains all settings, credentials, workspace)
Copy-Item -Path "$HOME\.ironclaw" -Destination "$backupPath\.ironclaw-snapshot" -Recurse -Force

# Backup local .env if exists
if (Test-Path "$HOME\.ironclaw\.env") {
  Copy-Item -Path "$HOME\.ironclaw\.env" -Destination "$backupPath\.env.old" -Force
}

# Backup from git-pr/ironclaw if .env exists there
if (Test-Path "c:\Users\ninex\git-pr\ironclaw\.env") {
  Copy-Item -Path "c:\Users\ninex\git-pr\ironclaw\.env" -Destination "$backupPath\.env.git" -Force
}
```

**Backup Docker volumes (if using named volumes):**
```powershell
# List named volumes
docker volume ls | Select-String "ironclaw"

# Inspect volume mount paths
docker volume inspect <volume-name>
```

**Create backup metadata file** (for reference):
```powershell
@"
# v0.19 Backup Metadata
Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Backup Path: $backupPath

## Preserved Items
- ~/.ironclaw/ (full snapshot)
- .env files (old and git-pr versions)
- Docker volume references (inspect commands logged above)

## Key Files to Cherry-Pick
- ~/.ironclaw/.env (LLM_BACKEND, DATABASE_URL, API keys)
- ~/.ironclaw/settings.json (user preferences)
- ~/.ironclaw/session.json (NEAR AI session token, if using)
- ~/.ironclaw/workspace/ (memory/notes/skills)
- ~/.ironclaw/skills/ (trusted skills)

## Docker Container Info
Image: (recorded above)
Volumes: (recorded above)
"@ | Out-File "$backupPath\BACKUP_METADATA.txt"
```

---

## Phase 2: Fresh v0.24 Build & Container Setup (10-15 min)

### 2.1 Verify Local Repository State

**Check current checkout:**
```powershell
cd c:\Users\ninex\git-pr\ironclaw
git status
git log --oneline -5
git branch -a
```

**Expected state** (per AGENTS.md):
- `origin/main` = promoted runtime baseline (**only push target**)
- `upstream/main` = nearai/ironclaw main (fetch-only)
- `upstream/staging` = candidate for fresh-install work

**Ensure on correct baseline:**
```powershell
# If needed, update from upstream
git fetch upstream main staging

# For fresh build, ensure on upstream/staging or origin/main
git log upstream/staging -1 --oneline
git log origin/main -1 --oneline
```

### 2.2 Build v0.24 Binary

**Option A: Local Release Build (Recommended)**
```powershell
cd c:\Users\ninex\git-pr\ironclaw

# Ensure Rust toolchain is current
rustup update
rustup target add wasm32-wasip2

# Run pre-flight checks
cargo fmt --check
cargo clippy --all --benches --tests --examples --all-features
cargo test --lib  # Quick unit tests

# Build release binary
cargo build --release --bin ironclaw

# Binary location: target/release/ironclaw.exe (or ironclaw on Linux)
```

**Option B: Docker Image Build (Recommended for Container Deployment)**
```powershell
# Single-stage build with cache
docker build -t ironclaw:v0.24-fresh -f Dockerfile .

# Or use docker-compose to build
docker-compose build
```

### 2.3 Clean Local Home Directory for Fresh Start

**⚠️ CRITICAL: Do NOT delete yet** — review backup first!

```powershell
# Verify backup was successful
$backupPath = "C:\Users\ninex\git-pr\ironclaw0.19-backup"
Get-ChildItem -Path $backupPath -Recurse | Measure-Object | Select-Object Count

# Only proceed if backup exists and has content
if ((Get-Item "$backupPath\.ironclaw-snapshot" -ErrorAction SilentlyContinue) -ne $null) {
  Write-Host "✅ Backup verified. Safe to clean."
  
  # Remove old ~/.ironclaw to force fresh onboarding
  Remove-Item -Path "$HOME\.ironclaw" -Recurse -Force -ErrorAction SilentlyContinue
  
  # Verify deletion
  if (-not (Test-Path "$HOME\.ironclaw")) {
    Write-Host "✅ Old ~/.ironclaw removed. Fresh build will create new."
  }
} else {
  Write-Host "❌ Backup NOT found. DO NOT DELETE ~/.ironclaw!"
}
```

---

## Phase 3: Fresh v0.24 Onboarding (15-25 min)

### 3.1 Start Fresh Container (No Volume Mount Yet)

**Option A: Local Binary**
```powershell
cd c:\Users\ninex\git-pr\ironclaw

# Run with minimal setup (will trigger onboarding)
.\target\release\ironclaw.exe --help

# Start interactive onboarding
.\target\release\ironclaw.exe onboard
```

**Option B: Docker Container**
```powershell
# Start fresh container (auto-runs onboarding on first launch)
docker run -it --rm \
  -p 3000:3000 \
  -e RUST_LOG=ironclaw=info \
  ironclaw:v0.24-fresh

# Or via docker-compose (new fresh stack)
docker-compose -f docker-compose.yml -p ironclaw-v0.24-fresh up
```

### 3.2 Onboarding Wizard Steps (9-Step Flow)

v0.24 will prompt for:

1. **Database Connection** → libSQL (`~/.ironclaw/ironclaw.db`) or PostgreSQL URL
   - **Cherry-pick decision**: Use fresh libSQL (simpler) OR restore PostgreSQL connection from backup
   
2. **Security** → Master key generation
   - New key will be created & stored in OS keychain
   
3. **Inference Provider** → Select LLM backend
   - **Cherry-pick from backup**: Extract `LLM_BACKEND`, API key from `.env.old`
   
4. **Model Selection** → Choose default model
   - **Cherry-pick**: Use previous model choice if available
   
5. **Embeddings Provider** → Configure embeddings
   - **Cherry-pick**: Extract `EMBEDDINGS_PROVIDER`, API key from backup
   
6. **Channels** → Enable Telegram, Discord, Slack, etc.
   - **Cherry-pick**: Restore channel credentials from backup workspace if needed
   
7. **Extensions** → Discover & install WASM tools
   - Fresh discovery; can reinstall known skills from backup after
   
8. **Docker Sandbox** → Enable/configure sandbox policy
   - Set to `ReadOnly` or `WorkspaceWrite` based on preferences
   
9. **Background Tasks** → Heartbeat scheduling
   - Default: 30 minutes; can adjust later

✅ **Result**: Fresh `~/.ironclaw/.env` created + PostgreSQL/libSQL initialized

### 3.3 Post-Onboarding Validation

After onboarding completes, verify:

```powershell
# Check new config was created
Get-Content "$HOME\.ironclaw\.env" -Head 20

# Test LLM connectivity
.\target\release\ironclaw.exe --version
.\target\release\ironclaw.exe  # Start chat REPL

# Test simple query
# Type: "Hello, who are you?"
# Should get response from LLM
```

---

## Phase 4: Selective Restore from Backup (10-15 min)

### 4.1 Cherry-Pick LLM & Embeddings Configuration

**From backup, extract:**
```powershell
$backupEnv = "$backupPath\.env.old"
$newEnv = "$HOME\.ironclaw\.env"

# Read backup
$backupContent = Get-Content $backupEnv

# Extract key variables (if you want to restore exact config)
$backupContent | Select-String "LLM_BACKEND", "ANTHROPIC_API_KEY", "OPENAI_API_KEY", "EMBEDDINGS_PROVIDER"

# Manual decision: append to new .env if you want identical setup
# Example: add to $newEnv if not already set
```

### 4.2 Restore Workspace & Memory Files

**Copy workspace (contains all memory, notes, skills):**
```powershell
$backupWorkspace = "$backupPath\.ironclaw-snapshot\workspace"
$newWorkspace = "$HOME\.ironclaw\workspace"

# Merge (preserve new identity files, add old memory)
if (Test-Path $backupWorkspace) {
  # Copy entire backup workspace
  Copy-Item -Path "$backupWorkspace\*" -Destination $newWorkspace -Recurse -Force -Exclude "BOOTSTRAP.md"
  
  Write-Host "✅ Workspace memory restored"
}
```

### 4.3 Restore Trusted Skills

**Copy skills directory:**
```powershell
$backupSkills = "$backupPath\.ironclaw-snapshot\skills"
$newSkills = "$HOME\.ironclaw\skills"

if (Test-Path $backupSkills) {
  Copy-Item -Path "$backupSkills\*" -Destination $newSkills -Recurse -Force
  Write-Host "✅ Trusted skills restored"
}
```

### 4.4 Session Token (NEAR AI, if applicable)

**Restore NEAR AI session:**
```powershell
$backupSession = "$backupPath\.ironclaw-snapshot\session.json"
$newSession = "$HOME\.ironclaw\session.json"

if (Test-Path $backupSession) {
  Copy-Item -Path $backupSession -Destination $newSession -Force
  Write-Host "✅ NEAR AI session token restored"
}
```

### 4.5 Settings JSON

**Restore user preferences:**
```powershell
$backupSettings = "$backupPath\.ironclaw-snapshot\settings.json"
$newSettings = "$HOME\.ironclaw\settings.json"

if (Test-Path $backupSettings) {
  # Merge carefully (preserve any new v0.24 defaults, add old custom settings)
  $old = Get-Content $backupSettings | ConvertFrom-Json
  $new = Get-Content $newSettings | ConvertFrom-Json
  
  # Add old custom keys to new (skip if already present)
  $old.PSObject.Properties | ForEach-Object {
    if (-not $new.PSObject.Properties.Name -contains $_.Name) {
      $new | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value
    }
  }
  
  $new | ConvertTo-Json | Set-Content $newSettings
  Write-Host "✅ Settings merged"
}
```

---

## Phase 5: Smoke Tests & Validation (10-15 min)

### 5.1 Test Core Functionality

**Start v0.24 agent:**
```powershell
cd c:\Users\ninex\git-pr\ironclaw

# Start REPL
.\target\release\ironclaw.exe

# Type test queries:
# Query 1: "Hello, what's your name?"
# Query 2: "What time is it?" (tests tool availability)
# Query 3: "List some skills" (if skills were restored)
```

**Docker container test:**
```powershell
docker run -it --rm \
  -v "$HOME/.ironclaw:/root/.ironclaw" \
  -p 3000:3000 \
  ironclaw:v0.24-fresh

# In another terminal, test HTTP gateway
curl http://localhost:3000/api/health
curl http://localhost:3000/api/gateway/status
```

### 5.2 Verify All Features

**Feature checklist (v0.24):**

- [ ] **LLM Provider** → Test inference with your selected model
  ```powershell
  # In REPL: "What's 2+2?" (confirm model responds)
  ```

- [ ] **Embeddings** → Test memory search
  ```powershell
  # In REPL: memory_search "test query" (confirm vector search works)
  ```

- [ ] **Database** → Verify persistence
  ```powershell
  # Check conversation saved:
  # In REPL: /memory (view workspace, confirm files exist)
  ```

- [ ] **Channels** → If enabled (Telegram, Discord, etc.)
  ```powershell
  # Send test message via Telegram/Discord bot
  # Confirm agent responds
  ```

- [ ] **Docker Sandbox** → If enabled
  ```powershell
  # In REPL: "shells: echo hello" (confirm shell tool works)
  # Check Docker daemon is accessible
  ```

- [ ] **Workspace/Memory** → Confirm restore worked
  ```powershell
  # In REPL: memory_search "keyword from old notes"
  # Should return results from restored workspace
  ```

- [ ] **Skills** → If restored
  ```powershell
  # In REPL: skill_list (confirm trusted skills appear)
  ```

- [ ] **Multi-Tenant** (v0.24 feature) - if configured
  ```powershell
  # Verify user isolation and API tokens work
  # (only if you configured multi-user mode during onboarding)
  ```

### 5.3 Run Unit & Integration Tests

```powershell
# Quick smoke tests
cargo test --lib --no-default-features --features "database-postgres" -- --nocapture

# Integration tests (requires postgres running)
cargo test --features integration -- --nocapture

# E2E tests (if available)
cd tests/e2e
pytest --tb=short
```

### 5.4 Comparison Test: Old vs New

**Keep v0.19 backup running in parallel** to compare:

```powershell
# Keep old version in docker if possible
docker run -d --name ironclaw-v0.19-backup \
  -v "$backupPath\.ironclaw-snapshot:/root/.ironclaw" \
  <old-v0.19-image>

# Compare responses
# Test both containers with identical queries
# Should see improvements in v0.24 (better tools, multi-tenant, fixes)
```

---

## Phase 6: Production Cutover (When Ready)

### 6.1 Update Docker Compose

**Create docker-compose.override.yml for v0.24:**

```yaml
version: '3.8'

services:
  ironclaw:
    image: ironclaw:v0.24-fresh
    restart: unless-stopped
    ports:
      - "127.0.0.1:3000:3000"
    environment:
      RUST_LOG: ironclaw=info
      # Add any custom env vars from backup
    volumes:
      - $HOME/.ironclaw:/root/.ironclaw
      - /var/run/docker.sock:/var/run/docker.sock  # if sandbox enabled
    depends_on:
      postgres:
        condition: service_healthy

  postgres:
    image: pgvector/pgvector:pg16
    # ... (unchanged)
```

### 6.2 Run v0.24 in Production

```powershell
# Stop old container
docker-compose down

# Start v0.24 stack
docker-compose -f docker-compose.yml -f docker-compose.override.yml up -d

# Monitor logs
docker-compose logs -f ironclaw
```

### 6.3 Monitor & Rollback Plan

**If issues occur:**

```powershell
# Rollback to v0.19 backup
docker-compose down
docker run -d --name ironclaw-v0.19 \
  -v "$backupPath\.ironclaw-snapshot:/root/.ironclaw" \
  <v0.19-image>

# Investigate v0.24 logs in $backupPath/v0.24-failures.log
```

---

## Appendix: Key Differences v0.19 → v0.24

| Feature | v0.19 | v0.24 | Action |
|---------|-------|-------|--------|
| Multi-tenant | Single-user | ✅ Multi-tenant with user isolation | Fresh onboarding handles setup |
| LLM Providers | Limited | ✅ 10+ providers + custom backends | Re-select during onboarding |
| Database | PostgreSQL only | ✅ PostgreSQL + libSQL | Choose during onboarding |
| Embeddings | Fixed 1536D | ✅ Dynamic dimensions | Auto-detected on first use |
| Skills | Manual | ✅ Recursive bundle discovery | Reinstall from backup if needed |
| Slack Channels | Basic | ✅ Thread reply support | Re-auth during onboarding |
| Shell Commands | Simple | ✅ Low/Medium/High risk levels | Configure during sandbox setup |
| WASM Tools | Limited | ✅ Full WASM sandbox + MCP | Auto-discover during extension step |
| Routines | Basic | ✅ Webhook triggers, better reliability | Recreate if critical |
| Memory | Simple search | ✅ Hybrid FTS + vector (RRF) | Restored from backup |

---

## Troubleshooting Reference

| Issue | Solution |
|-------|----------|
| Onboarding hangs | Kill process, check logs: `RUST_LOG=ironclaw=debug cargo run` |
| LLM not responding | Verify API key in .env, check network connectivity |
| Database error | Ensure PostgreSQL running or libSQL path writable |
| WASM tools not loading | Clear cache: `rm -rf ~/.ironclaw/.wasm-cache`, restart |
| Channels not working | Re-authenticate during onboarding or `ironclaw tool configure --channel telegram` |
| Memory search fails | Rebuild embeddings: `memory_search "test"` triggers index refresh |
| Docker sandbox fails | Verify Docker daemon running: `docker ps` |
| Old workspace not visible | Confirm restore: `ls ~/.ironclaw/workspace/` (should see old files) |

---

## Summary Checklist

- [ ] **Phase 1**: Backup v0.19 to `C:\Users\ninex\git-pr\ironclaw0.19-backup`
- [ ] **Phase 2**: Build v0.24 locally or via Docker
- [ ] **Phase 2**: Clean old `~/.ironclaw/` (verify backup first!)
- [ ] **Phase 3**: Run fresh onboarding wizard
- [ ] **Phase 4**: Cherry-pick settings, workspace, skills from backup
- [ ] **Phase 5**: Run smoke tests (REPL, channels, memory, sandbox)
- [ ] **Phase 5**: Run `cargo test` suite
- [ ] **Phase 6**: Update docker-compose and deploy
- [ ] **Phase 6**: Keep v0.19 backup available for emergency rollback

**Estimated time**: ~1 hour  
**Risk level**: ⚠️ Medium (fresh start, but backup available)  
**Success criterion**: All smoke tests pass + memory/workspace restored + no FATAL errors in logs
