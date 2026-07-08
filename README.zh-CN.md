---
created: 2026-06-11T20:18
updated: 2026-07-08T18:01
---
# ClaudeGrill

[English](README.md) | [中文](README.zh-CN.md)

ClaudeGrill 是一个本地桥接工具，用来把 Codex 和 Claude Code 的审查流程接起来。

它会安装两个 Codex skill：

- `claude-review`：让 Claude Code 做一次只读审查。
- `claude-grill`：运行多轮方案审查。Codex 先写方案，Claude Code 负责挑问题或批准，Codex 再根据反馈修改并执行。

它也会安装一个 Claude Code skill：

- `codex-review`：让 Codex 从 Claude Code 侧做一次只读审查。

## 为什么做这个

在一些环境里，直接把项目上下文从一个 AI agent 转给另一个 agent，可能会被沙盒或隐私边界拦住。ClaudeGrill 用本地请求队列绕开这个问题：

1. Codex 写出一个本地审查包。
2. macOS LaunchAgent 监听队列。
3. 后台桥调用 `claude -p`。
4. Claude 的结果写回本地结果文件。

Claude 始终只读审查。真正修改文件的责任仍然在 Codex 这边。

## 环境要求

- macOS，用来运行后台 LaunchAgent。
- 已安装并登录 Codex CLI。
- 已安装并登录 Claude Code CLI。
- `bash`、`launchctl` 和常见 Unix 工具。

## 安装

```bash
./install.sh
```

安装脚本会复制：

- Codex 插件包到 `${CODEX_HOME:-$HOME/.codex}/plugins/claudegrill`
- Codex skills 到 `${CODEX_HOME:-$HOME/.codex}/skills`
- Claude Code skills 到 `${CLAUDE_HOME:-$HOME/.claude}/skills`
- 桥接守护进程到 `${CODEX_HOME:-$HOME/.codex}/agent-bridge`
- LaunchAgent 到 `~/Library/LaunchAgents/com.claudegrill.agentbridge.claude-review.plist`

插件包在 `plugins/claudegrill`。它把 Codex 侧 skills 放进标准 Codex 插件结构里；原来的 skill 复制方式仍然保留，这样已有的本机提示词不会失效。

如果只想测试文件复制，不加载 macOS LaunchAgent：

```bash
CLAUDEGRILL_SKIP_LAUNCH_AGENT=1 ./install.sh
```

## 使用

在 Codex 里：

```text
让 claudecode 审查一下这个方案
```

命令式用法：

```bash
"${CODEX_HOME:-$HOME/.codex}/agent-bridge/claudegrill" setup
"${CODEX_HOME:-$HOME/.codex}/agent-bridge/claudegrill" review --background "审查当前实现" -- README.md install.sh
"${CODEX_HOME:-$HOME/.codex}/agent-bridge/claudegrill" adversarial-review --background "挑战插件架构设计" -- plugins/claudegrill/.codex-plugin/plugin.json
"${CODEX_HOME:-$HOME/.codex}/agent-bridge/claudegrill" status
"${CODEX_HOME:-$HOME/.codex}/agent-bridge/claudegrill" result <job-id>
"${CODEX_HOME:-$HOME/.codex}/agent-bridge/claudegrill" cancel <job-id>
```

多轮方案审批：

```text
先和 claudecode 多轮商讨并审批这个方案，再开始实现
```

对应命令是：

```bash
"${CODEX_HOME:-$HOME/.codex}/agent-bridge/claudegrill" grill --wait "实现前审批这个方案" -- plugins/claudegrill/.codex-plugin/plugin.json
```

`claude-grill` 流程要求 Claude Code 返回下面三种结果之一：

```text
VERDICT: APPROVED
VERDICT: REVISE
VERDICT: BLOCKED
```

在 Claude Code 里：

```text
让 codex 审查一下这个 diff
```

GitHub 不会为这个仓库自动按浏览器语言切换 README。需要通过文件顶部的语言链接手动切换。

## 运行时文件

默认运行状态保存在：

```text
/tmp/claudegrill
```

你可以用下面的环境变量覆盖默认路径：

```bash
export AGENT_BRIDGE_STATE_DIR=/path/to/state
export AGENT_BRIDGE_QUEUE_FILE=/path/to/queue
export AGENT_BRIDGE_LOCK_DIR=/path/to/lock
```

本地调试时，可以让队列只处理一次后退出：

```bash
AGENT_BRIDGE_ONCE=1 ./bin/agent_bridge_claude_daemon.sh
```

## 测试

ClaudeGrill 使用一个很小的 Bash 测试脚本，不需要额外测试框架：

```bash
tests/run.sh
```

测试会使用临时的 `HOME`、`CODEX_HOME`、`CLAUDE_HOME` 和桥接状态路径，不会安装到你真实的 Codex 或 Claude 目录。

测试脚本也会检查 `README.md` 和 `README.zh-CN.md` 是否保留相同的章节结构和语言切换链接。

## 卸载

```bash
./uninstall.sh
```

卸载脚本会移除 LaunchAgent 和已安装的 ClaudeGrill 文件。它不会删除项目里的 `.agent-reviews/` 目录。

## 安全说明

- ClaudeGrill 只用于本地、只读审查。
- 不要把 secrets、API key 或私密凭据放进审查包。
- 后台桥调用 Claude Code 时使用 `--tools ""`，所以 Claude 只审查请求包里的内容，不会直接读项目文件。
- 只有在用户和 Codex 接受方案后，Codex 才会修改文件。
