#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_ROOT="${TMPDIR:-/tmp}/claudegrill-tests-$$"
PASS_COUNT=0
FAIL_COUNT=0

cleanup() {
  rm -rf "$TEST_TMP_ROOT"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

pass() {
  printf 'ok - %s\n' "$1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

assert_file() {
  [ -f "$1" ] || {
    printf '  missing file: %s\n' "$1"
    return 1
  }
}

assert_executable() {
  [ -x "$1" ] || {
    printf '  not executable: %s\n' "$1"
    return 1
  }
}

assert_contains() {
  grep -Fq "$2" "$1" || {
    printf '  missing text in %s: %s\n' "$1" "$2"
    return 1
  }
}

assert_not_contains() {
  if grep -Fq "$2" "$1"; then
    printf '  unexpected text in %s: %s\n' "$1" "$2"
    return 1
  fi
}

assert_headings_match() {
  local en_file="$1"
  local zh_file="$2"
  local en_headings zh_headings expected_zh

  en_headings="$(awk '/^## / {sub(/^## /, ""); print}' "$en_file")"
  zh_headings="$(awk '/^## / {sub(/^## /, ""); print}' "$zh_file")"
  expected_zh="$(printf '%s\n' "$en_headings" | sed \
    -e 's/^Why$/为什么做这个/' \
    -e 's/^Requirements$/环境要求/' \
    -e 's/^Install$/安装/' \
    -e 's/^Usage$/使用/' \
    -e 's/^Runtime Files$/运行时文件/' \
    -e 's/^Tests$/测试/' \
    -e 's/^Uninstall$/卸载/' \
    -e 's/^Safety Notes$/安全说明/')"

  [ "$zh_headings" = "$expected_zh" ] || {
    printf '  README headings differ\n'
    printf '  expected:\n%s\n' "$expected_zh"
    printf '  actual:\n%s\n' "$zh_headings"
    return 1
  }
}

run_with_timeout() {
  local seconds="$1"
  shift
  perl -e 'alarm shift; exec @ARGV' "$seconds" "$@"
}

with_test_env() {
  local name="$1"
  TEST_DIR="$TEST_TMP_ROOT/$name"
  HOME="$TEST_DIR/home"
  CODEX_HOME="$TEST_DIR/codex"
  CLAUDE_HOME="$TEST_DIR/claude"
  AGENT_BRIDGE_STATE_DIR="$TEST_DIR/state"
  AGENT_BRIDGE_QUEUE_FILE="$TEST_DIR/queue"
  AGENT_BRIDGE_LOCK_DIR="$TEST_DIR/lock"
  PATH="$TEST_DIR/bin:$PATH"
  mkdir -p "$HOME" "$CODEX_HOME" "$CLAUDE_HOME" "$AGENT_BRIDGE_STATE_DIR" "$TEST_DIR/bin"
  export HOME CODEX_HOME CLAUDE_HOME AGENT_BRIDGE_STATE_DIR AGENT_BRIDGE_QUEUE_FILE AGENT_BRIDGE_LOCK_DIR PATH TEST_DIR
}

test_install_and_uninstall_without_launchagent() {
  with_test_env install

  if ! CLAUDEGRILL_SKIP_LAUNCH_AGENT=1 "$ROOT_DIR/install.sh" > "$TEST_DIR/install.out" 2> "$TEST_DIR/install.err"; then
    cat "$TEST_DIR/install.err"
    return 1
  fi

  assert_file "$CODEX_HOME/skills/claude-review/SKILL.md" &&
    assert_file "$CODEX_HOME/skills/claude-grill/SKILL.md" &&
    assert_file "$CODEX_HOME/plugins/claudegrill/.codex-plugin/plugin.json" &&
    assert_file "$CODEX_HOME/plugins/claudegrill/skills/claude-review/SKILL.md" &&
    assert_file "$CODEX_HOME/plugins/claudegrill/skills/claude-grill/SKILL.md" &&
    assert_file "$CLAUDE_HOME/skills/codex-review/SKILL.md" &&
    assert_executable "$CODEX_HOME/skills/claude-review/scripts/prepare_claude_review.sh" &&
    assert_executable "$CODEX_HOME/skills/claude-grill/scripts/claude_grill_round.sh" &&
    assert_executable "$CODEX_HOME/plugins/claudegrill/skills/claude-review/scripts/prepare_claude_review.sh" &&
    assert_executable "$CODEX_HOME/plugins/claudegrill/skills/claude-grill/scripts/claude_grill_round.sh" &&
    assert_executable "$CLAUDE_HOME/skills/codex-review/scripts/codex_review.sh" &&
    assert_executable "$CODEX_HOME/agent-bridge/claudegrill" &&
    assert_executable "$CODEX_HOME/agent-bridge/agent_bridge_claude_daemon.sh" || return 1

  "$ROOT_DIR/uninstall.sh" > "$TEST_DIR/uninstall.out" 2> "$TEST_DIR/uninstall.err" || {
    cat "$TEST_DIR/uninstall.err"
    return 1
  }

  [ ! -e "$CODEX_HOME/skills/claude-grill" ] &&
    [ ! -e "$CODEX_HOME/skills/claude-review" ] &&
    [ ! -e "$CODEX_HOME/plugins/claudegrill" ] &&
    [ ! -e "$CLAUDE_HOME/skills/codex-review" ] &&
    [ ! -e "$CODEX_HOME/agent-bridge/claudegrill" ]
}

test_prepare_review_creates_queue_bundle_and_pointer() {
  with_test_env prepare
  local work_dir="$TEST_DIR/project"
  mkdir -p "$work_dir"

  (
    cd "$work_dir" &&
      "$ROOT_DIR/skills/codex/claude-review/scripts/prepare_claude_review.sh" "检查安装流程" "$ROOT_DIR/README.md"
  ) > "$TEST_DIR/prepare.out" 2> "$TEST_DIR/prepare.err" || {
    cat "$TEST_DIR/prepare.err"
    return 1
  }

  local request_path result_path
  request_path="$(awk -F= '/^REQUEST_PATH=/ {print $2}' "$TEST_DIR/prepare.out")"
  result_path="$(awk -F= '/^RESULT_PATH=/ {print $2}' "$TEST_DIR/prepare.out")"

  assert_file "$request_path" &&
    assert_file "$work_dir/.agent-reviews/$(basename "$request_path")" &&
    assert_contains "$request_path" "检查安装流程" &&
    assert_contains "$request_path" "$ROOT_DIR/README.md" &&
    assert_contains "$AGENT_BRIDGE_QUEUE_FILE" "$request_path" &&
    [ "$result_path" != "$AGENT_BRIDGE_STATE_DIR/results/${request_path##*/}" ] || return 1

  [ -n "$result_path" ] && [ "${result_path%/*}" = "$AGENT_BRIDGE_STATE_DIR/results" ]
}

test_install_replaces_existing_skill_dirs() {
  with_test_env reinstall
  mkdir -p "$CODEX_HOME/skills/claude-grill" "$CODEX_HOME/skills/claude-review" "$CODEX_HOME/plugins/claudegrill" "$CLAUDE_HOME/skills/codex-review"
  touch "$CODEX_HOME/skills/claude-grill/stale-file"
  touch "$CODEX_HOME/skills/claude-review/stale-file"
  touch "$CODEX_HOME/plugins/claudegrill/stale-file"
  touch "$CLAUDE_HOME/skills/codex-review/stale-file"

  CLAUDEGRILL_SKIP_LAUNCH_AGENT=1 "$ROOT_DIR/install.sh" > "$TEST_DIR/install.out" 2> "$TEST_DIR/install.err" || {
    cat "$TEST_DIR/install.err"
    return 1
  }

  [ ! -e "$CODEX_HOME/skills/claude-grill/stale-file" ] &&
    [ ! -e "$CODEX_HOME/skills/claude-review/stale-file" ] &&
    [ ! -e "$CODEX_HOME/plugins/claudegrill/stale-file" ] &&
    [ ! -e "$CLAUDE_HOME/skills/codex-review/stale-file" ]
}

test_daemon_one_shot_processes_queued_request() {
  with_test_env daemon
  local request_path="$AGENT_BRIDGE_STATE_DIR/requests/claude-review-request-test.md"
  local result_path="$AGENT_BRIDGE_STATE_DIR/results/claude-review-test.md"
  mkdir -p "$(dirname "$request_path")"

  cat > "$TEST_DIR/bin/claude" <<'FAKE_CLAUDE'
#!/usr/bin/env bash
printf 'VERDICT: APPROVED\n\nfake review ok\n'
FAKE_CLAUDE
  chmod +x "$TEST_DIR/bin/claude"

  {
    printf '# Review request\n\n'
    printf -- '- 项目目录：%s\n' "$TEST_DIR/project"
    printf -- '- 结果路径：%s\n' "$result_path"
  } > "$request_path"
  printf '%s\n' "$request_path" > "$AGENT_BRIDGE_QUEUE_FILE"

  if ! AGENT_BRIDGE_ONCE=1 POLL_SECONDS=0 run_with_timeout 5 "$ROOT_DIR/bin/agent_bridge_claude_daemon.sh" > "$TEST_DIR/daemon.out" 2> "$TEST_DIR/daemon.err"; then
    cat "$TEST_DIR/daemon.err"
    return 1
  fi

  assert_file "$result_path" &&
    assert_contains "$result_path" "VERDICT: APPROVED" &&
    assert_file "$request_path.done"
}

test_daemon_one_shot_waits_for_live_lock() {
  with_test_env daemon-lock
  local request_path="$AGENT_BRIDGE_STATE_DIR/requests/claude-review-request-test.md"
  local result_path="$AGENT_BRIDGE_STATE_DIR/results/claude-review-test.md"
  mkdir -p "$(dirname "$request_path")" "$AGENT_BRIDGE_LOCK_DIR"

  cat > "$TEST_DIR/bin/claude" <<'FAKE_CLAUDE'
#!/usr/bin/env bash
printf 'VERDICT: APPROVED\n\nfake review ok\n'
FAKE_CLAUDE
  chmod +x "$TEST_DIR/bin/claude"

  printf '%s\n' "$$" > "$AGENT_BRIDGE_LOCK_DIR/pid"
  (
    sleep 1
    rm -f "$AGENT_BRIDGE_LOCK_DIR/pid"
    rmdir "$AGENT_BRIDGE_LOCK_DIR" 2>/dev/null || true
  ) &

  {
    printf '# Review request\n\n'
    printf -- '- 项目目录：%s\n' "$TEST_DIR/project"
    printf -- '- 结果路径：%s\n' "$result_path"
  } > "$request_path"
  printf '%s\n' "$request_path" > "$AGENT_BRIDGE_QUEUE_FILE"

  if ! AGENT_BRIDGE_ONCE=1 POLL_SECONDS=0 run_with_timeout 5 "$ROOT_DIR/bin/agent_bridge_claude_daemon.sh" > "$TEST_DIR/daemon.out" 2> "$TEST_DIR/daemon.err"; then
    cat "$TEST_DIR/daemon.err"
    return 1
  fi

  assert_file "$result_path" &&
    assert_contains "$result_path" "VERDICT: APPROVED"
}

test_daemon_writes_failure_result_when_claude_times_out() {
  with_test_env daemon-timeout
  local request_path="$AGENT_BRIDGE_STATE_DIR/requests/claude-review-request-test.md"
  local result_path="$AGENT_BRIDGE_STATE_DIR/results/claude-review-test.md"
  mkdir -p "$(dirname "$request_path")"

  cat > "$TEST_DIR/bin/claude" <<'FAKE_CLAUDE'
#!/usr/bin/env bash
sleep 5
FAKE_CLAUDE
  chmod +x "$TEST_DIR/bin/claude"

  {
    printf '# Review request\n\n'
    printf -- '- 项目目录：%s\n' "$TEST_DIR/project"
    printf -- '- 结果路径：%s\n' "$result_path"
  } > "$request_path"
  printf '%s\n' "$request_path" > "$AGENT_BRIDGE_QUEUE_FILE"

  if ! AGENT_BRIDGE_ONCE=1 POLL_SECONDS=0 CLAUDEGRILL_CLAUDE_TIMEOUT_SECONDS=1 run_with_timeout 5 "$ROOT_DIR/bin/agent_bridge_claude_daemon.sh" > "$TEST_DIR/daemon.out" 2> "$TEST_DIR/daemon.err"; then
    cat "$TEST_DIR/daemon.err"
    return 1
  fi

  assert_file "$result_path" &&
    assert_contains "$result_path" "Claude Code 审查桥执行失败" &&
    assert_contains "$result_path" "timeout"
}

test_claude_grill_parses_approved_result() {
  with_test_env grill
  local prepare_dir="$CODEX_HOME/skills/claude-review/scripts"
  local result_path="$TEST_DIR/grill-result.md"
  mkdir -p "$prepare_dir"

  cat > "$prepare_dir/prepare_claude_review.sh" <<FAKE_PREPARE
#!/usr/bin/env bash
printf 'VERDICT: APPROVED\n\nfake grill ok\n' > "$result_path"
printf 'RESULT_PATH=%s\n' "$result_path"
FAKE_PREPARE
  chmod +x "$prepare_dir/prepare_claude_review.sh"

  CLAUDE_GRILL_WAIT_SECONDS=2 "$ROOT_DIR/skills/codex/claude-grill/scripts/claude_grill_round.sh" "检查方案" > "$TEST_DIR/grill.out" 2> "$TEST_DIR/grill.err" || {
    cat "$TEST_DIR/grill.err"
    return 1
  }

  assert_contains "$TEST_DIR/grill.out" "GRILL_VERDICT=APPROVED" &&
    assert_contains "$TEST_DIR/grill.out" "GRILL_EXIT_CODE=0"
}

test_claude_grill_accepts_markdown_wrapped_verdict() {
  with_test_env grill-markdown
  local prepare_dir="$CODEX_HOME/skills/claude-review/scripts"
  local result_path="$TEST_DIR/grill-result.md"
  mkdir -p "$prepare_dir"

  cat > "$prepare_dir/prepare_claude_review.sh" <<FAKE_PREPARE
#!/usr/bin/env bash
printf '**VERDICT: APPROVED**\n\nfake grill ok\n' > "$result_path"
printf 'RESULT_PATH=%s\n' "$result_path"
FAKE_PREPARE
  chmod +x "$prepare_dir/prepare_claude_review.sh"

  CLAUDE_GRILL_WAIT_SECONDS=1 "$ROOT_DIR/skills/codex/claude-grill/scripts/claude_grill_round.sh" "检查方案" > "$TEST_DIR/grill.out" 2> "$TEST_DIR/grill.err" || {
    cat "$TEST_DIR/grill.err"
    return 1
  }

  assert_contains "$TEST_DIR/grill.out" "GRILL_VERDICT=APPROVED" &&
    assert_contains "$TEST_DIR/grill.out" "GRILL_EXIT_CODE=0"
}

test_claude_grill_exits_one_for_revise() {
  with_test_env grill-revise
  local prepare_dir="$CODEX_HOME/skills/claude-review/scripts"
  local result_path="$TEST_DIR/grill-result.md"
  mkdir -p "$prepare_dir"

  cat > "$prepare_dir/prepare_claude_review.sh" <<FAKE_PREPARE
#!/usr/bin/env bash
printf 'VERDICT: REVISE\n\nneeds changes\n' > "$result_path"
printf 'RESULT_PATH=%s\n' "$result_path"
FAKE_PREPARE
  chmod +x "$prepare_dir/prepare_claude_review.sh"

  CLAUDE_GRILL_WAIT_SECONDS=2 "$ROOT_DIR/skills/codex/claude-grill/scripts/claude_grill_round.sh" "检查方案" > "$TEST_DIR/grill.out" 2> "$TEST_DIR/grill.err"
  local status=$?

  [ "$status" -eq 1 ] &&
    assert_contains "$TEST_DIR/grill.out" "GRILL_VERDICT=REVISE" &&
    assert_contains "$TEST_DIR/grill.out" "GRILL_EXIT_CODE=1"
}

test_claude_grill_exits_two_for_blocked() {
  with_test_env grill-blocked
  local prepare_dir="$CODEX_HOME/skills/claude-review/scripts"
  local result_path="$TEST_DIR/grill-result.md"
  mkdir -p "$prepare_dir"

  cat > "$prepare_dir/prepare_claude_review.sh" <<FAKE_PREPARE
#!/usr/bin/env bash
printf 'VERDICT: BLOCKED\n\nmissing information\n' > "$result_path"
printf 'RESULT_PATH=%s\n' "$result_path"
FAKE_PREPARE
  chmod +x "$prepare_dir/prepare_claude_review.sh"

  CLAUDE_GRILL_WAIT_SECONDS=2 "$ROOT_DIR/skills/codex/claude-grill/scripts/claude_grill_round.sh" "检查方案" > "$TEST_DIR/grill.out" 2> "$TEST_DIR/grill.err"
  local status=$?

  [ "$status" -eq 2 ] &&
    assert_contains "$TEST_DIR/grill.out" "GRILL_VERDICT=BLOCKED" &&
    assert_contains "$TEST_DIR/grill.out" "GRILL_EXIT_CODE=2"
}

test_claude_grill_times_out_when_result_missing() {
  with_test_env grill-timeout
  local prepare_dir="$CODEX_HOME/skills/claude-review/scripts"
  local result_path="$TEST_DIR/missing-result.md"
  mkdir -p "$prepare_dir"

  cat > "$prepare_dir/prepare_claude_review.sh" <<FAKE_PREPARE
#!/usr/bin/env bash
printf 'RESULT_PATH=%s\n' "$result_path"
FAKE_PREPARE
  chmod +x "$prepare_dir/prepare_claude_review.sh"

  CLAUDE_GRILL_WAIT_SECONDS=1 "$ROOT_DIR/skills/codex/claude-grill/scripts/claude_grill_round.sh" "检查方案" > "$TEST_DIR/grill.out" 2> "$TEST_DIR/grill.err"
  [ "$?" -eq 124 ] && assert_contains "$TEST_DIR/grill.err" "等待 Claude Code grill 结果超时"
}

test_claudegrill_command_setup_reports_bridge_paths() {
  with_test_env command-setup

  cat > "$TEST_DIR/bin/claude" <<'FAKE_CLAUDE'
#!/usr/bin/env bash
printf 'fake claude\n'
FAKE_CLAUDE
  chmod +x "$TEST_DIR/bin/claude"

  CLAUDEGRILL_SKIP_LAUNCH_AGENT=1 "$ROOT_DIR/install.sh" > "$TEST_DIR/install.out" 2> "$TEST_DIR/install.err" || {
    cat "$TEST_DIR/install.err"
    return 1
  }

  "$CODEX_HOME/agent-bridge/claudegrill" setup > "$TEST_DIR/setup.out" 2> "$TEST_DIR/setup.err" || {
    cat "$TEST_DIR/setup.err"
    return 1
  }

  assert_contains "$TEST_DIR/setup.out" "ClaudeGrill setup" &&
    assert_contains "$TEST_DIR/setup.out" "claude CLI: ok" &&
    assert_contains "$TEST_DIR/setup.out" "Codex plugin: $CODEX_HOME/plugins/claudegrill" &&
    assert_contains "$TEST_DIR/setup.out" "Bridge queue: $AGENT_BRIDGE_QUEUE_FILE"
}

test_claudegrill_command_tracks_background_review_job() {
  with_test_env command-review
  local work_dir="$TEST_DIR/project"
  mkdir -p "$work_dir"

  CLAUDEGRILL_SKIP_LAUNCH_AGENT=1 "$ROOT_DIR/install.sh" > "$TEST_DIR/install.out" 2> "$TEST_DIR/install.err" || {
    cat "$TEST_DIR/install.err"
    return 1
  }

  (
    cd "$work_dir" &&
      "$CODEX_HOME/agent-bridge/claudegrill" review --background "检查插件命令" -- "$ROOT_DIR/README.md"
  ) > "$TEST_DIR/review.out" 2> "$TEST_DIR/review.err" || {
    cat "$TEST_DIR/review.err"
    return 1
  }

  local job_id result_path
  job_id="$(awk -F= '/^JOB_ID=/ {print $2}' "$TEST_DIR/review.out")"
  result_path="$(awk -F= '/^RESULT_PATH=/ {print $2}' "$TEST_DIR/review.out")"

  [ -n "$job_id" ] &&
    assert_file "$AGENT_BRIDGE_STATE_DIR/jobs/$job_id.env" &&
    assert_contains "$AGENT_BRIDGE_QUEUE_FILE" "claude-review-request-" &&
    "$CODEX_HOME/agent-bridge/claudegrill" status "$job_id" > "$TEST_DIR/status.out" &&
    assert_contains "$TEST_DIR/status.out" "$job_id" &&
    assert_contains "$TEST_DIR/status.out" "pending" || return 1

  printf 'Claude review complete\n' > "$result_path"
  "$CODEX_HOME/agent-bridge/claudegrill" result "$job_id" > "$TEST_DIR/result.out" || return 1
  assert_contains "$TEST_DIR/result.out" "Claude review complete"
}

test_claudegrill_command_cancels_queued_job() {
  with_test_env command-cancel
  local work_dir="$TEST_DIR/project"
  mkdir -p "$work_dir"

  CLAUDEGRILL_SKIP_LAUNCH_AGENT=1 "$ROOT_DIR/install.sh" > "$TEST_DIR/install.out" 2> "$TEST_DIR/install.err" || {
    cat "$TEST_DIR/install.err"
    return 1
  }

  (
    cd "$work_dir" &&
      "$CODEX_HOME/agent-bridge/claudegrill" adversarial-review --background "挑战这个实现" -- "$ROOT_DIR/install.sh"
  ) > "$TEST_DIR/review.out" 2> "$TEST_DIR/review.err" || {
    cat "$TEST_DIR/review.err"
    return 1
  }

  local job_id
  job_id="$(awk -F= '/^JOB_ID=/ {print $2}' "$TEST_DIR/review.out")"

  "$CODEX_HOME/agent-bridge/claudegrill" cancel "$job_id" > "$TEST_DIR/cancel.out" || return 1
  "$CODEX_HOME/agent-bridge/claudegrill" status "$job_id" > "$TEST_DIR/status.out" || return 1

  assert_contains "$TEST_DIR/cancel.out" "cancelled" &&
    assert_contains "$TEST_DIR/status.out" "cancelled"
}

test_claudegrill_command_marks_bridge_failure_as_failed() {
  with_test_env command-failed
  local work_dir="$TEST_DIR/project"
  mkdir -p "$work_dir"

  CLAUDEGRILL_SKIP_LAUNCH_AGENT=1 "$ROOT_DIR/install.sh" > "$TEST_DIR/install.out" 2> "$TEST_DIR/install.err" || {
    cat "$TEST_DIR/install.err"
    return 1
  }

  (
    cd "$work_dir" &&
      "$CODEX_HOME/agent-bridge/claudegrill" review --background "检查失败状态" -- "$ROOT_DIR/README.md"
  ) > "$TEST_DIR/review.out" 2> "$TEST_DIR/review.err" || {
    cat "$TEST_DIR/review.err"
    return 1
  }

  local job_id result_path
  job_id="$(awk -F= '/^JOB_ID=/ {print $2}' "$TEST_DIR/review.out")"
  result_path="$(awk -F= '/^RESULT_PATH=/ {print $2}' "$TEST_DIR/review.out")"
  printf 'Claude Code 审查桥执行失败。\n' > "$result_path"

  "$CODEX_HOME/agent-bridge/claudegrill" status "$job_id" > "$TEST_DIR/status.out" || return 1
  assert_contains "$TEST_DIR/status.out" "failed"
}

test_readme_language_switch_and_structure() {
  assert_file "$ROOT_DIR/README.md" &&
    assert_file "$ROOT_DIR/README.zh-CN.md" &&
    assert_contains "$ROOT_DIR/README.md" "[English](README.md) | [中文](README.zh-CN.md)" &&
    assert_contains "$ROOT_DIR/README.zh-CN.md" "[English](README.md) | [中文](README.zh-CN.md)" &&
    assert_headings_match "$ROOT_DIR/README.md" "$ROOT_DIR/README.zh-CN.md" &&
    assert_contains "$ROOT_DIR/README.md" "tests/run.sh" &&
    assert_contains "$ROOT_DIR/README.zh-CN.md" "tests/run.sh" &&
    assert_contains "$ROOT_DIR/README.md" "CLAUDEGRILL_SKIP_LAUNCH_AGENT=1 ./install.sh" &&
    assert_contains "$ROOT_DIR/README.zh-CN.md" "CLAUDEGRILL_SKIP_LAUNCH_AGENT=1 ./install.sh"
}

test_codex_plugin_manifest_is_valid_for_local_plugin() {
  local manifest="$ROOT_DIR/plugins/claudegrill/.codex-plugin/plugin.json"

  assert_file "$manifest" &&
    assert_executable "$ROOT_DIR/plugins/claudegrill/scripts/claudegrill" &&
    assert_contains "$manifest" '"name": "claudegrill"' &&
    assert_contains "$manifest" '"skills": "./skills/"' &&
    assert_contains "$manifest" '"displayName": "ClaudeGrill"' &&
    assert_contains "$manifest" '"shortDescription": "Ask Claude Code to review or challenge Codex work"' &&
    assert_contains "$manifest" '"Read"' &&
    assert_not_contains "$manifest" '"Write"'
}

test_codex_plugin_skills_match_source_skills() {
  diff -ru "$ROOT_DIR/skills/codex/claude-review" "$ROOT_DIR/plugins/claudegrill/skills/claude-review" &&
    diff -ru "$ROOT_DIR/skills/codex/claude-grill" "$ROOT_DIR/plugins/claudegrill/skills/claude-grill"
}

test_codex_plugin_command_docs_exist() {
  local command
  for command in setup review adversarial-review grill status result cancel; do
    assert_file "$ROOT_DIR/plugins/claudegrill/commands/$command.md" || return 1
    assert_contains "$ROOT_DIR/plugins/claudegrill/commands/$command.md" "claudegrill" || return 1
  done
}

test_tracked_files_do_not_reference_legacy_project_name() {
  local pattern
  pattern='grill[-_ ]?m''e[-_ ]?codex|grillm''ecodex'

  if git -C "$ROOT_DIR" grep -n -Ei "$pattern" -- .; then
    return 1
  fi
}

run_test() {
  local name="$1"
  if "$name"; then
    pass "$name"
  else
    fail "$name"
  fi
}

mkdir -p "$TEST_TMP_ROOT"

run_test test_install_and_uninstall_without_launchagent
run_test test_install_replaces_existing_skill_dirs
run_test test_prepare_review_creates_queue_bundle_and_pointer
run_test test_daemon_one_shot_processes_queued_request
run_test test_daemon_one_shot_waits_for_live_lock
run_test test_daemon_writes_failure_result_when_claude_times_out
run_test test_claude_grill_parses_approved_result
run_test test_claude_grill_accepts_markdown_wrapped_verdict
run_test test_claude_grill_exits_one_for_revise
run_test test_claude_grill_exits_two_for_blocked
run_test test_claude_grill_times_out_when_result_missing
run_test test_claudegrill_command_setup_reports_bridge_paths
run_test test_claudegrill_command_tracks_background_review_job
run_test test_claudegrill_command_cancels_queued_job
run_test test_claudegrill_command_marks_bridge_failure_as_failed
run_test test_readme_language_switch_and_structure
run_test test_codex_plugin_manifest_is_valid_for_local_plugin
run_test test_codex_plugin_skills_match_source_skills
run_test test_codex_plugin_command_docs_exist
run_test test_tracked_files_do_not_reference_legacy_project_name

printf '\n%s passed, %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
