---
applyTo: "src/tools/**,tools-src/**,src/channels/**,src/cli/**"
description: "Tool dispatch and channel rules for IronClaw. Apply when working in tools, channels, or CLI — enforces the ToolDispatcher.dispatch() invariant and tool implementation patterns."
---

# Tool Architecture & Dispatch Rules

Full rules: [.claude/rules/tools.md](../../.claude/rules/tools.md) | Architecture: [src/tools/README.md](../../src/tools/README.md)

## Everything Goes Through Tools

**All actions from gateway handlers, CLI commands, WASM channels, or the routine engine MUST go through `ToolDispatcher::dispatch()` — never directly through `state.store`, `workspace`, `extension_manager`, `skill_registry`, or `session_manager`.**

Why this matters:
1. **Audit trail** — every dispatched call creates an `ActionRecord` linked to a system job
2. **Safety pipeline** — parameter normalization, schema validation, `sensitive_params()` redaction, output sanitization
3. **Channel-agnostic** — new channels inherit the full pipeline for free

The pre-commit hook (`scripts/pre-commit-safety.sh`) flags new lines in handler/CLI files that directly touch those state fields. Annotate intentional exceptions with `// dispatch-exempt: <reason>`.

## Tool Implementation Pattern

```rust
#[async_trait]
impl Tool for MyTool {
    fn name(&self) -> &str { "my_tool" }
    fn description(&self) -> &str { "Does something useful" }
    fn parameters_schema(&self) -> serde_json::Value { serde_json::json!({ ... }) }
    async fn execute(&self, params: serde_json::Value, ctx: &JobContext)
        -> Result<ToolOutput, ToolError>
    {
        let start = std::time::Instant::now();
        // ... do work ...
        Ok(ToolOutput::text("result", start.elapsed()))
    }
    fn requires_sanitization(&self) -> bool { true } // always true for external data
}
```

## Tool Type Decision Guide

| Capability | Type |
|-----------|------|
| Core internal, tightly coupled to runtime | Built-in Rust tool (`src/tools/builtin/`) |
| Sandboxed extension, plugin-style | WASM tool (`tools-src/<name>/`) |
| External server, any language | MCP server |

## Channel Implementation

1. Create `src/channels/my_channel.rs` implementing the `Channel` trait
2. Add config in `src/config/channels.rs`
3. Wire up in `src/app.rs` channel setup section
4. For WASM channels: implement with `channels-src/<name>/`, define `<name>.capabilities.json`, build with `--target wasm32-wasip2`
