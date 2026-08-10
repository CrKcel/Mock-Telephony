#!/usr/bin/env bash
# Behavioral tests for module/boot-completed.sh: boot diagnostics report.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

case_reports_full_diagnostics() {
  set_prop ro.radio.noril false
  set_prop gsm.version.baseband MPSS.DI.3.0.c1.7-00001-1
  set_pm_features android.hardware.telephony android.hardware.telephony.gsm
  set_service_list android.hardware.radio.config.IRadioConfig/default
  set_service_list android.hardware.radio.sim.IRadioSim/slot1
  set_dumpsys "mDefaultPhoneId=0 mDefaultSubId=0"
  harness_run boot-completed.sh || return 1
  assert_log_contains "boot-completed" || return 1
  # properties
  assert_log_contains "MPSS.DI.3.0.c1.7-00001-1" || return 1
  # features
  assert_log_contains "android.hardware.telephony" || return 1
  # phone service + registered radio HALs
  assert_log_contains "Service phone: found" || return 1
  assert_log_contains "android.hardware.radio.config" || return 1
  # telephony registry dump
  assert_log_contains "mDefaultPhoneId=0" || return 1
  # no mockmodem pidfile -> reports the daemon as not running
  assert_log_contains "mockmodem not running" || return 1
  return 0
}

case_no_telephony_features_reported() {
  # Empty pm features: boot-completed reports the absence explicitly.
  harness_run boot-completed.sh || return 1
  assert_log_contains "NO telephony features" || return 1
  return 0
}

run_case boot-completed:full-diagnostics case_reports_full_diagnostics
run_case boot-completed:no-features case_no_telephony_features_reported

summary
