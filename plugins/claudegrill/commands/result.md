---
description: Show the stored output for a ClaudeGrill job
argument-hint: "[job-id]"
---

Run:

```bash
"${CODEX_HOME:-$HOME/.codex}/agent-bridge/claudegrill" result "$ARGUMENTS"
```

Present the result to the user without hiding findings, verdicts, paths, or error messages.
