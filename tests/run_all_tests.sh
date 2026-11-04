#!/usr/bin/env bash
# ==============================================================================
# run_all_tests.sh — Comprehensive Test Suite for autoprofile.selector
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

echo "======================================================================"
echo " Running Full Verification Suite for autoprofile.selector"
echo "======================================================================"

# Ensure latest package is built
./build.sh >/dev/null

echo ""
echo ">>> [1/5] Running NEMESIS Package Specification Tests..."
python3 tests/test_nemesis_spec.py

echo ">>> [2/5] Running Package Directory Structure & File Integrity Tests..."
python3 tests/test_package_structure.py

echo ">>> [3/5] Running Android APK Verification & Signing Tests..."
python3 tests/test_apk_verification.py

echo ">>> [4/5] Running In-Vehicle Hardware IPC Architecture & Safety Tests..."
python3 tests/test_hardware_ipc_logic.py

echo ">>> [5/5] Running Radio Fingerprinting & Sanitization Tests..."
python3 tests/test_fingerprint_matching.py
python3 tests/test_sanitization.py

echo "======================================================================"
echo " ALL TESTS PASSED SUCCESSFULLY! (100% VERIFICATION)"
echo "======================================================================"
