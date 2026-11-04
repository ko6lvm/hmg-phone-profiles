#!/system/bin/sh
# ==============================================================================
# post.sh — Post-installation activation hook for hmg-phone-profiles
# Runs as root after package directory copy, APK install, and service register.
# Current working directory: /data/nemesis/apps/hmg-phone-profiles
# ==============================================================================

export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin:$PATH

PKG_DIR="/data/nemesis/apps/hmg-phone-profiles"
DATA_DIR="$PKG_DIR/data"
CONFIG_FILE="$PKG_DIR/config.json"
FALLBACK_CONFIG="/data/local/tmp/hmg_phone_profiles_config.json"
FALLBACK_STATE="/data/local/tmp/hmg_phone_profiles_state.json"
FALLBACK_PID="/data/local/tmp/hmg_phone_profiles_helper.pid"

LEGACY_PKG_DIR="/data/nemesis/apps/autoprofile.selector"
LEGACY_CONFIG="/data/nemesis/apps/autoprofile.selector/config.json"

echo "[hmg-phone-profiles] Running post-install hook..."

# Clean up / migrate legacy autoprofile.selector if upgrading
if [ -d "$LEGACY_PKG_DIR" ]; then
    echo "[hmg-phone-profiles] Migrating legacy installation..."
    if [ -f "$LEGACY_CONFIG" ] && [ ! -f "$CONFIG_FILE" ]; then
        mkdir -p "$DATA_DIR"
        cp -f "$LEGACY_CONFIG" "$CONFIG_FILE" 2>/dev/null || true
    fi
    rm -rf "$LEGACY_PKG_DIR" 2>/dev/null || true
    pm uninstall autoprofile.selector 2>/dev/null || true
fi

# Ensure data directory exists with world-writable permissions so APK can sync state
mkdir -p "$DATA_DIR"
chmod 777 "$DATA_DIR" 2>/dev/null || true
chmod 755 "$PKG_DIR/svc/helper.sh" 2>/dev/null || true
chmod 755 "$PKG_DIR/scripts/"*.sh 2>/dev/null || true

# Initialize or refresh configuration if missing or containing mock placeholders
needs_init=false
if [ ! -f "$CONFIG_FILE" ]; then
    needs_init=true
elif grep -q "AA:BB:CC:11:22:33" "$CONFIG_FILE" 2>/dev/null; then
    needs_init=true
fi

if [ "$needs_init" = "true" ]; then
    bonded=$("$PKG_DIR/svc/helper.sh" bonded 2>/dev/null || true)
    if [ -n "$bonded" ]; then
        echo "[hmg-phone-profiles] Populating configuration with active vehicle Bluetooth devices..."
        cat <<'EOF' > "$CONFIG_FILE"
{
  "version": 1,
  "settings": {
    "auto_select": true,
    "dismiss_notice": false,
    "show_banner": true,
    "conflict_policy": "p1",
    "detection_window_sec": 10
  },
  "phones": [
EOF
        idx=1
        first=true
        while IFS='|' read -r bname bmac; do
            [ -z "$bmac" ] && continue
            if [ "$first" = "false" ]; then echo "    }," >> "$CONFIG_FILE"; fi
            first=false
            echo "    {" >> "$CONFIG_FILE"
            echo "      \"id\": $idx," >> "$CONFIG_FILE"
            echo "      \"name\": \"$bname\"," >> "$CONFIG_FILE"
            echo "      \"bt_mac\": \"$bmac\"," >> "$CONFIG_FILE"
            echo "      \"wifi_mac\": null," >> "$CONFIG_FILE"
            drv=$idx
            if [ "$idx" -gt 2 ]; then drv=0; fi
            echo "      \"assigned_driver\": $drv," >> "$CONFIG_FILE"
            echo "      \"priority\": $drv" >> "$CONFIG_FILE"
            idx=$((idx + 1))
        done <<EOF
$bonded
EOF
        if [ "$first" = "false" ]; then echo "    }" >> "$CONFIG_FILE"; fi
        echo '  ]' >> "$CONFIG_FILE"
        echo '}' >> "$CONFIG_FILE"
    else
        cat <<'EOF' > "$CONFIG_FILE"
{
  "version": 1,
  "settings": {
    "auto_select": true,
    "dismiss_notice": false,
    "show_banner": true,
    "conflict_policy": "p1",
    "detection_window_sec": 10
  },
  "phones": []
}
EOF
    fi
fi

chmod 666 "$CONFIG_FILE" 2>/dev/null || true

# Fallback copy for non-root / standard Android process access
cp -f "$CONFIG_FILE" "$FALLBACK_CONFIG" 2>/dev/null || true
chmod 666 "$FALLBACK_CONFIG" 2>/dev/null || true
cp -f "$CONFIG_FILE" "/data/local/tmp/autoprofile_config.json" 2>/dev/null || true
chmod 666 "/data/local/tmp/autoprofile_config.json" 2>/dev/null || true

# Touch fallback state and pid files with open permissions
touch "$FALLBACK_STATE" 2>/dev/null || true
chmod 666 "$FALLBACK_STATE" 2>/dev/null || true
touch "$FALLBACK_PID" 2>/dev/null || true
chmod 666 "$FALLBACK_PID" 2>/dev/null || true
touch "/data/local/tmp/autoprofile_state.json" 2>/dev/null || true
chmod 666 "/data/local/tmp/autoprofile_state.json" 2>/dev/null || true
touch "/data/local/tmp/autoprofile_helper.pid" 2>/dev/null || true
chmod 666 "/data/local/tmp/autoprofile_helper.pid" 2>/dev/null || true

echo "[hmg-phone-profiles] Post-install completed successfully."
exit 0
