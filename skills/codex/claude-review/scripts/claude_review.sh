#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(pwd)"
REVIEW_FOCUS="${*:-请审查当前项目的计划、diff 或实现。}"
REVIEW_DIR="$PROJECT_DIR/.agent-reviews"
STAMP="$(date '+%Y%m%d-%H%M%S')"
OUT_FILE="$REVIEW_DIR/claude-review-$STAMP.md"
PROMPT_FILE="$(mktemp "${TMPDIR:-/tmp}/claude-review.XXXXXX.md")"

cleanup() {
  rm -f "$PROMPT_FILE"
}
trap cleanup EXIT

if command -v claude >/dev/null 2>&1; then
  CLAUDE_BIN="$(command -v claude)"
elif [ -x "$HOME/.local/bin/claude" ]; then
  CLAUDE_BIN="$HOME/.local/bin/claude"
else
  echo "未找到 claude CLI。请先确认 Claude Code 已安装并登录。" >&2
  exit 1
fi

mkdir -p "$REVIEW_DIR"

{
  echo "你是被 Codex 邀请进来的 Claude Code 只读审查员。"
  echo
  echo "请在当前项目目录中审查，不要修改、创建、删除任何项目文件。你只能读取文件并基于下方上下文给出审查意见。"
  echo
  echo "审查重点："
  echo "$REVIEW_FOCUS"
  echo
  echo "当前目录：$PROJECT_DIR"
  echo
  echo "Git 状态："
  git status --short 2>/dev/null || echo "当前目录不是 git 仓库，或 git 状态不可用。"
  echo
  echo "Git diff 统计："
  git diff --stat HEAD 2>/dev/null || echo "diff 统计不可用。"
  echo
  echo "Git diff 文件列表："
  git diff --name-only HEAD 2>/dev/null || echo "diff 文件列表不可用。"
  echo
  echo "请用中文输出，结构如下："
  echo
  echo "1. 结论：通过 / 需要修改 / 信息不足"
  echo "2. 高风险问题：按严重程度列出，包含文件或行为依据"
  echo "3. 中低风险问题：列出重要但不阻塞的问题"
  echo "4. 建议的下一步：给 Codex 的具体行动建议"
  echo "5. 你查看过的依据：列出关键文件或 diff 依据"
  echo
  echo "如果没有发现问题，请明确说“暂未发现阻塞问题”，并说明剩余不确定性。"
} > "$PROMPT_FILE"

(
  cd "$PROJECT_DIR"
  "$CLAUDE_BIN" -p \
    --permission-mode plan \
    --tools "Read,Grep,Glob" \
    --output-format text \
    "$(cat "$PROMPT_FILE")"
) | tee "$OUT_FILE"

echo
echo "Claude Code 审查结果已保存到：$OUT_FILE"
