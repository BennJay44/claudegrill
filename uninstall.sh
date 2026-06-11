#!/usr/bin/env bash
set -euo pipefail

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
LAUNCH_AGENT_LABEL="com.claudegrill.agentbridge.claude-review"
LAUNCH_AGENT_PATH="$HOME/Library/LaunchAgents/$LAUNCH_AGENT_LABEL.plist"

if [ "$(uname -s)" = "Darwin" ] && [ -f "$LAUNCH_AGENT_PATH" ]; then
  launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT_PATH" >/dev/null 2>&1 || true
  rm -f "$LAUNCH_AGENT_PATH"
fi

rm -rf \
  "$CODEX_HOME/skills/claude-review" \
  "$CODEX_HOME/skills/claude-grill" \
  "$CLAUDE_HOME/skills/codex-review" \
  "$CODEX_HOME/agent-bridge/agent_bridge_claude_daemon.sh"

echo "ClaudeGrill uninstalled."
