#!/system/bin/sh
# ==============================================================================
# preun.sh — Pre-uninstall cleanup hook for hmg-phone-profiles
# Runs as root before package services/APKs are removed.
# ==============================================================================

export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin:$PATH

PKG_DIR="/data/nemesis/apps/hmg-phone-profiles"
PID_FILE="$PKG_DIR/data/helper.pid"
FALLBACK_PID="/data/local/tmp/hmg_phone_profiles_helper.pid"

echo "[hmg-phone-profiles] Running pre-uninstall hook..."

# Terminate running helper daemon if PID file exists
for pf in "$PID_FILE" "$FALLBACK_PID" "/data/nemesis/apps/autoprofile.selector/data/helper.pid" "/data/local/tmp/autoprofile_helper.pid"; do
    if [ -f "$pf" ]; then
        PID=$(cat "$pf" 2>/dev/null)
        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            echo "[hmg-phone-profiles] Terminating helper daemon (PID $PID)..."
            kill "$PID" 2>/dev/null || true
        fi
        rm -f "$pf"
    fi
done

# Clean up shared tmp files
rm -f /data/local/tmp/hmg_phone_profiles_config.json 2>/dev/null || true
rm -f /data/local/tmp/hmg_phone_profiles_state.json 2>/dev/null || true
rm -f /data/local/tmp/hmg_phone_profiles_helper.pid 2>/dev/null || true
rm -f /data/local/tmp/autoprofile_config.json 2>/dev/null || true
rm -f /data/local/tmp/autoprofile_state.json 2>/dev/null || true
rm -f /data/local/tmp/autoprofile_helper.pid 2>/dev/null || true

echo "[hmg-phone-profiles] Pre-uninstall completed successfully."
exit 0
