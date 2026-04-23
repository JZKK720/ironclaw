---
applyTo: "src/safety/**,src/sandbox/**,src/secrets/**,src/tools/wasm/**,crates/ironclaw_safety/**"
description: "Safety, sandbox, and secrets rules for IronClaw. Apply when working in safety/, sandbox/, secrets/, WASM tool sandbox, or the ironclaw_safety crate."
---

# Safety Layer & Sandbox Rules

Full rules: [.claude/rules/safety-and-sandbox.md](../../.claude/rules/safety-and-sandbox.md)

## Safety Layer Pipeline

All external tool output passes through `SafetyLayer` in `crates/ironclaw_safety/`:

1. **Sanitizer** — detects injection patterns, escapes dangerous content
2. **Validator** — checks length, encoding, forbidden patterns
3. **Policy** — rules with severity (Critical/High/Medium/Low) and actions (Block/Warn/Review/Sanitize)
4. **Leak Detector** — scans for 15+ secret patterns at two points: tool output before LLM, and LLM responses before user

Tool outputs are wrapped in `<tool_output>` XML before reaching the LLM.

## Import Convention

Import from the extracted crate directly — **not** from `crate::safety`:
```rust
use ironclaw_safety::SafetyLayer;  // correct
use crate::safety::SafetyLayer;    // wrong — shim no longer re-exports
```

## Sandbox Policies

| Policy | Filesystem | Network |
|--------|-----------|---------|
| `ReadOnly` | Read-only workspace | Allowlisted domains |
| `WorkspaceWrite` | Read-write workspace | Allowlisted domains |
| `FullAccess` | Full filesystem (host) | Unrestricted |

`FullAccess` requires a second opt-in (`SANDBOX_ALLOW_FULL_ACCESS=true`) and bypasses Docker entirely. Without it, `FullAccess` is silently downgraded to `WorkspaceWrite`.

## Zero-Exposure Credential Model

Secrets are AES-256-GCM encrypted on the host. The sandbox network proxy injects credentials into HTTP requests at transit time. **Container processes never see raw credential values.** Do not pass secrets via env vars into containers — use the proxy allowlist + credential injection path.

## Security Review Checklist

When touching listeners, routes, auth, secrets, sandboxing, approvals, or outbound HTTP:
- [ ] No weakening of bearer-token auth, webhook auth, CORS/origin checks
- [ ] Body limits and rate limits preserved
- [ ] Docker containers treated as untrusted
- [ ] Tool parameters with `sensitive_params()` are redacted before logging
- [ ] No new direct DB calls that bypass the safety/audit pipeline
