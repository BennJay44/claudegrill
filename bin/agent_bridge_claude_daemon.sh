#!/usr/bin/env bash
set -euo pipefail

QUEUE_FILE="${AGENT_BRIDGE_QUEUE_FILE:-/tmp/claudegrill-claude-review.queue}"
LOCK_DIR="${AGENT_BRIDGE_LOCK_DIR:-/tmp/claudegrill-claude-review.lock}"
STATE_DIR="${AGENT_BRIDGE_STATE_DIR:-/tmp/claudegrill}"
LOG_DIR="$STATE_DIR/logs"
RESULT_DIR="$STATE_DIR/results"
BATCH_DIR="$STATE_DIR/batches"
POLL_SECONDS="${POLL_SECONDS:-3}"
AGENT_BRIDGE_ONCE="${AGENT_BRIDGE_ONCE:-0}"
LOCK_ATTEMPTS="${AGENT_BRIDGE_LOCK_ATTEMPTS:-50}"

mkdir -p "$LOG_DIR" "$RESULT_DIR" "$BATCH_DIR"
touch "$QUEUE_FILE"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_DIR/claude-review-daemon.log"
}

acquire_queue_lock() {
  local attempts=0
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    if [ -f "$LOCK_DIR/pid" ]; then
      local lock_pid
      lock_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
      if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
        rm -f "$LOCK_DIR/pid"
        rmdir "$LOCK_DIR" 2>/dev/null || true
        continue
      fi
    elif rmdir "$LOCK_DIR" 2>/dev/null; then
      continue
    fi

    attempts=$((attempts + 1))
    if [ "$attempts" -ge "$LOCK_ATTEMPTS" ]; then
      log "queue lock busy: $LOCK_DIR"
      return 1
    fi
    sleep 0.1
  done

  printf '%s\n' "$$" > "$LOCK_DIR/pid"
  return 0
}

release_queue_lock() {
  rm -f "$LOCK_DIR/pid" 2>/dev/null || true
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

find_claude() {
  if command -v claude >/dev/null 2>&1; then
    command -v claude
  elif [ -x "$HOME/.local/bin/claude" ]; then
    printf '%s\n' "$HOME/.local/bin/claude"
  else
    return 1
  fi
}

project_dir_from_request() {
  local request_file="$1"
  local project_line
  project_line="$(grep -m 1 '^- 项目目录：' "$request_file" 2>/dev/null || true)"
  if [ -n "$project_line" ]; then
    printf '%s\n' "${project_line#- 项目目录：}"
  else
    dirname "$(dirname "$request_file")"
  fi
}

result_path_from_request() {
  local request_file="$1"
  local result_line
  result_line="$(grep -m 1 '^- 结果路径：' "$request_file" 2>/dev/null || true)"
  if [ -n "$result_line" ]; then
    printf '%s\n' "${result_line#- 结果路径：}"
  else
    local base stamp
    base="$(basename "$request_file")"
    stamp="${base#claude-review-request-}"
    stamp="${stamp%.md}"
    printf '%s\n' "$RESULT_DIR/claude-review-$stamp.md"
  fi
}

process_request() {
  local request_file="$1"
  [ -n "$request_file" ] || return 0
  [ -f "$request_file" ] || {
    log "skip missing request: $request_file"
    return 0
  }

  local dir base stamp result_file run_log done_file project_dir claude_bin prompt_text
  dir="$(dirname "$request_file")"
  base="$(basename "$request_file")"
  stamp="${base#claude-review-request-}"
  stamp="${stamp%.md}"
  result_file="$(result_path_from_request "$request_file")"
  mkdir -p "$(dirname "$result_file")"
  run_log="${result_file%.md}.run.log"
  done_file="$request_file.done"
  project_dir="$(project_dir_from_request "$request_file")"

  if [ -e "$done_file" ] || [ -s "$result_file" ]; then
    log "skip already processed: $request_file"
    return 0
  fi

  claude_bin="$(find_claude)" || {
    log "claude CLI not found"
    printf 'Claude CLI not found. 请先确认 Claude Code 已安装并登录。\n' > "$run_log"
    return 1
  }

  log "processing: $request_file"
  if ! prompt_text="$(cat "$request_file" 2> "$run_log")"; then
    {
      echo "Claude Code 审查桥读取请求失败。"
      echo
      echo "- 请求文件：$request_file"
      echo "- 错误日志：$run_log"
      echo
      cat "$run_log"
    } > "$result_file"
    log "failed to read request: $request_file"
    return 1
  fi

  prompt_text="你正在以无工具后台审查模式运行。你不能调用 Read、Grep、Glob、Bash、Edit 或任何工具；不要输出 <tool_call>。所有可用上下文都已经在下面的请求包文本里。请直接基于请求包内容给出中文审查意见。

$prompt_text"

  (
    cd "${TMPDIR:-/tmp}"
    "$claude_bin" -p \
      --permission-mode plan \
      --tools "" \
      --output-format text \
      "$prompt_text"
  ) > "$result_file" 2> "$run_log"

  touch "$done_file"
  log "done: $result_file"
}

process_batch_file() {
  local batch_file="$1"

  [ -s "$batch_file" ] || {
    rm -f "$batch_file"
    return 0
  }

  while IFS= read -r request_file; do
    process_request "$request_file" || true
  done < "$batch_file"

  rm -f "$batch_file"
}

recover_batches() {
  local batch_file
  for batch_file in "$BATCH_DIR"/queue-*; do
    [ -e "$batch_file" ] || continue
    process_batch_file "$batch_file"
  done
}

drain_queue_once() {
  local batch_file
  batch_file="$BATCH_DIR/queue-$(date '+%Y%m%d-%H%M%S')-$$"

  recover_batches

  if acquire_queue_lock; then
    if [ -s "$QUEUE_FILE" ]; then
      mv "$QUEUE_FILE" "$batch_file"
      touch "$QUEUE_FILE"
    fi
    release_queue_lock
  else
    return 0
  fi

  process_batch_file "$batch_file"
}

log "daemon started"
if [ "$AGENT_BRIDGE_ONCE" = "1" ]; then
  drain_queue_once
  log "daemon stopped after one drain"
  exit 0
fi

while true; do
  drain_queue_once
  sleep "$POLL_SECONDS"
done
