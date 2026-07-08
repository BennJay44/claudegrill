#!/usr/bin/env bash
set -euo pipefail

WAIT_SECONDS="${CLAUDE_GRILL_WAIT_SECONDS:-240}"
BRIEF="${1:-请审查并优化当前方案。}"
shift || true

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
PREPARE_SCRIPT="$CODEX_HOME/skills/claude-review/scripts/prepare_claude_review.sh"
if [ ! -x "$PREPARE_SCRIPT" ]; then
  echo "未找到自动桥脚本：$PREPARE_SCRIPT" >&2
  exit 1
fi

for file_path in "$@"; do
  if [ ! -f "$file_path" ]; then
    echo "附带文件不存在或不可读取：$file_path" >&2
    exit 2
  fi
done

PROMPT_TEMPLATE="$(cat <<'PROMPT_EOF'
这是 Codex ↔ Claude Code 的方案商讨/审批回合。请你作为 Claude Code 只读审查员，严格审查 Codex 的方案，并帮助优化。

请只基于本请求中附带的内容分析，不要调用工具，不要输出 <tool_call>。

你必须在最终答案第一行写且只写以下三种 verdict 之一：

VERDICT: APPROVED
VERDICT: REVISE
VERDICT: BLOCKED

判定标准：
- APPROVED：方案可以执行，没有阻塞性风险。
- REVISE：方案方向可行，但需要 Codex 修改计划或补充验证后再执行。
- BLOCKED：关键信息不足，或当前方案存在高风险，不能继续。

请输出：

1. Verdict
2. 主要风险：按严重程度列出
3. 你要求 Codex 修改的点：要具体、可执行
4. 你认可的部分：避免重复返工
5. 下一轮需要 Codex 带回来的内容

Codex 当前方案/请求如下：
PROMPT_EOF
)"
PROMPT="$PROMPT_TEMPLATE"$'\n\n'"$BRIEF"

RUN_OUTPUT="$(mktemp "${TMPDIR:-/tmp}/claude-grill-round.XXXXXX")"
trap 'rm -f "$RUN_OUTPUT"' EXIT

"$PREPARE_SCRIPT" "$PROMPT" "$@" | tee "$RUN_OUTPUT"

RESULT_PATH="$(awk -F '=' '/^RESULT_PATH=/ {print substr($0, index($0, "=") + 1)}' "$RUN_OUTPUT" | tail -1 | sed 's/^ *//;s/ *$//')"
if [ -z "$RESULT_PATH" ]; then
  echo "无法解析 Claude Code 结果路径。" >&2
  echo "prepare 脚本输出如下：" >&2
  cat "$RUN_OUTPUT" >&2
  exit 1
fi

elapsed=0
while [ "$elapsed" -lt "$WAIT_SECONDS" ]; do
  VERDICT_LINE=""
  if [ -s "$RESULT_PATH" ]; then
    VERDICT_LINE="$(grep -m 1 -E '^[*[:space:]]*VERDICT:[[:space:]]*(APPROVED|REVISE|BLOCKED)[*[:space:]]*$' "$RESULT_PATH" || true)"
  fi
  if [ -n "$VERDICT_LINE" ]; then
    VERDICT="$(printf '%s\n' "$VERDICT_LINE" | sed 's/^[*[:space:]]*VERDICT:[[:space:]]*//;s/[*[:space:]]*$//')"
    case "$VERDICT" in
      APPROVED) EXIT_CODE=0 ;;
      REVISE) EXIT_CODE=1 ;;
      BLOCKED) EXIT_CODE=2 ;;
      *) EXIT_CODE=3 ;;
    esac
    echo
    echo "Claude Code grill 结果：$RESULT_PATH"
    echo
    cat "$RESULT_PATH"
    echo
    echo "GRILL_RESULT_PATH=$RESULT_PATH"
    echo "GRILL_VERDICT=$VERDICT"
    echo "GRILL_EXIT_CODE=$EXIT_CODE"
    exit "$EXIT_CODE"
  fi
  sleep 3
  elapsed=$((elapsed + 3))
done

echo "等待 Claude Code grill 结果超时，或结果中缺少 VERDICT 行：$RESULT_PATH" >&2
exit 124
