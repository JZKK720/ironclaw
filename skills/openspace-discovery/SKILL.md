---
name: openspace-discovery
version: 0.1.0
description: Search OpenSpace's local and cloud skill catalog through the OpenSpace MCP server before deciding whether to handle work directly in IronClaw or delegate it.
activation:
  keywords:
    - openspace
    - openspace skills
    - search openspace skills
    - find openspace skill
    - use openspace
  patterns:
    - "(?i)(search|find|look for).*(openspace).*(skill|workflow)"
    - "(?i)is there an openspace skill for"
    - "(?i)use openspace"
  tags:
    - openspace
    - mcp
    - delegation
  max_context_tokens: 1400
---

# OpenSpace Discovery

Use this skill when the user explicitly wants OpenSpace help or when you need to check whether OpenSpace already has a reusable workflow before you delegate work.

## Runtime assumption

This skill assumes IronClaw has an MCP server named `openspace` configured and active.

Expected tool ids inside IronClaw:

- `openspace_search_skills`
- `openspace_execute_task`
- `openspace_fix_skill`
- `openspace_upload_skill`

If those tools are unavailable, stop and tell the user OpenSpace is not configured in IronClaw yet. Do not pretend delegation is available.

## Default behavior

1. Search first with `openspace_search_skills`.
2. Review the returned skills and decide whether:
   - IronClaw should handle the task directly,
   - OpenSpace should handle one bounded slice, or
   - OpenSpace should handle the full task.
3. Tell the user what you found and why you recommend that path.

## Search pattern

Use natural-language queries that describe the capability, not just a noun.

Examples:

```json
{
  "query": "docker health checks with restart policy",
  "source": "all"
}
```

```json
{
  "query": "repo-wide refactor planning with validation steps",
  "source": "all",
  "limit": 10,
  "auto_import": true
}
```

## Decision rules

- If OpenSpace returns a strong match and the task needs external tools or a broader skill library, recommend delegation.
- If OpenSpace returns a strong match but IronClaw can execute the workflow natively, follow the workflow yourself and keep OpenSpace out of the loop.
- If results are weak or irrelevant, say so plainly and continue in IronClaw.

## Reporting rules

When you report results to the user, include:

- whether OpenSpace had a useful match,
- the top 1 to 3 relevant skills or patterns,
- whether you recommend direct handling or delegation,
- any missing configuration that blocks OpenSpace usage.