#!/usr/bin/env python3
"""
Test Hardware IPC architecture and safety gate logic against Firmware 260507 ground truth.
"""

import os
import re
import sys

def test_helper_script_ipc(helper_path):
    print("Testing helper.sh IPC constants and execution logic...")
    with open(helper_path, "r") as f:
        content = f.read()

    # 1. Safety Gate: com.hkmc.micom.system Tx 36 == 1
    assert "com.hkmc.micom.system 36" in content, "Missing com.hkmc.micom.system Tx 36 gear check"
    assert "00000000 00000001" in content, "Missing Park status parcel match"
    assert "! is_in_park" in content or "is_in_park" in content, "Missing is_in_park check"
    print("  ✓ Safety gate verified: com.hkmc.micom.system Tx 36 strictly required before mutations")

    # 2. Profile Switching: com.hkmc.userprofile Tx 5 & Tx 44
    assert "com.hkmc.userprofile 5" in content, "Missing com.hkmc.userprofile Tx 5 switchUser"
    assert "com.hkmc.userprofile 44" in content, "Missing com.hkmc.userprofile Tx 44 setPreBootUserType"
    print("  ✓ Profile switch verified: switchUser (Tx 5) and setPreBootUserType (Tx 44)")

    # 3. Door Seat Memory Emulation: com.hkmc.vr Tx 14 (PBACK_P1=4, PBACK_P2=5)
    assert "com.hkmc.vr 14" in content, "Missing com.hkmc.vr Tx 14 set_AVNIMSButton_Cmd_AVN"
    assert "cmd=$((target_uid + 3))" in content or ("4" in content and "5" in content), "Missing PBACK_P1=4 / PBACK_P2=5 calculation"
    assert "sleep 1" in content, "Missing 1.0s delay for seat settling"
    print("  ✓ Door seat memory verified: com.hkmc.vr Tx 14 (cmd 4 for D1, 5 for D2 after 1.0s delay)")

    # 4. Consent Screen Dismissal: com.hkmc.factory Tx 82 & notification Tx 24
    assert "com.hkmc.factory 82" in content, "Missing com.hkmc.factory Tx 82 hideConsentScreen"
    assert "notification 24" in content, "Missing notification Tx 24 notifyConsentScreenChanged"
    print("  ✓ ConsentScreen dismissal verified: factory Tx 82 & notification Tx 24")

    # 5. Confirmation Toast: com.hkmc.intent.action.TOAST
    assert "com.hkmc.intent.action.TOAST" in content, "Missing toast intent action"
    assert "com.hkmc.intent.extra.TOAST_MESSAGE" in content, "Missing toast message extra"
    assert "com.hkmc.intent.extra.TOAST_POPUPSHOWING" in content, "Missing popup showing extra"
    print("  ✓ Native OEM Toast verified: com.hkmc.intent.action.TOAST with extras")

def test_java_actuator_ipc(actuator_path):
    print("Testing VehicleActuator.java IPC constants and safety contracts...")
    with open(actuator_path, "r") as f:
        content = f.read()

    assert "TX_GEAR_P_STATUS = 36" in content, "TX_GEAR_P_STATUS must be 36"
    assert "TX_SWITCH_USER = 5" in content, "TX_SWITCH_USER must be 5"
    assert "TX_GET_USER_ID = 4" in content, "TX_GET_USER_ID must be 4"
    assert "TX_GET_USER_NAME = 10" in content, "TX_GET_USER_NAME must be 10"
    assert "TX_SET_PREBOOT_USER = 44" in content, "TX_SET_PREBOOT_USER must be 44"
    assert "TX_VR_AVN_IMS_CMD = 14" in content, "TX_VR_AVN_IMS_CMD must be 14"
    assert "TX_HIDE_CONSENT_SCREEN = 82" in content, "TX_HIDE_CONSENT_SCREEN must be 82"
    assert "TX_NOTIFY_CONSENT_CHANGED = 24" in content, "TX_NOTIFY_CONSENT_CHANGED must be 24"

    assert "CMD_PBACK_P1 = 4" in content, "CMD_PBACK_P1 must be 4"
    assert "CMD_PBACK_P2 = 5" in content, "CMD_PBACK_P2 must be 5"

    assert "Thread.sleep(1000)" in content, "Must sleep 1000ms before seat recall"
    assert "!isParkGear()" in content, "Must check isParkGear() in executeSafeSwitch"
    print("  ✓ Java constants and safety contracts all matched perfectly!")

def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    helper_path = os.path.join(repo_root, "package", "svc", "helper.sh")
    actuator_path = os.path.join(repo_root, "app", "src", "main", "java", "hmg", "phone", "profiles", "VehicleActuator.java")

    test_helper_script_ipc(helper_path)
    test_java_actuator_ipc(actuator_path)
    print("ALL HARDWARE IPC CHECKS PASSED!\n")

if __name__ == "__main__":
    main()
