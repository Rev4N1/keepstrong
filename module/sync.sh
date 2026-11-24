#!/system/bin/sh
# KeepStrong — one full orchestration pass.
#
# The single pipeline shared by the Action button, boot, the hourly loop and
# the WebUI "Sync now". Order matters:
#   0. pif action — (action/boot only) run PlayIntegrityFork's own fetch so the
#                   fingerprint is fresh before we mirror it
#   1. keybox     — pull a keybox from your endpoints (first that works)
#   2. pif flags  — re-assert PlayIntegrityFork's STRONG spoof flags
#   3. patch      — derive the attested security patch from the PIF fingerprint
#   4. teesim     — mirror identity + patch + targets + root-of-trust into TEESim
#   5. hma        — point HMA-OSS at the same targets (optional, non-destructive)
#   6. restart    — bounce DroidGuard / Play Store so the new identity takes hold
#
# Usage: sync.sh [action|boot|hourly]
#   action/boot run PIF's own fetch (step 0); hourly skips it to avoid churn.

MODDIR=${0%/*}
. "$MODDIR/common.sh"
. "$MODDIR/detect.sh"
ks_init
MODE="${1:-action}"

ks_on enabled || { ks_log "sync: disabled, nothing to do"; exit 0; }
ks_log "sync: start ($MODE)"

# Presence summary (for the WebUI/status and the logs).
_dir=$(ks_pif_dir) && _kind=$(ks_pif_kind "$_dir") || _kind=none
st_set pif_kind "${_kind:-none}"
ks_teesim_present && st_set teesim present || st_set teesim absent
ks_hma_present && st_set hma present || st_set hma absent

# 0. Trigger PlayIntegrityFork's own fetch so Build carries a fresh fingerprint
#    before we mirror it into TEESimulator. action/boot only (not hourly).
if ks_on run_pif_action && [ "$_kind" != "none" ] && { [ "$MODE" = "action" ] || [ "$MODE" = "boot" ]; }; then
  if [ -f "$_dir/action.sh" ]; then
    ks_log "sync: running PlayIntegrityFork action.sh"
    sh "$_dir/action.sh" >/dev/null 2>&1 || true
  elif [ -f "$_dir/autopif4.sh" ]; then
    ks_log "sync: running PlayIntegrityFork autopif4.sh"
    sh "$_dir/autopif4.sh" -m >/dev/null 2>&1 || true
  fi
fi

# 1. keybox
if ks_on auto_keybox; then
  sh "$MODDIR/keybox_fetch.sh" >/dev/null 2>&1
  st_set keybox_rc "$?"
fi

# 2. PIF flags
if ks_on auto_fp_sync; then
  _k=$(sh "$MODDIR/pif_sync.sh" 2>/dev/null); st_set pif_synced "${_k:-none}"
fi

# 3. security patch
sh "$MODDIR/sync_patch.sh" "$MODE" >/dev/null 2>&1

# 4. teesim config (identity + patch + targets + root of trust + keybox pickup)
sh "$MODDIR/teesim_config.sh" >/dev/null 2>&1

# 5. HMA-OSS (optional, preserves your existing config)
ks_on manage_hma && sh "$MODDIR/hma_sync.sh" >/dev/null 2>&1

# 6. restart Play Integrity surfaces
ks_on restart_gms_on_sync && ks_restart_gms

st_set last_sync "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
ks_log "sync: done"
