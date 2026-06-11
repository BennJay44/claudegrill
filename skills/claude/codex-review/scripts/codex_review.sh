#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(pwd)"
REVIEW_FOCUS="${*:-请审查当前项目的计划、diff 或实现。}"
REVIEW_DIR="$PROJECT_DIR/.agent-reviews"
STAMP="$(date '+%Y%m%d-%H%M%S')"
OUT_FILE="$REVIEW_DIR/codex-review-$STAMP.md"
RUN_LOG="$REVIEW_DIR/codex-review-$STAMP.run.log"
PROMPT_FILE="$(mktemp "${TMPDIR:-/tmp}/codex-review.XXXXXX.md")"

cleanup() {
  rm -f "$PROMPT_FILE"
}
trap cleanup EXIT

if command -v codex >/dev/null 2>&1; then
  CODEX_BIN="$(command -v codex)"
elif [ -x "/Applications/Codex.app/Contents/Resources/codex" ]; then
  CODEX_BIN="/Applications/Codex.app/Contents/Resources/codex"
else
  echo "未找到 codex CLI。请先确认 Codex 已安装并登录。" >&2
  exit 1
fi

mkdir -p "$REVIEW_DIR"

cat > "$PROMPT_FILE" <<PROMPT
你是被 Claude Code 邀请进来的 Codex 只读审查员。

请在当前项目目录中审查，不要修改、创建、删除任何项目文件。你可以读取文件、查看 git 状态、查看 diff、运行只读检查命令。若需要验证构建或测试，只提出建议，不要执行会写入大量文件或改变环境的命令。

审查重点：
$REVIEW_FOCUS

请用中文输出，结构如下：

1. 结论：通过 / 需要修改 / 信息不足
2. 高风险问题：按严重程度列出，包含文件或行为依据
3. 中低风险问题：列出重要但不阻塞的问题
4. 建议的下一步：给 Claude Code 的具体行动建议
5. 你查看过的依据：列出关键命令、文件或 diff 依据

如果没有发现问题，请明确说“暂未发现阻塞问题”，并说明剩余不确定性。
PROMPT

if ! "$CODEX_BIN" exec \
    --cd "$PROJECT_DIR" \
    --sandbox read-only \
    --skip-git-repo-check \
    --color never \
    --output-last-message "$OUT_FILE" \
    - < "$PROMPT_FILE" > "$RUN_LOG" 2>&1; then
  echo "Codex 审查调用失败，运行日志在：$RUN_LOG" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

echo
echo "Codex 审查结果已保存到：$OUT_FILE"
if [ -s "$OUT_FILE" ]; then
  echo
  cat "$OUT_FILE"
fi
