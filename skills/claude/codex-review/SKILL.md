---
name: codex-review
description: Use when the user asks Claude Code to have Codex review, audit, critique, grill, or double-check the current plan, diff, code, or implementation. Trigger phrases include "让 codex 审查一下", "让 Codex 看看", "叫 codex review", "ask Codex to review", and similar requests.
argument-hint: "[review focus]"
---

# Ask Codex To Review

When this skill is invoked, call Codex as a read-only reviewer for the current project.

## What to send

Prepare a concise review brief in Chinese with:

- the user's latest request;
- the current goal or plan, if known;
- relevant files, commands, errors, or decisions already discussed;
- what Codex should focus on, such as correctness, security, tests, edge cases, UX, or architecture.

If the user passed arguments, include them as the review focus:

```text
$ARGUMENTS
```

## Command

Run:

```bash
"${CLAUDE_HOME:-$HOME/.claude}/skills/codex-review/scripts/codex_review.sh" "<your concise review brief>"
```

## After Codex replies

Report Codex's findings to the user in Chinese. Lead with high-risk issues first. Mention the saved review file path from the script output.
