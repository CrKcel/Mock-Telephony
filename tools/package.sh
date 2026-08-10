#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/build-env.sh
. "$SCRIPT_DIR/lib/build-env.sh"

SEVEN_ZIP_BIN="${SEVEN_ZIP_BIN:-}"
if [ -z "$SEVEN_ZIP_BIN" ]; then
  if command -v 7zz >/dev/null 2>&1; then
    SEVEN_ZIP_BIN=$(command -v 7zz)
  elif command -v 7z >/dev/null 2>&1; then
    SEVEN_ZIP_BIN=$(command -v 7z)
  else
    die "required command not found: 7zz or 7z"
  fi
fi

if [ "${1:-}" != --no-build ]; then
  "$SCRIPT_DIR/build.sh"
fi

ARTIFACT="$PROJECT_ROOT/out/artifacts/mockmodem.jar"
MODULE_SRC="$PROJECT_ROOT/module"
STAGE="$PROJECT_ROOT/out/module-staging"
DIST="$PROJECT_ROOT/dist"

[ -f "$ARTIFACT" ] || die "missing module artifact: run tools/build.sh"
version=$(module_property version)
[ -n "$version" ] || die "module.prop has no version"

PACKAGE_NAME="mock-telephony-${version}.zip"
PACKAGE="$DIST/$PACKAGE_NAME"
TEMP_DIR=$(mktemp -d)
TEMP_PACKAGE="$TEMP_DIR/$PACKAGE_NAME"

rm -rf "$STAGE"
mkdir -p "$STAGE/bin" "$DIST"
cp -a "$MODULE_SRC/." "$STAGE/"
install -m 0644 "$PROJECT_ROOT/LICENSE" "$STAGE/"
cp -a "$PROJECT_ROOT/licenses" "$STAGE/"
install -m 0644 "$ARTIFACT" "$STAGE/bin/mockmodem.jar"

(
  cd "$STAGE"
  "$SEVEN_ZIP_BIN" a -tzip -mx=6 "$TEMP_PACKAGE" . >/dev/null
)
mv -f "$TEMP_PACKAGE" "$PACKAGE"
rmdir "$TEMP_DIR"

echo "Package: $PACKAGE"
