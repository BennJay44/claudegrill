# ClaudeGrill

[English](README.md) | [中文](README.zh-CN.md)

ClaudeGrill is a local bridge for Codex and Claude Code.

It installs two Codex skills:

- `claude-review`: ask Claude Code for a one-shot, read-only review.
- `claude-grill`: run a `grill-me-codex` style plan review loop. Codex drafts a plan, Claude Code critiques or approves it, and Codex revises before implementation.

It also installs one Claude Code skill:

- `codex-review`: ask Codex for a one-shot, read-only review from Claude Code.

## Why

Directly forwarding project context from one AI agent to another can be blocked by sandbox or privacy boundaries. ClaudeGrill avoids that by using a local request queue:

1. Codex writes a local review bundle.
2. A macOS LaunchAgent watches the queue.
3. The background bridge calls `claude -p`.
4. Claude's result is written back to a local result file.

Claude remains read-only. Codex remains responsible for editing files.

## Requirements

- macOS for the background LaunchAgent.
- Codex CLI installed and logged in.
- Claude Code CLI installed and logged in.
- `bash`, `launchctl`, and standard Unix tools.

## Install

```bash
./install.sh
```

The installer copies:

- Codex skills to `${CODEX_HOME:-$HOME/.codex}/skills`
- Claude Code skills to `${CLAUDE_HOME:-$HOME/.claude}/skills`
- the bridge daemon to `${CODEX_HOME:-$HOME/.codex}/agent-bridge`
- the LaunchAgent to `~/Library/LaunchAgents/com.claudegrill.agentbridge.claude-review.plist`

To test the file copy step without loading the macOS LaunchAgent:

```bash
CLAUDEGRILL_SKIP_LAUNCH_AGENT=1 ./install.sh
```

## Usage

In Codex:

```text
Ask Claude Code to review this plan.
```

For multi-round plan approval:

```text
Use a grill-me-codex style loop: discuss this plan with Claude Code and get approval before implementation.
```

The `claude-grill` flow expects Claude Code to return one of:

```text
VERDICT: APPROVED
VERDICT: REVISE
VERDICT: BLOCKED
```

In Claude Code:

```text
Ask Codex to review this diff.
```

GitHub does not switch README languages automatically for this repository. Use the language links at the top of the file to switch manually.

## Runtime Files

By default, runtime state lives under:

```text
/tmp/claudegrill
```

You can override it with:

```bash
export AGENT_BRIDGE_STATE_DIR=/path/to/state
export AGENT_BRIDGE_QUEUE_FILE=/path/to/queue
export AGENT_BRIDGE_LOCK_DIR=/path/to/lock
```

For local debugging, process the queue once and exit:

```bash
AGENT_BRIDGE_ONCE=1 ./bin/agent_bridge_claude_daemon.sh
```

## Tests

ClaudeGrill uses a small Bash test harness, so it does not need a separate test framework:

```bash
tests/run.sh
```

The tests run with temporary `HOME`, `CODEX_HOME`, `CLAUDE_HOME`, and bridge state paths. They do not install into your real Codex or Claude directories.

The test harness also checks that `README.md` and `README.zh-CN.md` keep the same section structure and language-switch links.

## Uninstall

```bash
./uninstall.sh
```

This unloads the LaunchAgent and removes installed ClaudeGrill files. It does not delete your project `.agent-reviews/` folders.

## Safety Notes

- ClaudeGrill is designed for local, read-only review.
- Do not pass secrets, API keys, or private credentials into review bundles.
- Claude Code is called with `--tools ""` in the background bridge, so it reviews the embedded request bundle instead of reading files directly.
- Codex applies changes only after the user and Codex accept the plan.
