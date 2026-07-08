---
description: Ask Claude Code for a normal read-only review
argument-hint: "[--wait|--background] [focus] [-- file ...]"
---

Run:

```bash
"${CODEX_HOME:-$HOME/.codex}/agent-bridge/claudegrill" review "$ARGUMENTS"
```

Use `--background` for larger reviews and check progress with `claudegrill status`.
Use `--wait` only for small, focused reviews.
