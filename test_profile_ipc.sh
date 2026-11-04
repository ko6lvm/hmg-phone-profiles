#!/usr/bin/env bash
# ==============================================================================
# test_profile_ipc.sh — Hyundai/Kia Gen5W Feature & IPC Test Harness
# Target: 2024 Hyundai Ioniq 5 Limited (Android 4.4.2 / API 19 / Firmware 250607)
#
# SAFETY GATE: Every mutating command strictly verifies that the vehicle is in
# Park (P) via `com.hkmc.micom.system` Tx 36 (`getGearPStatus() == 1`) before
# executing any IPC, broadcast, or UI tap.
# ==============================================================================

set -euo pipefail

# Auto-detect adb across common macOS & Linux PATHs if not explicitly set
if [[ -z "${ADB_CMD:-}" ]]; then
    if command -v adb >/dev/null 2>&1; then
        ADB_CMD="adb"
    elif [[ -x "$HOME/Library/Android/sdk/platform-tools/adb" ]]; then
        ADB_CMD="$HOME/Library/Android/sdk/platform-tools/adb"
    elif [[ -x "/opt/homebrew/bin/adb" ]]; then
        ADB_CMD="/opt/homebrew/bin/adb"
    elif [[ -x "/usr/local/bin/adb" ]]; then
        ADB_CMD="/usr/local/bin/adb"
    else
        ADB_CMD="adb"
    fi
fi

usage() {
    cat <<'EOF'
Usage:
  # System & Gear Safety
  ./test_profile_ipc.sh gear-status
  ./test_profile_ipc.sh status

  # Profiles (Default method: binder [IUserProfileService.switchUser Tx 5])
  ./test_profile_ipc.sh get-profile
  ./test_profile_ipc.sh change-profile <1|2|0> [binder|external|broadcast|tap]

  # Seats (Door Memory Button / IMS Recall)
  ./test_profile_ipc.sh get-seats
  ./test_profile_ipc.sh change-seats <1|2> [vr|vr-raw|bcm|usm-ims|sys-ims|sys-seat]

  # Notifications / Toast
  ./test_profile_ipc.sh show-message "<message>"

  # Radios & Fingerprinting (Direct Binder IPC)
  ./test_profile_ipc.sh bt-fingerprint
  ./test_profile_ipc.sh wifi-fingerprint

  # ConsentScreen (Boot EULA)
  ./test_profile_ipc.sh consent-show [1|2|0]
  ./test_profile_ipc.sh consent-focus <1|2|0>
  ./test_profile_ipc.sh consent-hide [1|2|0]

  # Combined End-to-End Test
  ./test_profile_ipc.sh full-flow <1|2> [seat-method]

User IDs:
  1 = Driver 1
  2 = Driver 2
  0 = Guest

Seat Recall Methods (for change-seats <1|2> [method]):
  vr      = IVRService.set_AVNIMSButton_Cmd_AVN (com.hkmc.vr Tx 14, PBACK_P1=4 / PBACK_P2=5) [CONFIRMED DEFAULT]
  vr-raw  = IVRService.set_AVNIMSButton_Cmd_AVN (com.hkmc.vr Tx 14, raw 1 / 2)
  bcm     = IBCMService.requestWindowAndIMSCmd (com.hkmc.micom.bcm Tx 51, PBACK_P1=4 / PBACK_P2=5)
  usm-ims = IUSMService.SetIMSProfileNValue (com.hkmc.micom.usm Tx 161, 1 / 2)
  sys-ims = ISystemService.requestIMSData (com.hkmc.micom.system Tx 63, 1 / 2)
  sys-seat= ISystemService.requestSeatPositioningData (com.hkmc.micom.system Tx 67, 1 / 2)
EOF
    exit 1
}

# Run adb shell command cleanly without hiding errors
adb_exec() {
    $ADB_CMD shell "$@" 2>&1 | tr -d '\r'
}

# Decode a UTF-16LE String from Android `service call` Parcel hex output
decode_parcel_str() {
    local raw="$1"
    local cleaned
    cleaned=$(echo "$raw" | sed "s/Result: Parcel(//g; s/'[^']*'//g; s/0x[0-9a-fA-F]*://g; s/[^0-9a-fA-F ]/ /g")
    local words=($cleaned)
    if [[ ${#words[@]} -lt 2 ]]; then
        echo "<none>"
        return
    fi
    local len_hex="${words[1]}"
    if [[ "$len_hex" == "ffffffff" || "$len_hex" == "FFFFFFFF" ]]; then
        echo "<null>"
        return
    fi
    local len=$((16#$len_hex))
    if [[ $len -le 0 ]]; then
        echo "<empty>"
        return
    fi
    local out=""
    local count=0
    local i=2
    while [[ $i -lt ${#words[@]} && $count -lt $len ]]; do
        local w="${words[$i]}"
        if [[ ${#w} -eq 8 ]]; then
            local c1_hex="${w:6:2}"
            local c2_hex="${w:2:2}"
            if [[ "$c1_hex" != "00" && $count -lt $len ]]; then
                out+=$(printf "\\x$c1_hex")
                count=$((count + 1))
            fi
            if [[ "$c2_hex" != "00" && $count -lt $len ]]; then
                out+=$(printf "\\x$c2_hex")
                count=$((count + 1))
            fi
        fi
        i=$((i + 1))
    done
    echo "$out"
}

# Decode a 32-bit int from Android `service call` Parcel hex output
decode_parcel_int() {
    local raw="$1"
    local cleaned
    cleaned=$(echo "$raw" | sed "s/Result: Parcel(//g; s/'[^']*'//g; s/0x[0-9a-fA-F]*://g; s/[^0-9a-fA-F ]/ /g")
    local words=($cleaned)
    if [[ ${#words[@]} -lt 2 ]]; then
        echo "<none>"
        return
    fi
    echo "$((16#${words[1]}))"
}

call_str_service() {
    local svc="$1"
    local tx="$2"
    shift 2
    local raw
    raw=$(adb_exec service call "$svc" "$tx" "$@")
    local decoded
    decoded=$(decode_parcel_str "$raw")
    if [[ "$decoded" == "<none>" && -n "$raw" ]]; then
        echo "$raw"
    else
        echo "$decoded"
    fi
}

call_int_service() {
    local svc="$1"
    local tx="$2"
    shift 2
    local raw
    raw=$(adb_exec service call "$svc" "$tx" "$@")
    local decoded
    decoded=$(decode_parcel_int "$raw")
    echo "$decoded  [raw: $raw]"
}

# Verify vehicle is in Park (P) via com.hkmc.micom.system Tx 36 (getGearPStatus)
require_park_gear() {
    local parcel
    parcel=$(adb_exec service call com.hkmc.micom.system 36)
    if echo "$parcel" | grep -q "00000000 00000001"; then
        echo "[SAFE] Gear P verified (ISystemService.getGearPStatus == 1)."
        return 0
    fi
    echo "[ABORT] SAFETY LOCK: Vehicle is NOT in Park (P)!" >&2
    echo "        Response from com.hkmc.micom.system Tx 36: $parcel" >&2
    exit 2
}

get_current_user_id() {
    local parcel
    parcel=$(adb_exec service call com.hkmc.userprofile 4)
    if echo "$parcel" | grep -q "00000000 00000001"; then
        echo "1"
    elif echo "$parcel" | grep -q "00000000 00000002"; then
        echo "2"
    elif echo "$parcel" | grep -q "00000000 00000000"; then
        echo "0"
    else
        echo "unknown ($parcel)"
    fi
}

validate_user_id() {
    local uid="$1"
    if [[ "$uid" != "0" && "$uid" != "1" && "$uid" != "2" ]]; then
        echo "[ERROR] Invalid userType '$uid'." >&2
        echo "        Must specify an individual profile: '1' (Driver 1), '2' (Driver 2), or '0' (Guest)." >&2
        exit 1
    fi
}

validate_seat_preset() {
    local preset="$1"
    if [[ "$preset" != "1" && "$preset" != "2" ]]; then
        echo "[ERROR] Invalid seat memory preset '$preset'." >&2
        echo "        Must specify an individual memory preset: '1' (Memory 1) or '2' (Memory 2)." >&2
        exit 1
    fi
}

dispatch_seat_recall() {
    local preset="$1"
    local method="${2:-vr}"
    # AVNIMSButtonType enum in com.hkmc.bcm.BCMConstants:
    #   MEM_P1=1, MEM_P2=2, MEM_P3=3, PBACK_P1=4, PBACK_P2=5, PBACK_P3=6
    local pback_cmd=$((preset + 3))

    case "$method" in
        vr)
            echo "[EXEC] Method 'vr': IVRService.set_AVNIMSButton_Cmd_AVN($pback_cmd [PBACK_P$preset]) (com.hkmc.vr Tx 14 -> C_AVNIMSButtonCmd)..."
            adb_exec service call com.hkmc.vr 14 i32 "$pback_cmd"
            ;;
        vr-raw)
            echo "[EXEC] Method 'vr-raw': IVRService.set_AVNIMSButton_Cmd_AVN($preset) (com.hkmc.vr Tx 14 -> C_AVNIMSButtonCmd)..."
            adb_exec service call com.hkmc.vr 14 i32 "$preset"
            ;;
        bcm)
            echo "[EXEC] Method 'bcm': IBCMService.requestWindowAndIMSCmd(0, 0, 0, 0, $pback_cmd [PBACK_P$preset]) (com.hkmc.micom.bcm Tx 51)..."
            adb_exec service call com.hkmc.micom.bcm 51 i32 0 i32 0 i32 0 i32 0 i32 "$pback_cmd"
            ;;
        vr-all)
            echo "[EXEC] Method 'vr-all': IVRService.All_IMS_Req($preset) (com.hkmc.vr Tx 21 -> All_IMS_Req)..."
            adb_exec service call com.hkmc.vr 21 i32 "$preset"
            ;;
        usm-ims)
            echo "[EXEC] Method 'usm-ims': IUSMService.SetIMSProfileNValue($preset) (com.hkmc.micom.usm Tx 161 -> MICOM 0x1115 param 8)..."
            adb_exec service call com.hkmc.micom.usm 161 i32 "$preset"
            ;;
        sys-ims)
            echo "[EXEC] Method 'sys-ims': ISystemService.requestIMSData($preset) (com.hkmc.micom.system Tx 63 -> SYS_IMS_DATA_C_REQ)..."
            adb_exec service call com.hkmc.micom.system 63 i32 "$preset"
            ;;
        sys-seat)
            echo "[EXEC] Method 'sys-seat': ISystemService.requestSeatPositioningData($preset) (com.hkmc.micom.system Tx 67 -> SYS_SEAT_POSITIONING_C_REQ)..."
            adb_exec service call com.hkmc.micom.system 67 i32 "$preset"
            ;;
        *)
            echo "[ERROR] Unknown seat method '$method'. Options: vr, vr-raw, bcm, vr-all, usm-ims, sys-ims, sys-seat" >&2
            exit 1
            ;;
    esac
}

cmd="${1:-}"
[[ -z "$cmd" ]] && usage

case "$cmd" in
    # --------------------------------------------------------------------------
    # 1. Gear Status & Overall Status
    # --------------------------------------------------------------------------
    gear-status)
        echo "=== Checking Gear Status (com.hkmc.micom.system Tx 36: getGearPStatus) ==="
        parcel=$(adb_exec service call com.hkmc.micom.system 36)
        echo "$parcel"
        if echo "$parcel" | grep -q "00000000 00000001"; then
            echo "Status: PARK (P) [MUTATING ACTIONS ALLOWED]"
        else
            echo "Status: NOT IN PARK [MUTATING ACTIONS BLOCKED]"
        fi
        ;;

    status)
        echo "=== 1. Gear State (com.hkmc.micom.system Tx 36) ==="
        adb_exec service call com.hkmc.micom.system 36
        echo ""
        echo "=== 2. Active User Profile (com.hkmc.userprofile Tx 4: getUserId) ==="
        cur_uid=$(get_current_user_id)
        echo "Active userType: $cur_uid"
        echo ""
        echo "=== 3. Configured Profile Names (com.hkmc.userprofile Tx 10: getUserName) ==="
        echo "Driver 1 (1): $(call_str_service com.hkmc.userprofile 10 i32 1)"
        echo "Driver 2 (2): $(call_str_service com.hkmc.userprofile 10 i32 2)"
        echo "Guest    (0): $(call_str_service com.hkmc.userprofile 10 i32 0)"
        echo ""
        echo "=== 4. IMS / Seat Memory Option & State ==="
        echo "VR  get_VR_IMS_Option (Tx 6):          $(call_int_service com.hkmc.vr 6)"
        echo "BCM getIMSOption (Tx 49):              $(call_int_service com.hkmc.micom.bcm 49)"
        echo "USM getUserProfile_IMSRValue (Tx 485): $(call_int_service com.hkmc.micom.usm 485)"
        echo ""
        echo "=== 5. ConsentScreen System Properties ==="
        echo "sys.boot.show_screen:    $(adb_exec getprop sys.boot.show_screen)"
        echo "sys.boot.enabled_screen: $(adb_exec getprop sys.boot.enabled_screen)"
        echo "sys.boot.confirm_screen: $(adb_exec getprop sys.boot.confirm_screen)"
        echo ""
        echo "=== 6. Top Window / Focused App ==="
        adb_exec dumpsys window windows | grep -iE "mCurrentFocus|mFocusedApp|ConsentScreen" || true
        ;;

    # --------------------------------------------------------------------------
    # 2. User Profiles
    # --------------------------------------------------------------------------
    get-profile)
        echo "=== User Profile Details ==="
        echo "Active userType (Tx 4):     $(get_current_user_id)"
        echo "Pre-boot userType (Tx 43):  $(call_int_service com.hkmc.userprofile 43)"
        echo "Profile status (Tx 48):     $(call_int_service com.hkmc.userprofile 48)"
        echo "Driver 1 Name (Tx 10):      $(call_str_service com.hkmc.userprofile 10 i32 1)"
        echo "Driver 2 Name (Tx 10):      $(call_str_service com.hkmc.userprofile 10 i32 2)"
        echo "Guest Name (Tx 10):         $(call_str_service com.hkmc.userprofile 10 i32 0)"
        ;;

    change-profile)
        uid="${2:-}"
        method="${3:-binder}"
        validate_user_id "$uid"
        require_park_gear

        before_uid=$(get_current_user_id)
        echo "[INFO] Current active userType before switch: $before_uid"

        case "$method" in
            binder)
                echo "[EXEC] Calling IUserProfileService.switchUser($uid, false, false) [com.hkmc.userprofile Tx 5]..."
                adb_exec service call com.hkmc.userprofile 5 i32 "$uid" i32 0 i32 0
                ;;
            external)
                echo "[EXEC] Calling IUserProfileService.setUserTypeFromExternal($uid, fromWhere=3 [Digital Key]) [com.hkmc.userprofile Tx 6]..."
                adb_exec service call com.hkmc.userprofile 6 i32 "$uid" i32 3
                ;;
            broadcast)
                echo "[EXEC] Broadcasting com.mobis.intent.switchUser.digitalKey (userType=$uid)..."
                adb_exec am broadcast -a com.mobis.intent.switchUser.digitalKey --ei userType "$uid"
                ;;
            tap)
                echo "[EXEC] Executing fallback tap on ConsentScreen for profile $uid..."
                case "$uid" in
                    1) tap_x=234; tap_y=180 ;;
                    2) tap_x=234; tap_y=450 ;;
                    0) tap_x=234; tap_y=621 ;;
                esac
                adb_exec input tap $tap_x $tap_y
                sleep 1
                adb_exec input tap 825 660 # Confirm button
                ;;
            *)
                echo "[ERROR] Unknown method '$method'. Options: binder, external, broadcast, tap" >&2
                exit 1
                ;;
        esac

        # Update pre-boot profile for next ignition cycle
        adb_exec service call com.hkmc.userprofile 44 i32 "$uid" >/dev/null || true
        sleep 1
        echo "[DONE] Active userType is now: $(get_current_user_id) (Name: $(call_str_service com.hkmc.userprofile 10 i32 "$uid"))"
        ;;

    # --------------------------------------------------------------------------
    # 3. Seats (Physical Door Memory Button / IMS Emulation)
    # --------------------------------------------------------------------------
    change-seats)
        preset="${2:-}"
        method="${3:-vr}"
        validate_seat_preset "$preset"
        require_park_gear
        dispatch_seat_recall "$preset" "$method"
        echo "[DONE] Dispatched Door Memory $preset recall via '$method'."
        ;;

    get-seats)
        echo "=== Integrated Memory System (IMS) & Seat State ==="
        echo "1. VR  get_VR_IMS_Option (com.hkmc.vr Tx 6):                 $(call_int_service com.hkmc.vr 6)"
        echo "2. BCM getIMSOption (com.hkmc.micom.bcm Tx 49):              $(call_int_service com.hkmc.micom.bcm 49)"
        echo "3. USM getUserProfile_IMSRValue (com.hkmc.micom.usm Tx 485): $(call_int_service com.hkmc.micom.usm 485)"
        echo "4. USM getAllSeatMoving (com.hkmc.micom.usm Tx 595):         $(call_int_service com.hkmc.micom.usm 595)"
        ;;

    # --------------------------------------------------------------------------
    # 4. Notifications / Toast
    # --------------------------------------------------------------------------
    show-message|toast)
        msg="${2:-Switched to Driver 1}"
        echo "[EXEC] Broadcasting native OEM Toast: '$msg'..."
        adb_exec am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "$msg" --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true
        echo "[DONE] Toast broadcast dispatched (renders globally for ~5s across all screens)."
        ;;

    # --------------------------------------------------------------------------
    # 5. Radio Fingerprinting (Bluetooth & Wi-Fi)
    # --------------------------------------------------------------------------
    bt-fingerprint)
        echo "=== Bluetooth & PhoneProjection Binder State (Fast IPC) ==="
        echo "1. Bluetooth Manager (Binder service: bluetooth_manager):"
        echo "   isEnabled (Tx 5):                     $(call_int_service bluetooth_manager 5)"
        echo "   Head Unit Local BT MAC (Tx 22):       $(call_str_service bluetooth_manager 22)"
        echo "   Head Unit Local BT Name (Tx 23):      $(call_str_service bluetooth_manager 23)"
        echo "   Connected HFP Phone MAC (Tx 17):      $(call_str_service bluetooth_manager 17)"
        echo ""
        echo "2. PhoneProjection Manager (Binder service: phoneprojection):"
        echo "   Connected Device Name (Tx 4):         $(call_str_service phoneprojection 4)"
        echo "   Connected Device BT MAC (Tx 5):       $(call_str_service phoneprojection 5)"
        echo "   CarPlay Connected BT MAC (Tx 8):      $(call_str_service phoneprojection 8)"
        echo "   Android Auto Connected BT MAC (Tx 9): $(call_str_service phoneprojection 9)"
        echo "   BT HFP Connected Device (Tx 21):      $(call_str_service phoneprojection 21)"
        echo "   BT A2DP-1 Connected Device (Tx 23):   $(call_str_service phoneprojection 23)"
        echo "   BT A2DP-2 Connected Device (Tx 25):   $(call_str_service phoneprojection 25)"
        echo "   Playing BT Audio Device (Tx 27):      $(call_str_service phoneprojection 27)"
        echo "   Wireless Connect State (Tx 77):       $(call_int_service phoneprojection 77)"
        echo ""
        echo "3. DiPO / CarPlay Manager (Binder service: dipo):"
        echo "   DiPO Connect Status (Tx 8):           $(call_int_service dipo 8)"
        echo "   Last CarPlay Address (Tx 14):         $(call_str_service dipo 14)"
        ;;

    wifi-fingerprint)
        echo "=== Wi-Fi Subsystem State & Hotspot Clients (/proc/net) ==="
        echo "1. Connected Stations (/proc/net/arp):"
        adb_exec cat /proc/net/arp
        echo ""
        echo "2. Active Projection Sockets (/proc/net/tcp):"
        echo "   (Searching for Port 5288 [Wireless Android Auto] / CarPlay TCP connections)"
        adb_exec cat /proc/net/tcp | head -n 25
        echo ""
        echo "3. Wi-Fi Interface State:"
        echo "wlan.driver.status: $(adb_exec getprop wlan.driver.status)"
        adb_exec netcfg | grep -i "wlan" || true
        ;;

    # --------------------------------------------------------------------------
    # 6. ConsentScreen (Boot Splash EULA)
    # --------------------------------------------------------------------------
    consent-show)
        uid="${2:-$(get_current_user_id)}"
        validate_user_id "$uid"
        require_park_gear
        echo "[EXEC] Triggering ConsentScreen (com.mobis.user_profile.intent.action.SHOW_CONSENT, userType=$uid)..."
        adb_exec am broadcast -a com.mobis.user_profile.intent.action.SHOW_CONSENT --ei userType "$uid"
        ;;

    consent-focus)
        uid="${2:-1}"
        validate_user_id "$uid"
        require_park_gear
        echo "[EXEC] Highlighting Driver $uid on ConsentScreen (com.mobis.intent.action.CHANGE_FOCUS_CONSENT)..."
        adb_exec am broadcast -a com.mobis.intent.action.CHANGE_FOCUS_CONSENT --ei userType "$uid" --ei fromWhere 3
        ;;

    consent-hide)
        uid="${2:-$(get_current_user_id)}"
        validate_user_id "$uid"
        require_park_gear
        echo "[EXEC] Calling IMicomFactoryService.hideConsentScreen() [Tx 82]..."
        adb_exec service call com.hkmc.factory 82
        echo "[EXEC] Calling INotificationManager.notifyConsentScreenChanged(1, $uid) [Tx 24]..."
        adb_exec service call notification 24 i32 1 i32 "$uid"
        echo "[DONE] ConsentScreen dismissed."
        ;;

    # --------------------------------------------------------------------------
    # 7. Combined Full Integration Flow
    # --------------------------------------------------------------------------
    full-flow)
        uid="${2:-}"
        seat_method="${3:-vr}"
        validate_user_id "$uid"
        require_park_gear

        echo ">>> Executing Full Auto-Switch Flow for Driver $uid in Park <<<"

        # 1. Switch user profile
        echo "[Step 1] Switching profile to Driver $uid (com.hkmc.userprofile Tx 5: switchUser)..."
        adb_exec service call com.hkmc.userprofile 5 i32 "$uid" i32 0 i32 0 >/dev/null
        adb_exec service call com.hkmc.userprofile 44 i32 "$uid" >/dev/null || true

        # 2. Dismiss ConsentScreen if present
        echo "[Step 2] Dismissing startup screen (com.hkmc.factory Tx 82 + notification Tx 24)..."
        adb_exec service call com.hkmc.factory 82 >/dev/null || true
        adb_exec service call notification 24 i32 1 i32 "$uid" >/dev/null || true

        # 3. Seat memory recall (if Driver 1 or Driver 2)
        # Recalled AFTER switchUser so the Door Memory preset overrides Hyundai's stock profile seat position
        if [[ "$uid" == "1" || "$uid" == "2" ]]; then
            sleep 1
            echo "[Step 3] Recalling Door Memory Button $uid via '$seat_method'..."
            dispatch_seat_recall "$uid" "$seat_method" >/dev/null
        fi

        # 4. Display 5-second native OEM Toast
        drv_name=$(call_str_service com.hkmc.userprofile 10 i32 "$uid")
        if [[ "$drv_name" == "<null>" || "$drv_name" == "<empty>" || "$drv_name" == "<none>" ]]; then
            drv_name="Driver $uid"
        fi
        echo "[Step 4] Displaying 5-second toast notification ('Switched to $drv_name')..."
        adb_exec am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "Switched to $drv_name" --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null

        echo "[SUCCESS] Full flow complete. Active profile: $(get_current_user_id) ($drv_name)"
        ;;

    *)
        usage
        ;;
esac
