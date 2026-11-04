#!/system/bin/sh
# ==============================================================================
# post.sh — Post-installation activation hook for autoprofile.selector
# Runs as root after package directory copy, APK install, and service register.
# Current working directory: /data/nemesis/apps/autoprofile.selector
# ==============================================================================

export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin:$PATH

PKG_DIR="/data/nemesis/apps/autoprofile.selector"
DATA_DIR="$PKG_DIR/data"
CONFIG_FILE="$PKG_DIR/config.json"
FALLBACK_CONFIG="/data/local/tmp/autoprofile_config.json"
FALLBACK_STATE="/data/local/tmp/autoprofile_state.json"
FALLBACK_PID="/data/local/tmp/autoprofile_helper.pid"

echo "[autoprofile.selector] Running post-install hook..."

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
        echo "[autoprofile.selector] Populating configuration with active vehicle Bluetooth devices..."
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

# Touch fallback state and pid files with open permissions
touch "$FALLBACK_STATE" 2>/dev/null || true
chmod 666 "$FALLBACK_STATE" 2>/dev/null || true
touch "$FALLBACK_PID" 2>/dev/null || true
chmod 666 "$FALLBACK_PID" 2>/dev/null || true

echo "[autoprofile.selector] Post-install completed successfully."
exit 0
