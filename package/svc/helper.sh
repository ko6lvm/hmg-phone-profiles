#!/system/bin/sh
# ==============================================================================
# helper.sh — Root Service Daemon for hmg-phone-profiles
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

PKG_DIR="/data/nemesis/apps/hmg-phone-profiles"
LEGACY_PKG_DIR="/data/nemesis/apps/autoprofile.selector"
DATA_DIR="$PKG_DIR/data"
CONFIG_FILE="$PKG_DIR/config.json"
FALLBACK_CONFIG="/data/local/tmp/hmg_phone_profiles_config.json"
PID_FILE="$DATA_DIR/helper.pid"
FALLBACK_PID="/data/local/tmp/hmg_phone_profiles_helper.pid"
STATE_FILE="$DATA_DIR/state.json"
FALLBACK_STATE="/data/local/tmp/hmg_phone_profiles_state.json"

mkdir -p "$DATA_DIR" 2>/dev/null || true
chmod 777 "$DATA_DIR" 2>/dev/null || true

# ------------------------------------------------------------------------------
# Parcel String Decoder (UTF-16LE from service call hex output)
# ------------------------------------------------------------------------------

decode_parcel_str() {
    raw="$1"
    [ -z "$raw" ] && return
    echo "$raw" | awk '
    function hex2dec(h,   d, i, c) {
        d = 0; h = tolower(h)
        for (i = 1; i <= length(h); i++) {
            c = index("0123456789abcdef", substr(h, i, 1)) - 1
            if (c < 0) return 0
            d = d * 16 + c
        }
        return d
    }
    {
        sub(/.*Parcel\(/, "")
        sub(/\x27.*/, "")
        sub(/\).*/, "")
        n = split($0, words)
        if (n < 2) exit
        len_hex = tolower(words[2])
        if (len_hex == "ffffffff") exit
        len = hex2dec(len_hex)
        if (len <= 0 || len > 256) exit
        out = ""
        count = 0
        for (i = 3; i <= n && count < len; i++) {
            w = words[i]
            if (length(w) == 8) {
                c1_val = hex2dec(substr(w, 7, 2))
                c2_val = hex2dec(substr(w, 3, 2))
                if (c1_val > 0 && count < len) {
                    out = out sprintf("%c", c1_val)
                    count++
                }
                if (c2_val > 0 && count < len) {
                    out = out sprintf("%c", c2_val)
                    count++
                }
            }
        }
        print out
    }
    ' 2>/dev/null
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
    trigger_source="${4:-Manual}"
    target_name=$(get_profile_name "$target_uid")

    echo "[ACTION] Requesting profile switch to Driver $target_uid ($target_name) via $trigger_source..."

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
        toast_msg="${trigger_source} - Driver ${target_uid}"
        echo "[STEP 4] Broadcasting native OEM Toast: '$toast_msg'..."
        am broadcast -a com.hkmc.intent.action.TOAST \
            -e com.hkmc.intent.extra.TOAST_MESSAGE "$toast_msg" \
            --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1 || true
    fi

    mkdir -p "$DATA_DIR" 2>/dev/null || true
    echo "$target_uid" > "$DATA_DIR/last_switched_uid" 2>/dev/null || true
    date +%s > "$DATA_DIR/last_switched_ts" 2>/dev/null || true

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

    # Note: dipo Tx 14 is intentionally excluded because it stores the last paired
    # CarPlay address in NVRAM, which persists even when the phone is disconnected.

    for raw in "$raw1" "$raw2" "$raw3" "$raw4"; do
        decoded=$(decode_parcel_str "$raw")
        mac=$(echo "$decoded" | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | tr '[:lower:]' '[:upper:]' | head -n 1)
        if [ -n "$mac" ]; then
            bt_macs="$bt_macs $mac"
        fi
    done

    # Secondary fallback: dumpsys bluetooth ONLY when devices are actively connected
    # (Must not match disconnected devices or empty brackets mConnectedDevices: [])
    dump=$(dumpsys bluetooth 2>/dev/null || dumpsys bluetooth_manager 2>/dev/null || true)
    if [ -n "$dump" ]; then
        dump_macs=$(echo "$dump" | awk '
        /mConnectedDevices:[ \t]*\[/ {
            line = $0
            while (match(line, /([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/)) {
                print toupper(substr(line, RSTART, RLENGTH))
                line = substr(line, RSTART + RLENGTH)
            }
        }
        /STATE_CONNECTED|Connection state: 2/ {
            line = $0
            if (match(line, /([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/)) {
                print toupper(substr(line, RSTART, RLENGTH))
            }
        }
        ')
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

get_bonded_devices() {
    # 1. Connected Device Name & BT MAC from phoneprojection
    raw_p4=$(service call phoneprojection 4 2>/dev/null || true)
    name_p4=$(decode_parcel_str "$raw_p4")
    raw_p5=$(service call phoneprojection 5 2>/dev/null || true)
    mac_p5=$(decode_parcel_str "$raw_p5" | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | tr '[:lower:]' '[:upper:]' | head -n 1)
    if [ -n "$mac_p5" ] && [ -n "$name_p4" ] && [ "$name_p4" != "<null>" ] && [ "$name_p4" != "<empty>" ]; then
        echo "$name_p4|$mac_p5"
    fi

    # 2. Connected HFP Phone from bluetooth_manager
    raw_b17=$(service call bluetooth_manager 17 2>/dev/null || true)
    mac_b17=$(decode_parcel_str "$raw_b17" | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | tr '[:lower:]' '[:upper:]' | head -n 1)
    if [ -n "$mac_b17" ] && [ "$mac_b17" != "$mac_p5" ]; then
        echo "Connected Phone|$mac_b17"
    fi

    # 3. Last CarPlay phone from dipo
    raw_d14=$(service call dipo 14 2>/dev/null || true)
    mac_d14=$(decode_parcel_str "$raw_d14" | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | tr '[:lower:]' '[:upper:]' | head -n 1)
    if [ -n "$mac_d14" ]; then
        echo "CarPlay Phone|$mac_d14"
    fi

    # 4. Parse persistent Bluetooth config (Bluedroid XML & Conf) - covers ALL user profiles
    for bt_xml in /data/misc/bluedroid/bt_config.xml /data/misc/bluetoothd/bt_config.xml; do
        if [ -f "$bt_xml" ]; then
            awk '
            /Tag=.*([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/ {
                match($0, /([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/)
                cur_mac = toupper(substr($0, RSTART, RLENGTH))
            }
            cur_mac != "" && /Tag="Name"/ {
                match($0, />[^<]+</)
                if (RLENGTH > 2) {
                    name = substr($0, RSTART + 1, RLENGTH - 2)
                    print name "|" cur_mac
                    cur_mac = ""
                }
            }
            ' "$bt_xml" 2>/dev/null || true
        fi
    done

    for bt_conf in /data/misc/bluedroid/bt_config.conf /data/misc/bluetoothd/bt_config.conf; do
        if [ -f "$bt_conf" ]; then
            awk '
            /\[([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\]/ {
                match($0, /([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/)
                cur_mac = toupper(substr($0, RSTART, RLENGTH))
            }
            cur_mac != "" && /^[ \t]*Name[ \t]*=/ {
                sub(/^[ \t]*Name[ \t]*=[ \t]*/, "")
                sub(/[ \r\n\t]*$/, "")
                print $0 "|" cur_mac
                cur_mac = ""
            }
            ' "$bt_conf" 2>/dev/null || true
        fi
    done

    # 5. HKMC Bluetooth Settings shared_prefs across all user profiles (0, 10, 1, 2)
    for sp in /data/data/com.android.btsettings/shared_prefs/*.xml /data/user/*/com.android.btsettings/shared_prefs/*.xml /data/system/users/*/com.android.btsettings*.xml; do
        if [ -f "$sp" ]; then
            awk '
            /([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/ && />[^<]+</ {
                match($0, /([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/)
                mac = toupper(substr($0, RSTART, RLENGTH))
                match($0, />[^<]+</)
                if (RLENGTH > 2) {
                    name = substr($0, RSTART + 1, RLENGTH - 2)
                    print name "|" mac
                }
            }
            ' "$sp" 2>/dev/null || true
        fi
    done

    # 6. Dumpsys bluetooth / bluetooth_manager for bonded devices across profiles
    dump=$(dumpsys bluetooth 2>/dev/null || dumpsys bluetooth_manager 2>/dev/null || true)
    if [ -n "$dump" ]; then
        echo "$dump" | awk '
        /Bonded devices:/ { in_b = 1; next }
        /mBondedDevices:/ { in_b = 1; next }
        in_b && /^[ \t]*$/ { in_b = 0 }
        in_b && /^[^ \t]/ && !/Bonded/ { in_b = 0 }
        in_b {
            line = $0
            if (match(line, /([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/)) {
                mac = toupper(substr(line, RSTART, RLENGTH))
                sub(/^[ \t]*/, "", line)
                sub(mac, "", line)
                gsub(/[\(\)\[\]]/, "", line)
                sub(/BR\/EDR/, "", line)
                sub(/LE/, "", line)
                sub(/^[ \t]*/, "", line); sub(/[ \t]*$/, "", line)
                name = line
                if (name == "") name = "Paired Phone"
                print name "|" mac
            }
        }'
    fi
}

# ------------------------------------------------------------------------------
# Configuration Synchronization & Parsing
# ------------------------------------------------------------------------------

sync_and_get_config_path() {
    # If legacy autoprofile.selector config exists, copy over
    if [ ! -f "$CONFIG_FILE" ] && [ -f "$LEGACY_PKG_DIR/config.json" ]; then
        mkdir -p "$DATA_DIR" 2>/dev/null || true
        cp -f "$LEGACY_PKG_DIR/config.json" "$CONFIG_FILE" 2>/dev/null || true
    fi

    # If fallback config is newer, sync back to primary config
    if [ -f "$FALLBACK_CONFIG" ]; then
        if [ ! -f "$CONFIG_FILE" ] || [ "$FALLBACK_CONFIG" -nt "$CONFIG_FILE" ]; then
            cp -f "$FALLBACK_CONFIG" "$CONFIG_FILE" 2>/dev/null || true
        fi
    elif [ -f "/data/local/tmp/autoprofile_config.json" ]; then
        if [ ! -f "$CONFIG_FILE" ]; then
            cp -f "/data/local/tmp/autoprofile_config.json" "$CONFIG_FILE" 2>/dev/null || true
        fi
    fi

    if [ -f "$CONFIG_FILE" ]; then
        echo "$CONFIG_FILE"
    elif [ -f "$FALLBACK_CONFIG" ]; then
        echo "$FALLBACK_CONFIG"
    elif [ -f "/data/local/tmp/autoprofile_config.json" ]; then
        echo "/data/local/tmp/autoprofile_config.json"
    else
        echo ""
    fi
}

# Extracts phone entries as "name|bt_mac|wifi_mac|assigned_driver|priority"
parse_configured_phones() {
    cfg_file="$1"
    if [ -f "$cfg_file" ]; then
        awk -v RS="[,{}]" '
        /"name"[ \t]*:/ {
            s = $0; sub(/.*"name"[ \t]*:[ \t]*"/, "", s); sub(/".*/, "", s); name = s
        }
        /"bt_mac"[ \t]*:/ {
            s = $0; sub(/.*"bt_mac"[ \t]*:[ \t]*"/, "", s); sub(/".*/, "", s); bt = toupper(s)
        }
        /"wifi_mac"[ \t]*:/ {
            if ($0 ~ /null/) { wifi = "" }
            else {
                s = $0; sub(/.*"wifi_mac"[ \t]*:[ \t]*"/, "", s); sub(/".*/, "", s); wifi = toupper(s)
            }
        }
        /"assigned_driver"[ \t]*:/ {
            s = $0; sub(/.*"assigned_driver"[ \t]*:[ \t]*/, "", s); gsub(/[^0-9]/, "", s); driver = s
        }
        /"priority"[ \t]*:/ {
            s = $0; sub(/.*"priority"[ \t]*:[ \t]*/, "", s); gsub(/[^0-9]/, "", s); prio = s
            if (bt != "" || wifi != "") {
                print name "|" bt "|" wifi "|" driver "|" prio
            }
            name = ""; bt = ""; wifi = ""; driver = 0; prio = 0
        }
        ' "$cfg_file" 2>/dev/null
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
    echo "$$" > "/data/local/tmp/autoprofile_helper.pid" 2>/dev/null || true
    chmod 666 "$PID_FILE" 2>/dev/null || true
    chmod 666 "$FALLBACK_PID" 2>/dev/null || true
    chmod 666 "/data/local/tmp/autoprofile_helper.pid" 2>/dev/null || true

    echo "[hmg-phone-profiles] Daemon started with PID $$."

    trap 'echo "[hmg-phone-profiles] Shutting down..."; rm -f "$PID_FILE" "$FALLBACK_PID" "/data/local/tmp/autoprofile_helper.pid"; exit 0' SIGTERM SIGINT

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
        m_name="${matched_names#;}"
        m_first_name="${m_name%%;*}"
        [ -z "$m_first_name" ] && m_first_name="Phone"

        if [ "$matched_count" -eq 1 ]; then
            m_bt=$(echo "$matched_bts" | awk '{print $1}')
            m_wifi=$(echo "$matched_wifis" | awk '{print $1}')

            if [ -z "$m_wifi" ] && [ -n "$wifi_macs" ]; then
                for new_wmac in $wifi_macs; do
                    if [ "$new_wmac" != "00:00:00:00:00:00" ]; then
                        echo "[AUTO-LEARN] Auto-learned Wi-Fi MAC $new_wmac for $m_first_name (BT: $m_bt)"
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

        in_p=false
        if is_in_park; then in_p=true; fi

        # Manual switch cooldown check (suppress auto-revert within 60s of manual switch)
        last_manual_ts=0
        if [ -f "$DATA_DIR/last_switched_ts" ]; then
            last_manual_ts=$(cat "$DATA_DIR/last_switched_ts" 2>/dev/null || echo 0)
        fi
        now=$(date +%s 2>/dev/null || echo 0)
        cooldown_active=false
        if [ "$now" -gt 0 ] && [ "$last_manual_ts" -gt 0 ]; then
            elapsed=$((now - last_manual_ts))
            if [ "$elapsed" -ge 0 ] && [ "$elapsed" -lt 60 ]; then
                cooldown_active=true
            fi
        fi

        # Execute switch if target driver resolved and auto_select is active
        if [ "$auto_select" = "true" ] && [ "$resolved_driver" -gt 0 ]; then
            if [ "$current_uid" != "$resolved_driver" ]; then
                should_switch=false
                if [ "$resolved_driver" != "$last_resolved_driver" ]; then
                    should_switch=true
                elif [ "$in_p" = "true" ] && [ "$prev_in_park" = "false" ]; then
                    should_switch=true
                fi

                if [ "$cooldown_active" = "true" ]; then
                    echo "[COOLDOWN] Manual switch cooldown active ($elapsed sec < 60 sec). Suppressing auto-revert."
                    should_switch=false
                fi

                if [ "$should_switch" = "true" ]; then
                    echo "[DETECT] Phone ($m_first_name) matched Driver $resolved_driver (Current: $current_uid). Gating on Park..."
                    if [ "$in_p" = "true" ]; then
                        execute_switch_flow "$resolved_driver" "$dismiss_notice" "$show_banner" "$m_first_name"
                    else
                        echo "[GATE] Mutating action deferred: Gear is not in Park (P)."
                    fi
                fi
            fi
        fi

        last_resolved_driver="$resolved_driver"
        prev_in_park="$in_p"

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
        echo "=== hmg-phone-profiles Helper Status ==="
        pid=""
        for pf in "$PID_FILE" "$FALLBACK_PID" "/data/nemesis/apps/autoprofile.selector/data/helper.pid" "/data/local/tmp/autoprofile_helper.pid"; do
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
    is-park)
        if is_in_park; then
            echo "true"
            exit 0
        else
            echo "false"
            exit 1
        fi
        ;;
    get-profile)
        get_active_profile
        ;;
    get-profile-name)
        uid="${2:-$(get_active_profile)}"
        get_profile_name "$uid"
        ;;
    bonded)
        get_bonded_devices | awk -F'|' '!seen[$2]++ { print $0 }'
        ;;
    switch)
        target="${2:-1}"
        source_label="${3:-Manual}"
        execute_switch_flow "$target" "false" "true" "$source_label"
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
        msg="${2:-Manual - Driver 1}"
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
        source_label="${3:-Manual}"
        execute_switch_flow "$target" "true" "true" "$source_label"
        ;;
    *)
        echo "Usage: helper.sh [run|status|gear|switch <1|2|0> [source]|seat <1|2>|consent|toast <msg>|detect|full-flow <1|2> [source]]"
        exit 1
        ;;
esac
