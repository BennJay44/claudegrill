---
description: Ask Claude Code to challenge the implementation approach and design choices
argument-hint: "[--wait|--background] [focus] [-- file ...]"
---

Run:

```bash
"${CODEX_HOME:-$HOME/.codex}/agent-bridge/claudegrill" adversarial-review "$ARGUMENTS"
```

Use this when the user wants Claude Code to question assumptions, tradeoffs, rollback risk, safety, edge cases, and test gaps.
