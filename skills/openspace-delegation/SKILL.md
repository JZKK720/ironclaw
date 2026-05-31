---
name: openspace-delegation
version: 0.1.0
description: Delegate work from IronClaw to OpenSpace when OpenSpace is the better execution surface because of its MCP tooling, skill library, or multi-step grounding workflow.
activation:
  keywords:
    - delegate to openspace
    - use openspace
    - have openspace do
    - openspace delegation
    - let openspace handle
  patterns:
    - "(?i)(delegate|hand off|send).*(to )?openspace"
    - "(?i)let openspace (handle|do|run)"
    - "(?i)have openspace (handle|do|run)"
  tags:
    - openspace
    - delegation
    - mcp
  max_context_tokens: 1800
requires:
  skills:
    - openspace-discovery
---

# OpenSpace Delegation

Use this skill when OpenSpace is the better execution surface for a task.

## Runtime assumption

This skill assumes IronClaw has an MCP server named `openspace` configured and active.

Expected tool ids inside IronClaw:

- `openspace_search_skills`
- `openspace_execute_task`
- `openspace_fix_skill`
- `openspace_upload_skill`

If those tools are unavailable, stop and tell the user OpenSpace is not configured in IronClaw yet.

## When to delegate

- The task needs tools or workflows IronClaw does not currently expose.
- The task is multi-step and OpenSpace's skill library is likely to reduce trial-and-error.
- The user explicitly asks to use OpenSpace.
- You already searched and found an OpenSpace skill or pattern that clearly fits.

## Default workflow

1. Unless the task is already sharply scoped, call `openspace_search_skills` first.
2. If OpenSpace looks like the right surface, call `openspace_execute_task` with a concrete task statement.
3. Review the response for:
   - task result,
   - validations performed,
   - unresolved risks,
   - `evolved_skills` output.
4. Tell the user exactly what OpenSpace did and what still needs attention.

## Execution pattern

Use precise tasks, not vague delegation.

Good:

```json
{
  "task": "Inspect the repo's Docker health-check patterns and propose the smallest change set for service X. Do not edit files.",
  "search_scope": "all",
  "max_iterations": 12
}
```

Good:

```json
{
  "task": "Implement the agreed health-check change for service X, run the narrowest validation, and report any remaining risks.",
  "search_scope": "all",
  "max_iterations": 20
}
```

Avoid umbrella prompts like "fix everything" or "handle this somehow".

## Upload and repair rules

- Use `openspace_fix_skill` only when you know which OpenSpace skill is broken and can describe the repair precisely.
- Use `openspace_upload_skill` only after deciding whether the improvement is reusable or project-specific.
- If OpenSpace returns `evolved_skills`, report them to the user even when you choose not to upload.

## Reporting rules

When delegation finishes, summarize:

- what OpenSpace completed,
- what evidence or validation OpenSpace provided,
- whether there are evolved skills,
- whether you uploaded anything,
- whether IronClaw still needs to do follow-up work locally.