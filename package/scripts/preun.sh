#!/system/bin/sh
# ==============================================================================
# preun.sh — Pre-uninstall cleanup hook for autoprofile.selector
# Runs as root before package services/APKs are removed.
# ==============================================================================

export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin:$PATH

PKG_DIR="/data/nemesis/apps/autoprofile.selector"
PID_FILE="$PKG_DIR/data/helper.pid"
FALLBACK_PID="/data/local/tmp/autoprofile_helper.pid"

echo "[autoprofile.selector] Running pre-uninstall hook..."

# Terminate running helper daemon if PID file exists
for pf in "$PID_FILE" "$FALLBACK_PID"; do
    if [ -f "$pf" ]; then
        PID=$(cat "$pf" 2>/dev/null)
        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            echo "[autoprofile.selector] Terminating helper daemon (PID $PID)..."
            kill "$PID" 2>/dev/null || true
        fi
        rm -f "$pf"
    fi
done

# Clean up shared tmp files
rm -f /data/local/tmp/autoprofile_config.json 2>/dev/null || true
rm -f /data/local/tmp/autoprofile_state.json 2>/dev/null || true
rm -f /data/local/tmp/autoprofile_helper.pid 2>/dev/null || true

echo "[autoprofile.selector] Pre-uninstall completed successfully."
exit 0
