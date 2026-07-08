#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(pwd)"
REVIEW_FOCUS="${1:-请审查当前项目的计划、diff 或实现。}"
shift || true
REVIEW_DIR="$PROJECT_DIR/.agent-reviews"
STAMP="$(date '+%Y%m%d-%H%M%S')"
STATE_DIR="${AGENT_BRIDGE_STATE_DIR:-/tmp/claudegrill}"
REQUEST_DIR="$STATE_DIR/requests"
RESULT_DIR="$STATE_DIR/results"
QUEUE_FILE="${AGENT_BRIDGE_QUEUE_FILE:-/tmp/claudegrill-claude-review.queue}"
LOCK_DIR="${AGENT_BRIDGE_LOCK_DIR:-/tmp/claudegrill-claude-review.lock}"
OUT_FILE="$REQUEST_DIR/claude-review-request-$STAMP.md"
PROJECT_POINTER="$REVIEW_DIR/claude-review-request-$STAMP.md"
EXPECTED_RESULT="$RESULT_DIR/claude-review-$STAMP.md"

mkdir -p "$REVIEW_DIR" "$REQUEST_DIR" "$RESULT_DIR"

acquire_queue_lock() {
  local attempts=0
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    if [ -f "$LOCK_DIR/pid" ]; then
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
    if [ "$attempts" -ge 50 ]; then
      echo "无法获取自动审查队列锁：$LOCK_DIR" >&2
      return 1
    fi
    sleep 0.1
  done
  printf '%s\n' "$$" > "$LOCK_DIR/pid"
}

release_queue_lock() {
  rm -f "$LOCK_DIR/pid" 2>/dev/null || true
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

{
  echo "# Claude Code 只读审查请求"
  echo
  echo "- 生成时间：$(date '+%Y-%m-%d %H:%M:%S')"
  echo "- 项目目录：$PROJECT_DIR"
  echo "- 请求来源：Codex"
  echo "- 结果路径：$EXPECTED_RESULT"
  echo
  echo "## 审查目标"
  echo
  echo "$REVIEW_FOCUS"
  echo
  echo "## 审查边界"
  echo
  echo "- 当前后台审查模式不能使用 Read/Grep/Glob/Bash/Edit 等工具。"
  echo "- 请只基于本请求文件中已经嵌入的内容进行审查。"
  echo "- 不要输出 <tool_call>，不要尝试调用工具。"
  echo "- 请只读审查，不要修改、创建、删除项目文件。"
  echo "- 请重点检查正确性、安全性、数据风险、测试缺口、上线/回滚风险。"
  echo "- 如果信息不足，请明确列出需要补充的文件或命令输出。"
  echo
  echo "## 建议输出格式"
  echo
  echo "1. 结论：通过 / 需要修改 / 信息不足"
  echo "2. 高风险问题：按严重程度列出，包含文件或行为依据"
  echo "3. 中低风险问题：列出重要但不阻塞的问题"
  echo "4. 建议的下一步：给 Codex 的具体行动建议"
  echo "5. 你查看过的依据：列出关键命令、文件或 diff 依据"
  echo
  echo "## 当前 Git 状态"
  echo
  echo '```text'
  git status --short 2>/dev/null || echo "当前目录不是 git 仓库，或 git 状态不可用。"
  echo '```'
  echo
  echo "## Diff 统计"
  echo
  echo '```text'
  git diff --stat HEAD 2>/dev/null || echo "diff 统计不可用。"
  echo '```'
  echo
  echo "## Diff 文件列表"
  echo
  echo '```text'
  git diff --name-only HEAD 2>/dev/null || echo "diff 文件列表不可用。"
  echo '```'
  echo
  if [ "$#" -gt 0 ]; then
    echo "## 附带文件内容"
    echo
    for file_path in "$@"; do
      if [ -f "$file_path" ]; then
        echo "### $file_path"
        echo
        echo '```text'
        sed -n '1,260p' "$file_path"
        total_lines="$(wc -l < "$file_path" | tr -d ' ')"
        if [ "${total_lines:-0}" -gt 260 ]; then
          echo
          echo "[已截断：仅包含前 260 行，共 $total_lines 行]"
        fi
        echo '```'
        echo
      else
        echo "### $file_path"
        echo
        echo "文件不存在或不可读取。"
        echo
      fi
    done
  else
    echo "## 附带文件内容"
    echo
    echo "未附带具体文件。Claude Code 只能基于本请求、git 状态和 diff 摘要进行审查。"
  fi
} > "$OUT_FILE"

{
  echo "# Claude Code 审查请求指针"
  echo
  echo "- 本地审查包：$OUT_FILE"
  echo "- 自动结果路径：$EXPECTED_RESULT"
  echo "- 队列文件：$QUEUE_FILE"
} > "$PROJECT_POINTER"

acquire_queue_lock
printf '%s\n' "$OUT_FILE" >> "$QUEUE_FILE"
release_queue_lock

echo "Claude Code 审查请求包已生成：$OUT_FILE"
echo "项目内指针已生成：$PROJECT_POINTER"
echo
echo "已加入本机自动审查队列：$QUEUE_FILE"
echo "Claude Code 审查结果将写入：$EXPECTED_RESULT"
echo "REQUEST_PATH=$OUT_FILE"
echo "RESULT_PATH=$EXPECTED_RESULT"
