# Build & Release

## Environment

Requires JDK 11+, Android SDK build-tools 34+, Android SDK platform 34+, 7-Zip, `xmllint`, `unzip`, `sha1sum`, and `bwrap`.

## Build

```bash
./tools/release.sh
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

The default check is read-only: it checks the phone, the static bootstrap's SIM `ABSENT`, the 7 HALs,
registration state, and data not connected.

```bash
./tools/adb-smoke.sh
```

Recovery-path verification:

```bash
./tools/adb-smoke.sh --restart-daemon --restart-phone   # self-healing recovery (pull back up after killing daemon/phone)
./tools/adb-smoke.sh --fail-bootstrap                   # boot transaction failure rollback loop (break → roll back → restore)
./tools/adb-smoke.sh --uninstall-reinstall              # uninstall-reinstall-recover loop
```
