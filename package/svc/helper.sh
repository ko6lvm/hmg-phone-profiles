#!/system/bin/sh
# ==============================================================================
# helper.sh — Root Service Daemon for autoprofile.selector
# Target: 2024 Hyundai Ioniq 5 Limited (Gen5W, Android 4.4.2 KitKat, Build 260507)
# Runs as UID 0 under NEMESIS svcmgr (mode=restart)
#
# HARDWARE IPC GROUND TRUTH:
#   Gear Safety:     com.hkmc.micom.system Tx 36 (ISystemService.getGearPStatus == 1)
#   Profile Switch:  com.hkmc.userprofile Tx 5 (switchUser) & Tx 44 (setPreBootUserType)
#   Profile Query:   com.hkmc.userprofile Tx 4 (getUserId) & Tx 10 (getUserName)
#   Seat Memory:     com.hkmc.vr Tx 14 (set_AVNIMSButton_Cmd_AVN: 4=D1 / 5=D2)
#   Consent Hide:    com.hkmc.factory Tx 82 & notification Tx 24
#   Native Toast:    com.hkmc.intent.action.TOAST
# ==============================================================================

export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin:$PATH

PKG_DIR="/data/nemesis/apps/autoprofile.selector"
DATA_DIR="$PKG_DIR/data"
CONFIG_FILE="$PKG_DIR/config.json"
FALLBACK_CONFIG="/data/local/tmp/autoprofile_config.json"
PID_FILE="$DATA_DIR/helper.pid"
FALLBACK_PID="/data/local/tmp/autoprofile_helper.pid"
STATE_FILE="$DATA_DIR/state.json"
FALLBACK_STATE="/data/local/tmp/autoprofile_state.json"

mkdir -p "$DATA_DIR" 2>/dev/null || true
chmod 777 "$DATA_DIR" 2>/dev/null || true

# ------------------------------------------------------------------------------
# Parcel String Decoder (UTF-16LE from service call hex output)
# ------------------------------------------------------------------------------

decode_parcel_str() {
    raw="$1"
    cleaned=$(echo "$raw" | sed "s/Result: Parcel(//g; s/'[^']*'//g; s/0x[0-9a-fA-F]*://g; s/[^0-9a-fA-F ]/ /g")
    words=($cleaned)
    if [ ${#words[@]} -lt 2 ]; then
        return
    fi
    len_hex="${words[1]}"
    if [ "$len_hex" = "ffffffff" ] || [ "$len_hex" = "FFFFFFFF" ]; then
        return
    fi
    len=$((16#$len_hex))
    if [ $len -le 0 ] || [ $len -gt 256 ]; then
        return
    fi
    out=""
    count=0
    i=2
    while [ $i -lt ${#words[@]} ] && [ $count -lt $len ]; do
        w="${words[$i]}"
        if [ ${#w} -eq 8 ]; then
            c1_hex="${w:6:2}"
            c2_hex="${w:2:2}"
            if [ "$c1_hex" != "00" ] && [ $count -lt $len ]; then
                out+=$(printf "\\x$c1_hex")
                count=$((count + 1))
            fi
            if [ "$c2_hex" != "00" ] && [ $count -lt $len ]; then
                out+=$(printf "\\x$c2_hex")
                count=$((count + 1))
            fi
        fi
        i=$((i + 1))
    done
    echo "$out"
}

# ------------------------------------------------------------------------------
# IPC & Safety Verification
# ------------------------------------------------------------------------------

# Returns 0 if vehicle is strictly in Park (P), 1 otherwise
is_in_park() {
    parcel=$(service call com.hkmc.micom.system 36 2>/dev/null || true)
    if echo "$parcel" | grep -q "00000000 00000001"; then
        return 0
    fi
    return 1
}

# Returns active user ID (1 = Driver 1, 2 = Driver 2, 0 = Guest, -1 = unknown)
get_active_profile() {
    parcel=$(service call com.hkmc.userprofile 4 2>/dev/null || true)
    if echo "$parcel" | grep -q "00000000 00000001"; then
        echo "1"
    elif echo "$parcel" | grep -q "00000000 00000002"; then
        echo "2"
    elif echo "$parcel" | grep -q "00000000 00000000"; then
        echo "0"
    else
        echo "-1"
    fi
}

# Returns configured driver name
get_profile_name() {
    uid="$1"
    raw=$(service call com.hkmc.userprofile 10 i32 "$uid" 2>/dev/null || true)
    name=$(decode_parcel_str "$raw")
    if [ -n "$name" ] && [ "$name" != "<null>" ] && [ "$name" != "<empty>" ]; then
        echo "$name"
        return
    fi
    case "$uid" in
        1) echo "Driver 1" ;;
        2) echo "Driver 2" ;;
        0) echo "Guest" ;;
        *) echo "Unknown" ;;
    esac
}

# ------------------------------------------------------------------------------
# Mutating Flow (Strictly Gated by Park Gear)
# ------------------------------------------------------------------------------

execute_switch_flow() {
    target_uid="$1"
    dismiss_notice="${2:-false}"
    show_toast="${3:-true}"
    target_name=$(get_profile_name "$target_uid")

    echo "[ACTION] Requesting profile switch to Driver $target_uid ($target_name)..."

    # STRICT SAFETY GATE: Verify Park (P)
    if ! is_in_park; then
        echo "[ABORT] SAFETY GATE: Vehicle is NOT in Park (P)! All mutating actions blocked."
        if [ "$show_toast" = "true" ]; then
            am broadcast -a com.hkmc.intent.action.TOAST \
                -e com.hkmc.intent.extra.TOAST_MESSAGE "Action blocked: Vehicle not in Park" \
                --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1 || true
        fi
        return 1
    fi

    # 1. In-session Profile Switch (IUserProfileService.switchUser [Tx 5])
    echo "[STEP 1] IUserProfileService.switchUser($target_uid, false, false)..."
    service call com.hkmc.userprofile 5 i32 "$target_uid" i32 0 i32 0 >/dev/null 2>&1

    # 2. Update Pre-boot Profile for Next Ignition Cycle (Tx 44)
    service call com.hkmc.userprofile 44 i32 "$target_uid" >/dev/null 2>&1 || true

    # 3. Dismiss Startup Consent Screen if enabled
    if [ "$dismiss_notice" = "true" ]; then
        echo "[STEP 2] Dismissing ConsentScreen (factory Tx 82 & notification Tx 24)..."
        service call com.hkmc.factory 82 >/dev/null 2>&1 || true
        service call notification 24 i32 1 i32 "$target_uid" >/dev/null 2>&1 || true
    fi

    # 4. Recall Physical Door Memory Button (after 1.0s delay to override stock USM)
    if [ "$target_uid" = "1" ] || [ "$target_uid" = "2" ]; then
        sleep 1
        # PBACK_P1 = 4, PBACK_P2 = 5 (IVRService.set_AVNIMSButton_Cmd_AVN [Tx 14])
        cmd=$((target_uid + 3))
        echo "[STEP 3] Emulating Door Memory Button $target_uid (cmd=$cmd)..."
        service call com.hkmc.vr 14 i32 "$cmd" >/dev/null 2>&1 || true
    fi

    # 5. Native OEM Toast Notification (~5s global across all screens)
    if [ "$show_toast" = "true" ]; then
        echo "[STEP 4] Broadcasting native OEM Toast..."
        am broadcast -a com.hkmc.intent.action.TOAST \
            -e com.hkmc.intent.extra.TOAST_MESSAGE "Switched to $target_name" \
            --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1 || true
    fi

    echo "[SUCCESS] Profile switch to Driver $target_uid completed in Park."
    return 0
}

# ------------------------------------------------------------------------------
# Radio Fingerprinting (Bluetooth & Wi-Fi ARP / TCP)
# ------------------------------------------------------------------------------

get_connected_bt_macs() {
    bt_macs=""
    # 1. bluetooth_manager Tx 17 (Connected HFP Phone MAC)
    raw1=$(service call bluetooth_manager 17 2>/dev/null || true)
    # 2. phoneprojection Tx 5 (Connected Device BT MAC)
    raw2=$(service call phoneprojection 5 2>/dev/null || true)
    # 3. phoneprojection Tx 8 (CarPlay BT MAC)
    raw3=$(service call phoneprojection 8 2>/dev/null || true)
    # 4. phoneprojection Tx 9 (Android Auto BT MAC)
    raw4=$(service call phoneprojection 9 2>/dev/null || true)
    # 5. dipo Tx 14 (CarPlay Address)
    raw5=$(service call dipo 14 2>/dev/null || true)

    for raw in "$raw1" "$raw2" "$raw3" "$raw4" "$raw5"; do
        decoded=$(decode_parcel_str "$raw")
        mac=$(echo "$decoded" | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | tr '[:lower:]' '[:upper:]' | head -n 1)
        if [ -n "$mac" ]; then
            bt_macs="$bt_macs $mac"
        fi
    done

    # Secondary fallback: dumpsys bluetooth connected devices
    dump=$(dumpsys bluetooth 2>/dev/null || dumpsys bluetooth_manager 2>/dev/null || true)
    if [ -n "$dump" ]; then
        dump_macs=$(echo "$dump" | grep -iE 'connected|mConnectedDevices' | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | tr '[:lower:]' '[:upper:]' || true)
        for dmac in $dump_macs; do
            bt_macs="$bt_macs $dmac"
        done
    fi

    echo "$bt_macs" | tr ' ' '\n' | sort -u | tr '\n' ' '
}

get_connected_wifi_macs() {
    if [ -f /proc/net/arp ]; then
        # Parse station MACs with Flag 0x2 (completed ARP entry)
        awk '$3 == "0x2" {
            mac = toupper($4)
            if (mac != "00:00:00:00:00:00" && mac ~ /^([0-9A-F]{2}:){5}[0-9A-F]{2}$/) {
                print mac
            }
        }' /proc/net/arp 2>/dev/null | sort -u | tr '\n' ' '
    fi
}

has_active_projection_tcp() {
    # Port 5288 in hex is 14A8 (Wireless Android Auto)
    if [ -f /proc/net/tcp ]; then
        if grep -q ":14A8" /proc/net/tcp 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

# ------------------------------------------------------------------------------
# Configuration Synchronization & Parsing
# ------------------------------------------------------------------------------

sync_and_get_config_path() {
    # If fallback config is newer, sync back to primary config
    if [ -f "$FALLBACK_CONFIG" ]; then
        if [ ! -f "$CONFIG_FILE" ] || [ "$FALLBACK_CONFIG" -nt "$CONFIG_FILE" ]; then
            cp -f "$FALLBACK_CONFIG" "$CONFIG_FILE" 2>/dev/null || true
        fi
    fi

    if [ -f "$CONFIG_FILE" ]; then
        echo "$CONFIG_FILE"
    elif [ -f "$FALLBACK_CONFIG" ]; then
        echo "$FALLBACK_CONFIG"
    else
        echo ""
    fi
}

# Extracts phone entries as "name|bt_mac|wifi_mac|assigned_driver|priority"
parse_configured_phones() {
    cfg_file="$1"
    if [ -f "$cfg_file" ]; then
        sed 's/[{}]/\n&\n/g; s/,/\n/g' "$cfg_file" 2>/dev/null | awk '
        /"name":/ {
            s = $0; sub(/^[ \t]*"name":[ \t]*"/, "", s); sub(/",?[ \t]*$/, "", s); name = s
        }
        /"bt_mac":/ {
            s = $0; sub(/^[ \t]*"bt_mac":[ \t]*"/, "", s); sub(/",?[ \t]*$/, "", s); bt = toupper(s)
        }
        /"wifi_mac":/ {
            if ($0 ~ /null/) { wifi = "" }
            else {
                s = $0; sub(/^[ \t]*"wifi_mac":[ \t]*"/, "", s); sub(/",?[ \t]*$/, "", s); wifi = toupper(s)
            }
        }
        /"assigned_driver":/ {
            s = $0; sub(/^[ \t]*"assigned_driver":[ \t]*/, "", s); sub(/,?[ \t]*$/, "", s); driver = s
        }
        /"priority":/ {
            s = $0; sub(/^[ \t]*"priority":[ \t]*/, "", s); sub(/,?[ \t]*$/, "", s); prio = s
            if (bt != "" || wifi != "") {
                print name "|" bt "|" wifi "|" driver "|" prio
            }
            name = ""; bt = ""; wifi = ""; driver = 0; prio = 0
        }
        ' 2>/dev/null
    else
        # Default fallback entries
        echo "Pixel 11 Pro XL|AA:BB:CC:11:22:33|02:00:00:11:22:33|1|1"
        echo "iPhone Duo|DD:EE:FF:44:55:66|02:00:00:44:55:66|2|2"
        echo "Samsung S26 Ultra|11:22:33:AA:BB:CC||0|0"
    fi
}

persist_learned_wifi_mac() {
    target_bt="$1"
    learned_wifi="$2"
    cfg="$3"
    if [ -z "$cfg" ] || [ ! -f "$cfg" ]; then return; fi

    # Update config.json safely for both single-line and multi-line formats
    awk -v bt="$target_bt" -v w="$learned_wifi" '
    {
        if ($0 ~ bt) {
            if ($0 ~ /"wifi_mac"/) {
                sub(/"wifi_mac":[ \t]*null/, "\"wifi_mac\": \"" w "\"")
                sub(/"wifi_mac":[ \t]*""/, "\"wifi_mac\": \"" w "\"")
            } else {
                in_target = 1
            }
        } else if (in_target && /"wifi_mac":/) {
            sub(/null/, "\"" w "\"")
            sub(/""/, "\"" w "\"")
            in_target = 0
        }
        print
    }
    ' "$cfg" > "$cfg.tmp" 2>/dev/null && mv "$cfg.tmp" "$cfg" 2>/dev/null || rm -f "$cfg.tmp"

    chmod 666 "$cfg" 2>/dev/null || true
    cp -f "$cfg" "$FALLBACK_CONFIG" 2>/dev/null || true
    chmod 666 "$FALLBACK_CONFIG" 2>/dev/null || true
}

# ------------------------------------------------------------------------------
# State Synchronization
# ------------------------------------------------------------------------------

update_state_file() {
    in_p="false"
    if is_in_park; then in_p="true"; fi
    cur_p=$(get_active_profile)
    ts=$(date +%s 2>/dev/null || echo 0)

    state_json="{\"daemon\":\"RUNNING\",\"timestamp\":$ts,\"gear_park\":$in_p,\"active_profile\":$cur_p}"
    echo "$state_json" > "$STATE_FILE" 2>/dev/null || true
    echo "$state_json" > "$FALLBACK_STATE" 2>/dev/null || true
    chmod 666 "$STATE_FILE" 2>/dev/null || true
    chmod 666 "$FALLBACK_STATE" 2>/dev/null || true
}

# ------------------------------------------------------------------------------
# Daemon Main Loop
# ------------------------------------------------------------------------------

run_daemon() {
    echo "$$" > "$PID_FILE" 2>/dev/null || true
    echo "$$" > "$FALLBACK_PID" 2>/dev/null || true
    chmod 666 "$PID_FILE" 2>/dev/null || true
    chmod 666 "$FALLBACK_PID" 2>/dev/null || true

    echo "[autoprofile.selector] Daemon started with PID $$."

    trap 'echo "[autoprofile.selector] Shutting down..."; rm -f "$PID_FILE" "$FALLBACK_PID"; exit 0' SIGTERM SIGINT

    last_switched_driver=0

    while true; do
        update_state_file

        cfg=$(sync_and_get_config_path)

        auto_select=true
        dismiss_notice=false
        show_banner=true
        conflict_policy="p1"

        if [ -n "$cfg" ] && [ -f "$cfg" ]; then
            if grep -q '"auto_select":[ \t]*false' "$cfg" 2>/dev/null; then
                auto_select=false
            fi
            if grep -q '"dismiss_notice":[ \t]*true' "$cfg" 2>/dev/null; then
                dismiss_notice=true
            fi
            if grep -q '"show_banner":[ \t]*false' "$cfg" 2>/dev/null; then
                show_banner=false
            fi
            if grep -q '"conflict_policy":[ \t]*"tcp"' "$cfg" 2>/dev/null; then
                conflict_policy="tcp"
            elif grep -q '"conflict_policy":[ \t]*"manual"' "$cfg" 2>/dev/null; then
                conflict_policy="manual"
            fi
        fi

        # Fingerprint radios
        bt_macs=$(get_connected_bt_macs)
        wifi_macs=$(get_connected_wifi_macs)

        matched_count=0
        matched_drivers=""
        matched_priorities=""
        matched_names=""
        matched_bts=""
        matched_wifis=""

        phones_data=$(parse_configured_phones "$cfg")

        while IFS='|' read -r p_name p_bt p_wifi p_driver p_prio; do
            [ -z "$p_name" ] && continue
            p_bt_upper=$(echo "$p_bt" | tr '[:lower:]' '[:upper:]')
            p_wifi_upper=$(echo "$p_wifi" | tr '[:lower:]' '[:upper:]')

            is_match=false
            if [ -n "$p_bt_upper" ] && echo " $bt_macs " | grep -q " $p_bt_upper "; then
                is_match=true
            fi
            if [ -n "$p_wifi_upper" ] && echo " $wifi_macs " | grep -q " $p_wifi_upper "; then
                is_match=true
            fi

            if [ "$is_match" = "true" ]; then
                matched_count=$((matched_count + 1))
                matched_drivers="$matched_drivers $p_driver"
                matched_priorities="$matched_priorities $p_prio"
                matched_names="$matched_names;$p_name"
                matched_bts="$matched_bts $p_bt_upper"
                matched_wifis="$matched_wifis $p_wifi_upper"
            fi
        done <<EOF
$phones_data
EOF

        # Auto-learning: Single BT phone connected and a new Wi-Fi station appears
        if [ "$matched_count" -eq 1 ]; then
            m_bt=$(echo "$matched_bts" | awk '{print $1}')
            m_wifi=$(echo "$matched_wifis" | awk '{print $1}')
            m_name=$(echo "$matched_names" | sed 's/^;//')

            if [ -z "$m_wifi" ] && [ -n "$wifi_macs" ]; then
                for new_wmac in $wifi_macs; do
                    if [ "$new_wmac" != "00:00:00:00:00:00" ]; then
                        echo "[AUTO-LEARN] Auto-learned Wi-Fi MAC $new_wmac for $m_name (BT: $m_bt)"
                        persist_learned_wifi_mac "$m_bt" "$new_wmac" "$cfg"
                        break
                    fi
                done
            fi
        fi

        # Resolution based on matched count and conflict policy
        resolved_driver=0
        current_uid=$(get_active_profile)

        if [ "$matched_count" -eq 0 ]; then
            resolved_driver=0
        elif [ "$matched_count" -eq 1 ]; then
            resolved_driver=$(echo "$matched_drivers" | awk '{print $1}')
        else
            # Multiple phones matched: Apply conflict policy
            if [ "$conflict_policy" = "tcp" ]; then
                if has_active_projection_tcp; then
                    resolved_driver=1
                else
                    resolved_driver=1
                fi
            elif [ "$conflict_policy" = "manual" ]; then
                resolved_driver=$current_uid
            else
                # Default "p1": lowest positive priority number wins
                best_prio=999
                best_driver=1
                i=1
                for drv in $matched_drivers; do
                    prio=$(echo "$matched_priorities" | awk -v idx="$i" '{print $idx}')
                    if [ "$prio" -gt 0 ] && [ "$prio" -lt "$best_prio" ]; then
                        best_prio=$prio
                        best_driver=$drv
                    fi
                    i=$((i + 1))
                done
                resolved_driver=$best_driver
            fi
        fi

        # Execute switch if target driver changed and auto_select is active
        if [ "$auto_select" = "true" ] && [ "$resolved_driver" -gt 0 ]; then
            if [ "$current_uid" != "$resolved_driver" ]; then
                echo "[DETECT] Phone matched Driver $resolved_driver (Current: $current_uid). Gating on Park..."
                if is_in_park; then
                    execute_switch_flow "$resolved_driver" "$dismiss_notice" "$show_banner"
                    last_switched_driver="$resolved_driver"
                else
                    echo "[GATE] Mutating action deferred: Gear is not in Park (P)."
                fi
            fi
        fi

        sleep 3
    done
}

# ------------------------------------------------------------------------------
# CLI Dispatcher
# ------------------------------------------------------------------------------

cmd="${1:-run}"

case "$cmd" in
    source|import|noop)
        return 0 2>/dev/null || exit 0
        ;;
    decode)
        decode_parcel_str "$2"
        ;;
    parse-phones)
        cfg="${2:-$(sync_and_get_config_path)}"
        parse_configured_phones "$cfg"
        ;;
    learn)
        bt="$2"
        wifi="$3"
        cfg="${4:-$(sync_and_get_config_path)}"
        persist_learned_wifi_mac "$bt" "$wifi" "$cfg"
        ;;
    run)
        run_daemon
        ;;
    status)
        echo "=== autoprofile.selector Helper Status ==="
        pid=""
        for pf in "$PID_FILE" "$FALLBACK_PID"; do
            if [ -f "$pf" ]; then
                pid=$(cat "$pf" 2>/dev/null)
                break
            fi
        done
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "Daemon: RUNNING (PID $pid)"
        else
            echo "Daemon: STOPPED"
        fi
        if is_in_park; then
            echo "Gear: PARK (P) [MUTATING ALLOWED]"
        else
            echo "Gear: NOT IN PARK [MUTATING BLOCKED]"
        fi
        echo "Active Profile: $(get_active_profile) ($(get_profile_name $(get_active_profile)))"
        echo "BT Connected: $(get_connected_bt_macs)"
        echo "Wi-Fi Stations: $(get_connected_wifi_macs)"
        if has_active_projection_tcp; then
            echo "Active Projection: YES (Port 5288 / TCP)"
        else
            echo "Active Projection: NO"
        fi
        ;;
    gear)
        if is_in_park; then
            echo "PARK (1)"
            exit 0
        else
            echo "NOT_PARK (0)"
            exit 1
        fi
        ;;
    switch)
        target="${2:-1}"
        execute_switch_flow "$target" "false" "true"
        ;;
    seat)
        preset="${2:-1}"
        if ! is_in_park; then
            echo "[ABORT] Cannot recall seat: Vehicle not in Park (P)!"
            exit 1
        fi
        cmd=$((preset + 3))
        echo "Recalling Door Memory Button $preset (IVRService Tx 14 cmd=$cmd)..."
        service call com.hkmc.vr 14 i32 "$cmd"
        ;;
    consent)
        if ! is_in_park; then
            echo "[ABORT] Cannot hide consent screen: Vehicle not in Park (P)!"
            exit 1
        fi
        uid=$(get_active_profile)
        [ "$uid" -lt 0 ] && uid=1
        echo "Hiding ConsentScreen (factory Tx 82 & notification Tx 24)..."
        service call com.hkmc.factory 82
        service call notification 24 i32 1 i32 "$uid"
        ;;
    toast)
        msg="${2:-Switched to Driver 1}"
        echo "Broadcasting OEM Toast: '$msg'..."
        am broadcast -a com.hkmc.intent.action.TOAST \
            -e com.hkmc.intent.extra.TOAST_MESSAGE "$msg" \
            --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true
        ;;
    detect)
        echo "BT MACs: $(get_connected_bt_macs)"
        echo "Wi-Fi MACs: $(get_connected_wifi_macs)"
        if has_active_projection_tcp; then
            echo "Active Projection: YES (Port 5288 / TCP)"
        else
            echo "Active Projection: NO"
        fi
        ;;
    full-flow)
        target="${2:-1}"
        execute_switch_flow "$target" "true" "true"
        ;;
    *)
        echo "Usage: helper.sh [run|status|gear|switch <1|2|0>|seat <1|2>|consent|toast <msg>|detect|full-flow <1|2>]"
        exit 1
        ;;
esac
