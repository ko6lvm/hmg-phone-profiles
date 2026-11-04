# 04 - Building & Verification Guide

Instructions for compiling the source code, building NEMESIS standalone and USB installer packages, and executing the automated test suite.

---

## 1. Prerequisites

- **Host System**: Linux (x86_64 or aarch64) or macOS
- **JDK**: Java Development Kit 8 or 17 (must support `-source 8 -target 8`)
- **Android Build Tools**:
  - `aapt` (Android Asset Packaging Tool)
  - `dx` (Dalvik bytecode dexer)
  - `zipalign` (4-byte alignment utility)
  - `apksigner` (v1 and v2 APK signing tool)
- **Utilities**: `bash`, `make`, `zip`, `unzip`, `python3` (3.8+)

Set the environment variable pointing to your Android SDK if installed in a custom path:
```bash
export ANDROID_SDK_ROOT="/path/to/android-sdk"
```

---

## 2. Building Packages

Run the unified build script or use `make`:

```bash
# Build standalone package and USB installer bundle
make build
# or:
./build.sh
```

### Build Pipeline Stages

1. **Resource Compilation**: `aapt` compiles XML resources and generates `R.java`.
2. **Java Compilation**: `javac` compiles Java sources targeting Dalvik runtime (Java 8 bytecode).
3. **Dexing**: `dx` converts compiled `.class` files into `classes.dex`.
4. **Packaging**: `aapt` bundles assets (including embedded `Hyundai Sans` and `Kia Cube` fonts) and resources into an unaligned APK.
5. **Alignment**: `zipalign` aligns uncompressed assets on 4-byte boundaries.
6. **Signing**: `apksigner` signs the APK with both v1 (JAR signing) and v2 (APK signature scheme v2) for KitKat compatibility.
7. **NEMESIS Assembly**: Creates `hmg-phone-profiles.zip` containing `NEMESIS.data`, `app/AutoProfile.apk`, and `svc/helper.sh`.
8. **USB Installer Bundle**: Creates `hmg-phone-profiles-usb.zip` and populates `build/usb-stick/` with root `NEMESIS.data` (`type=install`) and `packages/hmg-phone-profiles.zip`.

---

## 3. Automated Verification Suite

Run all verification tests with a single command:

```bash
make test
# or:
./tests/run_all_tests.sh
```

The test runner executes 5 distinct verification suites:

| Suite | File | What It Tests |
|---|---|---|
| **1. NEMESIS Spec** | `tests/test_nemesis_spec.py` | Verifies `NEMESIS.data` conforms to 1.1 spec (`short-desc` &le; 64 chars, `detailed-desc` &le; 256 chars, `[app.0]`, `[service.0]`). |
| **2. Package Structure** | `tests/test_package_structure.py` | Verifies archive contents, file permissions, and USB bundle layout. |
| **3. APK Verification** | `tests/test_apk_verification.py` | Verifies v1/v2 signatures, KitKat SDK 19 target, and embedded font integrity. |
| **4. Hardware IPC Logic** | `tests/test_hardware_ipc_logic.py` | Verifies Park gear safety gate, switchUser transactions, and door button CAN codes. |
| **5. Radios & Sanitization**| `tests/test_fingerprint_matching.py`<br>`tests/test_sanitization.py` | Verifies Parcel string decoders, ARP table parsing, presence policies, and verifies 0 PII leaks across the repository. |
