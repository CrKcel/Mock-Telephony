#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/build-env.sh
. "$SCRIPT_DIR/lib/build-env.sh"

"$SCRIPT_DIR/build.sh"
"$SCRIPT_DIR/package.sh" --no-build

echo "Release package: $PROJECT_ROOT/dist/mock-telephony-$(module_property version).zip"
