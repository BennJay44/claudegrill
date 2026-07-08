---
name: claude-grill
description: Use when the user asks Codex to discuss, debate, approve, grill, or optimize a plan/project with Claude Code before implementation. Trigger phrases include "和 claudecode 互相商讨", "让 claudecode 审批方案", "优化方案后再做", "多轮审查方案", and similar requests.
argument-hint: "[goal or plan focus]"
---

# Claude Code Plan Grill

Use this skill when the user wants Codex and Claude Code to iteratively improve and approve a plan before execution.

The bundled script runs one grill round only. The multi-round loop is controlled by Codex: inspect Claude's verdict, revise the plan, then call the script again when needed.

## Core Rule

Claude Code is a read-only external reviewer. Codex remains the owner of the work and applies any approved changes. Do not let Claude Code directly edit project files.

## Workflow

1. Draft or locate the current plan.
   - If no plan file exists, create a concise plan in the conversation first.
   - For larger work, save it as `.agent-reviews/codex-plan-YYYYMMDD-HHMMSS.md`.
   - Create `.agent-reviews/` before saving plan files.
2. Send the plan to Claude Code for a grill round.
3. Read Claude's result.
4. If Claude returns `VERDICT: REVISE`, update the plan or implementation approach and run another round.
5. Stop when Claude returns `VERDICT: APPROVED`, `VERDICT: BLOCKED`, or after 3 rounds.
6. Summarize the final agreement to the user before implementation.

## Grill Command

Run one round with:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/claude-grill/scripts/claude_grill_round.sh" "<plan or review brief>" [relevant-file ...]
```

Pass only relevant files. Do not pass broad directories.

## Required Claude Verdict Format

The script asks Claude Code to include exactly one of:

```text
VERDICT: APPROVED
VERDICT: REVISE
VERDICT: BLOCKED
```

Interpretation:

- `APPROVED`: the plan is good enough to execute.
- `REVISE`: Codex should revise the plan and run another round.
- `BLOCKED`: information is missing or the approach is unsafe; ask the user or gather missing context.

## Output To User

After the loop, tell the user:

- how many rounds ran;
- Claude's final verdict;
- what changed in the plan because of Claude's critique;
- the saved result paths.

Do not claim Claude approved if the final result lacks `VERDICT: APPROVED`.
