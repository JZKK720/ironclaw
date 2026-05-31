---
name: openspace-phased-delegation
version: 0.1.0
description: Use OpenSpace in bounded phases for risky or ambiguous work: search first, delegate discovery or planning, then delegate implementation and verification separately when needed.
activation:
  keywords:
    - openspace phased delegation
    - delegate to openspace in phases
    - search first with openspace
    - openspace step by step
  patterns:
    - "(?i)(delegate|hand off).*(openspace).*(phase|step|stage)"
    - "(?i)(search first|plan first).*(openspace)"
    - "(?i)use openspace .* (carefully|in phases|step by step)"
  tags:
    - openspace
    - delegation
    - planning
    - verification
  max_context_tokens: 1800
requires:
  skills:
    - openspace-discovery
---

# OpenSpace Phased Delegation

Use this skill when the task is large, risky, or underspecified enough that a single OpenSpace call would hide too much uncertainty.

## Runtime assumption

This skill assumes IronClaw has an MCP server named `openspace` configured and active.

Expected tool ids inside IronClaw:

- `openspace_search_skills`
- `openspace_execute_task`
- `openspace_fix_skill`
- `openspace_upload_skill`

If those tools are unavailable, stop and tell the user OpenSpace is not configured in IronClaw yet.

## Core rule

Do not jump straight to one large `openspace_execute_task` call when you still need to clarify scope, validate fit, or control risk.

## Phase pattern

### Phase 1: Search

Call `openspace_search_skills` to see whether OpenSpace already has a strong workflow match.

### Phase 2: Discovery or planning

If the task is still unclear, delegate only discovery or planning first.

Example:

```json
{
  "task": "Inspect the existing implementation surface and propose the smallest safe change set. Do not edit files.",
  "search_scope": "all",
  "max_iterations": 12
}
```

### Phase 3: Implementation

Only after the scope is clear, delegate implementation as a separate call.

### Phase 4: Verification

If verification matters, ask OpenSpace for a focused verification pass or run IronClaw's own validation tools locally.

## Decision rules

- Use one-shot delegation only when the task is already well bounded.
- Split work into phases when the wrong first move would waste time or create regressions.
- Treat OpenSpace's "completed" status as provisional until you see concrete evidence.

## Evidence rules

After each phase, check for:

- changed files or artifacts,
- commands or validations run,
- unresolved risks,
- assumptions that still need confirmation.

If the response lacks evidence, do not report the work as done.

## Reporting rules

When you update the user, explain:

- which phase just ran,
- what OpenSpace actually proved,
- what the next phase is,
- whether IronClaw should continue locally or delegate again.