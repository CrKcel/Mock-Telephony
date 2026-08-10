#!/usr/bin/env bash
# Behavioral tests for module/service.sh: daemon startup gating.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

case_marker_blocks_daemon() {
  seed_runtime .bootstrap_failed ""
  harness_run service.sh; local rc=$?
  [ "$rc" -ne 0 ] || { echo "  ASSERT: expected refusal after bootstrap failure" >&2; return 1; }
  assert_log_contains "refusing to start daemon" || return 1
  # Supervisor must not be spawned.
  assert_not_exists "$SANDBOX/trace/app_process" || return 1
  return 0
}

case_overlay_not_owned_blocks() {
  # Sandbox default: neither overlay is owned by the module -> refuse.
  harness_run service.sh; local rc=$?
  [ "$rc" -ne 0 ] || { echo "  ASSERT: expected refusal when overlays are not owned" >&2; return 1; }
  assert_log_contains "required overlays are not owned" || return 1
  # Supervisor must not be spawned.
  assert_not_exists "$SANDBOX/trace/app_process" || return 1
  return 0
}

case_injection_missing_blocks() {
  # No overlayfs: the gate is file presence (manager systemless mount or the
  # module's tmpfs+bind mirror). Nothing injected -> refuse to start daemon.
  printf 'nodev tmpfs\n' > "$SANDBOX/etc/filesystems"
  harness_run service.sh; local rc=$?
  [ "$rc" -ne 0 ] || { echo "  ASSERT: expected refusal without injected files" >&2; return 1; }
  assert_log_contains "required injections are not present" || return 1
  assert_not_exists "$SANDBOX/trace/app_process" || return 1
  return 0
}

run_case service:bootstrap-failed-blocks-daemon case_marker_blocks_daemon
run_case service:overlay-not-owned-blocks case_overlay_not_owned_blocks
run_case service:injection-missing-blocks case_injection_missing_blocks

summary
