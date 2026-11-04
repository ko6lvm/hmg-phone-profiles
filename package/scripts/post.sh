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

# Initialize default configuration if not already present
if [ ! -f "$CONFIG_FILE" ]; then
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
    {
      "id": 1,
      "name": "Pixel 11 Pro XL",
      "bt_mac": "AA:BB:CC:11:22:33",
      "wifi_mac": "02:00:00:11:22:33",
      "assigned_driver": 1,
      "priority": 1
    },
    {
      "id": 2,
      "name": "iPhone Duo",
      "bt_mac": "DD:EE:FF:44:55:66",
      "wifi_mac": "02:00:00:44:55:66",
      "assigned_driver": 2,
      "priority": 2
    },
    {
      "id": 3,
      "name": "Samsung S26 Ultra",
      "bt_mac": "11:22:33:AA:BB:CC",
      "wifi_mac": null,
      "assigned_driver": 0,
      "priority": 0
    }
  ]
}
EOF
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
