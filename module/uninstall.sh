#!/system/bin/sh
# KeepStrong — uninstall cleanup.
#
# We leave /data/adb/teesim (keybox + config) in place: those belong to the
# TEESimulator module, not to us, and wiping them would break a stack the user
# keeps. We only remove our own state dir.
rm -rf /data/adb/keepstrong 2>/dev/null
