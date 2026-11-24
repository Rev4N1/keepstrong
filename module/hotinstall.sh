#!/system/bin/sh
# KeepStrong — live-apply hook, run right after a hot install swaps the new
# version into place. Re-runs the full pipeline so the update takes effect with
# no reboot. Writes .hotinstall_failed on error so customize.sh can warn.

MODDIR=${0%/*}
. "$MODDIR/common.sh"
. "$MODDIR/detect.sh"
ks_init

ks_log "hotinstall: applying update live"
rm -f "$KS_DIR/.hotinstall_failed" 2>/dev/null

if sh "$MODDIR/sync.sh" action >/dev/null 2>&1; then
  ks_log "hotinstall: live-apply done"
else
  : > "$KS_DIR/.hotinstall_failed"
  ks_log "hotinstall: live-apply failed"
fi
