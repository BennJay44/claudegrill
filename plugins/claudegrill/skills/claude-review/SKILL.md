---
name: claude-review
description: Use when the user asks Codex to have Claude Code review, audit, critique, grill, or double-check the current plan, diff, code, or implementation. Trigger phrases include "让 claudecode 审查一下", "让 Claude Code 看看", "叫 claude review", "ask Claude to review", and similar requests.
argument-hint: "[review focus]"
---

# Ask Claude Code To Review

When this skill is invoked from Codex, do not directly call Claude Code with project content. Some Codex environments block direct project-context forwarding to another external AI service, even with user consent.

Instead, use the local background bridge. Codex creates a local request bundle, the macOS background bridge calls Claude Code, and Claude's result is written back automatically.

If the user asks for multi-round discussion or plan approval, use the `claude-grill` skill instead of this one.

## What to send

Prepare a concise review brief in Chinese with:

- the user's latest request;
- the current goal or plan, if known;
- relevant files, commands, errors, or decisions already discussed;
- what Claude Code should focus on, such as correctness, security, tests, edge cases, UX, or architecture.
- relevant local file paths that Claude Code should review.

If the user passed arguments, include them as the review focus:

```text
$ARGUMENTS
```

## Command

Run:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/claude-review/scripts/prepare_claude_review.sh" "<your concise review brief>" [relevant-file ...]
```

Pass only the files that are actually needed for the review. Do not pass broad directories unless the user explicitly asks for a broad review.

## After Creating The Handoff

Tell the user:

1. the generated request bundle path;
2. the expected result path;
3. that the local background bridge will process it automatically.

If the user explicitly asks to force a direct terminal call outside Codex, the legacy script remains available:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/claude-review/scripts/claude_review.sh" "<review brief>"
```

Use that only outside restricted Codex contexts.
