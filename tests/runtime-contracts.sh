#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME="$PROJECT_ROOT/daemon/src/main/java/android/telephony/mockmodem"

fail() {
  echo "runtime contract failure: $*" >&2
  exit 1
}

for method in dial emergencyDial sendSms sendCdmaSms sendImsSms setupDataCall deactivateDataCall; do
  source_file="$RUNTIME/IRadioVoiceImpl.java"
  case "$method" in
    sendSms|sendCdmaSms|sendImsSms) source_file="$RUNTIME/IRadioMessagingImpl.java" ;;
    setupDataCall|deactivateDataCall) source_file="$RUNTIME/IRadioDataImpl.java" ;;
  esac
  method_body=$(sed -n "/void $method(/,/^    }/p" "$source_file")
  [ -n "$method_body" ] || fail "missing $method implementation"
  if printf '%s\n' "$method_body" | rg -q 'makeSolRsp\(serial\);'; then
    fail "$method returns success instead of deterministic failure"
  fi
done

# Empty state queries are successful so framework polling does not enter a retry storm.
current_calls_body=$(sed -n '/void getCurrentCalls(/,/^    }/p' "$RUNTIME/IRadioVoiceImpl.java")
printf '%s\n' "$current_calls_body" | rg -q 'makeSolRsp\(serial\);' \
  || fail "getCurrentCalls must return a successful empty state snapshot"

logical_apdu_body=$(sed -n '/void iccTransmitApduLogicalChannel(/,/^    }/p' "$RUNTIME/IRadioSimImpl.java")
printf '%s\n' "$logical_apdu_body" | rg -q 'iccTransmitApduLogicalChannelResponse' \
  || fail "logical APDU must use the logical-channel response callback"
if printf '%s\n' "$logical_apdu_body" | rg -q 'iccTransmitApduBasicChannelResponse'; then
  fail "logical APDU must not use the basic-channel response callback"
fi

rg -q 'result\.addresses = new .*LinkAddress\[0\]' "$RUNTIME/IRadioDataImpl.java" \
  || fail "setupDataCall failure payload has no non-null addresses"
rg -q 'result\.dnses = new String\[0\]' "$RUNTIME/IRadioDataImpl.java" \
  || fail "setupDataCall failure payload has no non-null DNS array"
rg -q 'makeFailedSmsResult\(\)' "$RUNTIME/IRadioMessagingImpl.java" \
  || fail "SMS failure payload factory is missing"

callback_count=$(rg -c 'private volatile IRadio.*(Response|Indication)' "$RUNTIME" \
  | awk -F: '{sum += $2} END {print sum + 0}')
[ "$callback_count" -eq 14 ] || fail "expected 14 volatile callback fields, got $callback_count"

if rg -l 'ServiceManager\.addService|markVintfStability' "$RUNTIME" \
    | grep -vE '/(MockModemMain|StandaloneRadioRegistrar)\.java$' | grep -q .; then
  fail "global service registration (addService/markVintfStability) must live only in MockModemMain + StandaloneRadioRegistrar"
fi
if rg -q '^import android\.app\.' "$RUNTIME"; then
  fail "daemon tree must not depend on android.app classes"
fi
if rg -q 'IRadioImsImpl|^import android\.hardware\.radio\.ims\.' "$RUNTIME"; then
  fail "daemon tree must not contain IMS sources (IRadioImsImpl or ims AIDL imports)"
fi
if rg -q '^import dev\.mocktelephony' "$RUNTIME"; then
  fail "daemon sources must not import APK packages"
fi
if rg -q 'dev\.mocktelephony' "$RUNTIME"; then
  fail "daemon tree must not reference the APK package"
fi
for entry in MockModemMain StandaloneRadioRegistrar; do
  [ -f "$RUNTIME/$entry.java" ] || fail "daemon tree missing entry $entry"
done

# ---- table-driven sweep over the solicited AIDL request surface ----------
# Every framework -> HAL request must be answered, and must either return a
# successful state snapshot or an accepted config push (the documented
# responses below) or fail deterministically. This list is the auditable
# SUCCESS surface; every other request method must not return a bare success
# response.
SUCCESS_QUERIES="
getNumOfLiveModems getPhoneCapability getSimSlotsStatus
getBasebandVersion getDeviceIdentity requestShutdown sendDeviceState setRadioPower
getIccCardStatus areUiccApplicationsEnabled setSimCardPower
getAllowedNetworkTypesBitmap getAvailableBandModes getAvailableNetworks
getCellInfoList getDataRegistrationState getNetworkSelectionMode getOperator
getSignalStrength getSystemSelectionChannels getVoiceRadioTechnology
getVoiceRegistrationState setAllowedNetworkTypesBitmap
setDataProfile setInitialAttachApn
getCurrentCalls
"

check_request_surface() {
  local package_name="$1" cap aidl impl method body
  cap=$(printf '%s' "$package_name" | sed 's/^./\U&/')
  aidl="$PROJECT_ROOT/radio-aidl/api/1/android/hardware/radio/$package_name/IRadio$cap.aidl"
  impl="$RUNTIME/IRadio${cap}Impl.java"
  while read -r method; do
    [ -n "$method" ] || continue
    case "$method" in
      setResponseFunctions|responseAcknowledgement) continue ;;
    esac
    body=$(sed -n "/void $method(/,/^    }/p" "$impl")
    [ -n "$body" ] || fail "missing implementation: IRadio${cap}Impl.$method"
    if printf '%s\n' "$SUCCESS_QUERIES" | rg -q "\b${method}\b"; then
      printf '%s\n' "$body" | rg -q 'makeSolRsp\(serial\);' \
        || fail "$method must return a successful state snapshot (bare makeSolRsp)"
    else
      if printf '%s\n' "$body" | rg -q 'makeSolRsp\(serial\);'; then
        fail "$method must fail deterministically, not return success"
      fi
    fi
  done < <(rg -o '^\s*oneway void [a-zA-Z0-9]+' "$aidl" | sed 's/.*void //')
}
for pkg in config data messaging modem network sim voice; do
  check_request_surface "$pkg"
done

echo "Runtime contract checks passed"
