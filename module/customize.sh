#!/system/bin/sh
# KeepStrong — install-time checks. Bundles nothing; only verifies the stack
# you install yourself and seeds config.

SKIPUNZIP=0

ui_print ""
ui_print "  KeepStrong — bring-your-own STRONG orchestrator"
ui_print "  ---------------------------------------------"
ui_print "  Bundles no modules. It drives the ones you install:"
ui_print "   - PlayIntegrityFork (osm0sis)  — Build/fingerprint spoof"
ui_print "   - TEESimulator (JingMatrix)    — key attestation"
ui_print "   - HMA-OSS (optional)           — module hiding"
ui_print ""

# Seed config + helpers so detect works at install time too.
mkdir -p /data/adb/keepstrong 2>/dev/null
. "$MODPATH/common.sh" 2>/dev/null
. "$MODPATH/detect.sh" 2>/dev/null
ks_init 2>/dev/null

_missing=0
if _dir=$(ks_pif_dir 2>/dev/null); then
  _kind=$(ks_pif_kind "$_dir" 2>/dev/null)
  ui_print "  [ok] PlayIntegrity engine detected: $_kind"
else
  ui_print "  [!!] PlayIntegrityFork NOT found."
  ui_print "       Install osm0sis PlayIntegrityFork, then reboot."
  _missing=1
fi
if ks_teesim_present 2>/dev/null; then
  ui_print "  [ok] TEESimulator (JingMatrix) detected"
else
  ui_print "  [!!] TEESimulator (JingMatrix, id 'teesim') NOT found."
  ui_print "       Install it from github.com/JingMatrix/TEESimulator."
  _missing=1
fi
ks_hma_present 2>/dev/null && ui_print "  [ok] HMA-OSS detected"

ui_print ""
if [ "$_missing" = "1" ]; then
  ui_print "  Install the missing module(s) above, then open KeepStrong's"
  ui_print "  WebUI, set your Keybox URL, and tap Sync."
else
  ui_print "  All set. Open the WebUI, set your Keybox URL, and tap Sync."
fi
ui_print "  Nothing here reaches STRONG without YOUR keybox endpoint."
ui_print ""

set_perm_recursive "$MODPATH" 0 0 0755 0644
for f in common.sh detect.sh sync.sh action.sh service.sh post-fs-data.sh \
         keybox_fetch.sh pif_sync.sh sync_patch.sh build_target.sh teesim_config.sh \
         hma_sync.sh webui.sh; do
  [ -f "$MODPATH/$f" ] && set_perm "$MODPATH/$f" 0 0 0755
done
