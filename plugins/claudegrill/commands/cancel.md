---
description: Cancel a queued ClaudeGrill job
argument-hint: "[job-id]"
---

Run:

```bash
"${CODEX_HOME:-$HOME/.codex}/agent-bridge/claudegrill" cancel "$ARGUMENTS"
```

Cancellation prevents queued jobs from being picked up by the local bridge. A job already running in Claude Code may still finish.
