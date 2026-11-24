#!/system/bin/sh
# KeepStrong — one full orchestration pass.
#
# The single pipeline shared by the Action button, boot, the hourly loop and
# the WebUI "Sync now". Order matters:
#   1. keybox   — pull a fresh keybox from your endpoint (if newer)
#   2. pif_sync — re-assert PlayIntegrityFork's STRONG flags
#   3. patch    — derive the attested security patch from the PIF fingerprint
#   4. teesim   — mirror identity + patch + target + root-of-trust into TEESim
#   5. restart  — bounce DroidGuard / Play Store so the new identity takes hold
#
# Usage: sync.sh [boot]   (boot also pins the ro.*.security_patch props)

MODDIR=${0%/*}
. "$MODDIR/common.sh"
. "$MODDIR/detect.sh"
ks_init
MODE="${1:-}"

ks_on enabled || { ks_log "sync: disabled, nothing to do"; exit 0; }
ks_log "sync: start ($MODE)"

# Presence summary (helps the WebUI/status and the logs).
_dir=$(ks_pif_dir) && _kind=$(ks_pif_kind "$_dir") || _kind=none
st_set pif_kind "${_kind:-none}"
ks_teesim_present && st_set teesim present || st_set teesim absent
ks_hma_present && st_set hma present || st_set hma absent

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

# 4. teesim config (identity + target + root of trust + keybox pickup)
sh "$MODDIR/teesim_config.sh" >/dev/null 2>&1

# 5. restart Play Integrity surfaces
ks_on restart_gms_on_sync && ks_restart_gms

st_set last_sync "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
ks_log "sync: done"
