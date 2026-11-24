#!/system/bin/sh
# KeepStrong — Action button (root manager "Action", or `sh action.sh`).
# Runs one full sync and prints a short, friendly summary.

MODDIR=${0%/*}
. "$MODDIR/common.sh"
. "$MODDIR/detect.sh"
ks_init

echo "KeepStrong — running sync..."
echo

_dir=$(ks_pif_dir) && _kind=$(ks_pif_kind "$_dir") || _kind=none
[ "$_kind" = "fork" ] || _kind=none
if [ "$_kind" = "none" ]; then
  echo "  ! PlayIntegrityFork not found. Install osm0sis PlayIntegrityFork"
  echo "    and tap Action again."
else
  echo "  - PlayIntegrity engine: $_kind"
fi
if ks_teesim_present; then echo "  - TEESimulator (JingMatrix): installed"
else echo "  ! TEESimulator (JingMatrix 'teesim') not found — install it."; fi
if ks_hma_present; then
  if ks_hma_config >/dev/null 2>&1; then echo "  - HMA-OSS: installed (config found)"
  else echo "  - HMA-OSS: installed (open it once so it creates a config)"; fi
fi

if [ -z "$(ks_get keybox_url)" ] && [ ! -f "$KS_DIR/keybox.urls" ]; then
  echo "  ! No keybox endpoint set. Open the WebUI and add a Keybox URL."
fi
if [ ! -s "$TEESIM_KEYBOX" ]; then
  echo "  ! No keybox at $TEESIM_KEYBOX yet."
fi
echo

sh "$MODDIR/sync.sh" action

echo
echo "Done. Verify with a Play Integrity checker (Play Integrity API Checker / YASNAC)."
echo "Logs: $KS_LOGS/keepstrong.log"
