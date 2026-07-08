#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
AGENT_HOME="$CODEX_HOME/agent-bridge"
CODEX_PLUGIN_HOME="$CODEX_HOME/plugins"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
LAUNCH_AGENT_LABEL="com.claudegrill.agentbridge.claude-review"
LAUNCH_AGENT_PATH="$LAUNCH_AGENT_DIR/$LAUNCH_AGENT_LABEL.plist"
STATE_DIR="${AGENT_BRIDGE_STATE_DIR:-/tmp/claudegrill}"
QUEUE_FILE="${AGENT_BRIDGE_QUEUE_FILE:-/tmp/claudegrill-claude-review.queue}"
LOCK_DIR="${AGENT_BRIDGE_LOCK_DIR:-/tmp/claudegrill-claude-review.lock}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_command bash

mkdir -p \
  "$CODEX_HOME/skills" \
  "$CODEX_PLUGIN_HOME" \
  "$CLAUDE_HOME/skills" \
  "$AGENT_HOME/logs" \
  "$LAUNCH_AGENT_DIR" \
  "$STATE_DIR"

rm -rf \
  "$CODEX_HOME/skills/claude-review" \
  "$CODEX_HOME/skills/claude-grill" \
  "$CODEX_PLUGIN_HOME/claudegrill" \
  "$CLAUDE_HOME/skills/codex-review"

cp -R "$ROOT_DIR/skills/codex/claude-review" "$CODEX_HOME/skills/"
cp -R "$ROOT_DIR/skills/codex/claude-grill" "$CODEX_HOME/skills/"
cp -R "$ROOT_DIR/plugins/claudegrill" "$CODEX_PLUGIN_HOME/"
cp -R "$ROOT_DIR/skills/claude/codex-review" "$CLAUDE_HOME/skills/"
cp "$ROOT_DIR/plugins/claudegrill/scripts/claudegrill" "$AGENT_HOME/claudegrill"
cp "$ROOT_DIR/bin/agent_bridge_claude_daemon.sh" "$AGENT_HOME/agent_bridge_claude_daemon.sh"

chmod +x \
  "$CODEX_HOME/skills/claude-review/scripts/prepare_claude_review.sh" \
  "$CODEX_HOME/skills/claude-review/scripts/claude_review.sh" \
  "$CODEX_HOME/skills/claude-grill/scripts/claude_grill_round.sh" \
  "$CODEX_PLUGIN_HOME/claudegrill/skills/claude-review/scripts/prepare_claude_review.sh" \
  "$CODEX_PLUGIN_HOME/claudegrill/skills/claude-review/scripts/claude_review.sh" \
  "$CODEX_PLUGIN_HOME/claudegrill/skills/claude-grill/scripts/claude_grill_round.sh" \
  "$CODEX_PLUGIN_HOME/claudegrill/scripts/claudegrill" \
  "$CLAUDE_HOME/skills/codex-review/scripts/codex_review.sh" \
  "$AGENT_HOME/claudegrill" \
  "$AGENT_HOME/agent_bridge_claude_daemon.sh"

if [ "${CLAUDEGRILL_SKIP_LAUNCH_AGENT:-0}" = "1" ]; then
  echo "Skipping LaunchAgent setup because CLAUDEGRILL_SKIP_LAUNCH_AGENT=1." >&2
elif [ "$(uname -s)" = "Darwin" ]; then
  sed \
    -e "s#__DAEMON_PATH__#$AGENT_HOME/agent_bridge_claude_daemon.sh#g" \
    -e "s#__LOG_DIR__#$AGENT_HOME/logs#g" \
    -e "s#__STATE_DIR__#$STATE_DIR#g" \
    -e "s#__QUEUE_FILE__#$QUEUE_FILE#g" \
    -e "s#__LOCK_DIR__#$LOCK_DIR#g" \
    "$ROOT_DIR/launchagents/$LAUNCH_AGENT_LABEL.plist.template" > "$LAUNCH_AGENT_PATH"

  launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT_PATH" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT_PATH"
  launchctl kickstart -k "gui/$(id -u)/$LAUNCH_AGENT_LABEL"
else
  echo "Non-macOS detected. Skills were installed, but LaunchAgent was not configured." >&2
fi

echo "ClaudeGrill installed."
echo "Codex skills: $CODEX_HOME/skills/claude-review, $CODEX_HOME/skills/claude-grill"
echo "Codex plugin: $CODEX_PLUGIN_HOME/claudegrill"
echo "ClaudeGrill command: $AGENT_HOME/claudegrill"
echo "Claude skill: $CLAUDE_HOME/skills/codex-review"
echo "Bridge state: $STATE_DIR"
