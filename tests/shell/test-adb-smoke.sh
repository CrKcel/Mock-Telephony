#!/usr/bin/env bash
# Offline tests for framework detection and manager command selection.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
ADB_SMOKE_LIB_ONLY=1
# shellcheck source=../../tools/adb-smoke.sh
. "$REPO_ROOT/tools/adb-smoke.sh"

TEST_PASS=0
TEST_FAIL=0
TRACE=""

run_case() {
  local name="$1" fn="$2"
  TRACE=$(mktemp)
  local rc=0
  if ! "$fn"; then rc=1; fi
  rm -f "$TRACE"
  if [ "$rc" -eq 0 ]; then
    TEST_PASS=$((TEST_PASS + 1))
    echo "  ok   $name"
  else
    TEST_FAIL=$((TEST_FAIL + 1))
    echo "  FAIL $name" >&2
  fi
}

assert_eq() {
  [ "$1" = "$2" ] \
    || { echo "  ASSERT: expected [$2], got [$1]" >&2; return 1; }
}

assert_trace() {
  grep -Fqx -- "$1" "$TRACE" \
    || { echo "  ASSERT: command not recorded: $1" >&2; return 1; }
}

case_detects_apatch_before_magisk_context() {
  root_shell() {
    case "$1" in
      *'/data/adb/ap/bin/apd'*) echo yes ;;
      id) echo 'uid=0(root) context=u:r:magisk:s0' ;;
    esac
  }
  assert_eq "$(detect_framework)" apatch
}

case_detects_magisk_context() {
  root_shell() {
    case "$1" in
      id) echo 'uid=0(root) context=u:r:magisk:s0' ;;
    esac
  }
  assert_eq "$(detect_framework)" magisk
}

case_detects_magisk_directory_fallback() {
  root_shell() {
    case "$1" in
      id) echo 'uid=0(root) context=u:r:su:s0' ;;
      *'/data/adb/magisk'*) echo yes ;;
    esac
  }
  assert_eq "$(detect_framework)" magisk
}

case_magisk_manager_commands() {
  root_shell() { printf '%s\n' "$1" >> "$TRACE"; }
  FRAMEWORK=magisk
  manager_install /data/local/tmp/module.zip
  manager_uninstall
  assert_trace '/data/adb/magisk/magisk --install-module /data/local/tmp/module.zip' || return 1
  assert_trace 'touch /data/adb/modules/mock_telephony/remove'
}

case_apatch_manager_commands() {
  root_shell() { printf '%s\n' "$1" >> "$TRACE"; }
  FRAMEWORK=apatch
  manager_install /data/local/tmp/module.zip
  manager_uninstall
  assert_trace '/data/adb/ap/bin/apd module install /data/local/tmp/module.zip' || return 1
  assert_trace '/data/adb/ap/bin/apd module uninstall mock_telephony'
}

run_case adb-smoke:detects-apatch-first case_detects_apatch_before_magisk_context
run_case adb-smoke:detects-magisk-context case_detects_magisk_context
run_case adb-smoke:detects-magisk-directory case_detects_magisk_directory_fallback
run_case adb-smoke:magisk-manager-commands case_magisk_manager_commands
run_case adb-smoke:apatch-manager-commands case_apatch_manager_commands

echo "shell tests: $TEST_PASS passed, $TEST_FAIL failed"
[ "$TEST_FAIL" -eq 0 ]
