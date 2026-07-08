---
description: Run a Claude Code approval round for a Codex plan
argument-hint: "[--wait|--background] [brief] [-- file ...]"
---

Run:

```bash
"${CODEX_HOME:-$HOME/.codex}/agent-bridge/claudegrill" grill "$ARGUMENTS"
```

The result should contain one of `VERDICT: APPROVED`, `VERDICT: REVISE`, or `VERDICT: BLOCKED`.
Codex remains responsible for applying changes after the plan is approved.
