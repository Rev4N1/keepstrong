#!/system/bin/sh
# KeepStrong — launcher for native hot install (ksud / mountify). Those bound
# the run script to ~30s, which the live-apply can exceed, so detach and return
# at once; hotinstall.sh logs to the KeepStrong log.
MODDIR=${0%/*}
if command -v setsid >/dev/null 2>&1; then
  setsid sh "$MODDIR/hotinstall.sh" >/dev/null 2>&1 &
else
  sh "$MODDIR/hotinstall.sh" >/dev/null 2>&1 &
fi
exit 0
