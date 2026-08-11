#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/build-env.sh"
load_aidl_version
resolve_android_tools

require_command xmllint
require_command unzip

echo "[check] shell syntax"
while IFS= read -r -d '' script; do
  bash -n "$script"
done < <(find "$PROJECT_ROOT/tools" "$PROJECT_ROOT/tests" -name '*.sh' -print0)
while IFS= read -r -d '' script; do
  sh -n "$script"
done < <(find "$PROJECT_ROOT/module" -maxdepth 1 -name '*.sh' -print0)

echo "[check] XML"
xmllint --noout \
  "$PROJECT_ROOT/module/system/etc/permissions/mock-telephony-features.xml" \
  "$PROJECT_ROOT/module/system/etc/vintf/manifest/mockmodem.radio.xml"

echo "[check] source contracts"
"$PROJECT_ROOT/tests/contracts.sh"

echo "[check] shell behavioral tests"
"$PROJECT_ROOT/tests/shell/run.sh"

echo "[check] runtime java unit tests"
"$PROJECT_ROOT/tests/run-java-tests.sh"

echo "[check] generated AIDL hashes"
for package_name in config data messaging modem network sim voice; do
  hash_var="AIDL_HASH_${package_name^^}"
  generated="$PROJECT_ROOT/out/build/generated/android/hardware/radio/$package_name"
  [ -d "$generated" ] || die "missing generated AIDL package: $package_name"
  rg -q "HASH = \"${!hash_var}\"" "$generated" \
    || die "generated $package_name interface hash does not match lock"
done
if rg -q 'HASH = "0000000000000000000000000000000000000000"' \
    "$PROJECT_ROOT/out/build/generated"; then
  die "zero hash found in generated AIDL"
fi

echo "[check] module ZIP"
version=$(module_property version)
package="$PROJECT_ROOT/dist/mock-telephony-${version}.zip"
[ -f "$package" ] || die "missing package: $package"
unzip -t "$package" >/dev/null
for required in module.prop customize.sh service.sh post-fs-data.sh post-mount.sh \
    LICENSE licenses/LICENSE-2.0.txt \
    bin/mockmodem.jar \
    system/etc/permissions/mock-telephony-features.xml \
    system/etc/vintf/manifest/mockmodem.radio.xml; do
  unzip -Z1 "$package" | grep -Fxq "$required" || die "ZIP missing $required"
done
if unzip -Z1 "$package" | grep -Fxq '.dev'; then
  die "module ZIP must not contain the dev marker"
fi
if unzip -p "$package" system/etc/permissions/mock-telephony-features.xml \
    | grep -Fq 'dev.mocktelephony.'; then
  die "module ZIP must not declare any dev.mocktelephony.* feature"
fi
cmp -s "$PROJECT_ROOT/out/artifacts/mockmodem.jar" \
  <(unzip -p "$package" bin/mockmodem.jar) || die "ZIP contains a stale daemon jar"
extract_dir=$(mktemp -d)
trap 'find "$extract_dir" -depth -delete' EXIT
unzip -q "$package" -d "$extract_dir"
for executable in customize.sh post-fs-data.sh post-mount.sh service.sh boot-completed.sh \
    mockmodem-supervisor.sh uninstall.sh common.sh bootstrap.sh; do
  [ "$(stat -c '%a' "$extract_dir/$executable")" = 755 ] \
    || die "$executable is not mode 0755 in ZIP"
done

echo "[check] module jar boundaries"
module_jar="$PROJECT_ROOT/out/artifacts/mockmodem.jar"
[ -f "$module_jar" ] || die "missing module jar: $module_jar"
module_extract=$(mktemp -d)
trap 'find "$module_extract" -depth -delete' EXIT
unzip -q "$module_jar" classes.dex -d "$module_extract"
module_dump="$module_extract/classes.txt"
"$DEXDUMP_BIN" -d "$module_extract/classes.dex" >"$module_dump" 2>/dev/null || true
if grep -Eq 'Class descriptor.*L(dev/mocktelephony/mock_telephony/|android/telephony/mockmodem/AppMockModemService)' \
    "$module_dump"; then
  die "module jar contains APK-only classes"
fi

for required in MockModemMain MockModemService IRadioConfigImpl; do
  grep -Eq "Class descriptor.*Landroid/telephony/mockmodem/$required;" "$module_dump" \
    || die "module jar is missing $required"
done
if grep -Eq 'Class descriptor.*Landroid/(hardware/radio/ims/|telephony/mockmodem/IRadioImsImpl)' \
    "$module_dump"; then
  die "module jar must not contain IMS classes"
fi

if grep -Eq 'MockSimService\$SimProfileInfo|MOCK_SIM_PROFILE_ID_DEFAULT|;\.loadSimProfile\b|;\.loadSimCard\b|;\.loadSimProfileFromXml|;\.applyAppConfiguration|;\.(changeSimProfile|applySimIdentity|applySimExtended|applyModemIdentity|setSimInfo)' \
    "$module_dump"; then
  die "module jar must not contain the config-switching runtime"
fi
if unzip -Z1 "$package" | grep -Eq '(^|/)mock_sim_.*\.xml$'; then
  die "module ZIP must not contain configurable SIM profiles"
fi
echo "All checks passed"
