# Build & Release

## Environment

Requires JDK 11+, Android SDK platform & build-tools 34+, 7-Zip, `xmllint`, `unzip`, `sha1sum`, and `bwrap`.

## Build

```bash
./tools/build.sh              # build daemon jar + package module ZIP
./tools/build.sh --no-package # daemon jar only
./tools/build.sh --no-build   # repackage from an existing daemon jar
```

Artifacts:

```text
out/artifacts/mockmodem.jar
out/module-staging/
dist/mock-telephony-<version>.zip
```

## Verification

```bash
./tools/check.sh
```

## Install

```bash
adb push dist/mock-telephony-<version>.zip /data/local/tmp/
adb shell su -c "/data/adb/ksud module install /data/local/tmp/mock-telephony-<version>.zip"
adb reboot
```

## Uninstall

```bash
adb shell su -c "/data/adb/ksud module uninstall mock_telephony"
adb reboot
```

## Device Regression

The default check is read-only: it checks the phone, the static bootstrap's SIM `READY`, the 7 HALs,
voice/data registration IN_SERVICE, and data not connected.

```bash
./tools/adb-smoke.sh
```

Recovery-path verification:

```bash
./tools/adb-smoke.sh --restart-daemon --restart-phone   # self-healing recovery (pull back up after killing daemon/phone)
./tools/adb-smoke.sh --fail-bootstrap                   # boot transaction failure rollback loop (break → roll back → restore)
./tools/adb-smoke.sh --uninstall-reinstall              # uninstall-reinstall-recover loop
```
