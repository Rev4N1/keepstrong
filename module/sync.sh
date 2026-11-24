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
# Action / WebUI runs show progress; boot + hourly stay quiet (they go to logcat).
[ "$MODE" = "action" ] && KS_VERBOSE=1
export KS_VERBOSE

ks_on enabled || { ks_say "KeepStrong is disabled — nothing to do."; exit 0; }
ks_say "KeepStrong sync — $MODE"

# Presence summary (for the WebUI/status and the logs).
_dir=$(ks_pif_dir) && _kind=$(ks_pif_kind "$_dir") || _kind=none
[ "$_kind" = "fork" ] || { _kind=none; _dir=""; }
st_set pif_kind "$_kind"
ks_teesim_present && st_set teesim present || st_set teesim absent
ks_hma_present && st_set hma present || st_set hma absent
ks_say "  stack: PIF=$_kind  teesim=$(ks_teesim_present && echo yes || echo NO)  hma=$(ks_hma_present && echo yes || echo no)"

# 0. Trigger PlayIntegrityFork's own fetch so Build carries a fresh fingerprint
#    before we mirror it into TEESimulator. action/boot only (not hourly).
if ks_on run_pif_action && [ "$_kind" != "none" ] && { [ "$MODE" = "action" ] || [ "$MODE" = "boot" ]; }; then
  if [ -f "$_dir/action.sh" ]; then
    ks_say "[1/6] PlayIntegrityFork: running its action.sh (fresh fingerprint)..."
    sh "$_dir/action.sh" >/dev/null 2>&1 || true
  elif [ -f "$_dir/autopif4.sh" ]; then
    ks_say "[1/6] PlayIntegrityFork: running autopif4.sh (fresh fingerprint)..."
    sh "$_dir/autopif4.sh" -m >/dev/null 2>&1 || true
  fi
else
  ks_say "[1/6] PlayIntegrityFork fetch: skipped ($MODE)"
fi

# 1. keybox
if ks_on auto_keybox; then
  ks_say "[2/6] Keybox: fetching from your endpoints..."
  sh "$MODDIR/keybox_fetch.sh"; _kbrc=$?
  st_set keybox_rc "$_kbrc"
  case "$_kbrc" in 0) ks_say "      keybox updated";; 2) ks_say "      keybox unchanged / nothing to do";; *) ks_say "      keybox: no update (check endpoints)";; esac
else
  ks_say "[2/6] Keybox: auto_keybox off, skipped"
fi
# Revocation check — a revoked keybox never reaches STRONG, so flag it loudly.
if [ -s "$TEESIM_KEYBOX" ]; then
  _rev=$(sh "$MODDIR/keybox_check.sh")
  case "$_rev" in
    OK) ks_say "      keybox revocation: OK (not revoked)";;
    REVOKED:*) ks_say "      !! KEYBOX REVOKED (${_rev#REVOKED:}) — get a fresh keybox, this will NOT pass STRONG";;
    *) ks_say "      keybox revocation: ${_rev#UNKNOWN:} (could not check)";;
  esac
fi

# 2. PIF flags
if ks_on auto_fp_sync; then
  ks_say "[3/6] PIF flags: re-asserting STRONG flags..."
  _k=$(sh "$MODDIR/pif_sync.sh"); st_set pif_synced "${_k:-none}"
  ks_say "      engine: ${_k:-none}"
else
  ks_say "[3/6] PIF flags: auto_fp_sync off, skipped"
fi

# 3. security patch
ks_say "[4/6] Security patch: matching to the PIF fingerprint..."
_patch=$(sh "$MODDIR/sync_patch.sh" "$MODE"); ks_say "      attested patch: ${_patch:-unknown}"

# 4. teesim config (identity + patch + targets + root of trust + keybox pickup)
ks_say "[5/6] TEESimulator: writing config + overrides, targeting apps..."
sh "$MODDIR/teesim_config.sh" >/dev/null; ks_say "      $(ks_teesim_present && echo 'config.json + overrides.json written' || echo 'teesim not installed — skipped')"

# 5. HMA-OSS (optional, preserves your existing config)
if ks_on manage_hma; then
  ks_say "[6/6] HMA-OSS: merging hide template into your config..."
  sh "$MODDIR/hma_sync.sh" >/dev/null
else
  ks_say "[6/6] HMA-OSS: manage_hma off, skipped"
fi

# restart Play Integrity surfaces
if ks_on restart_gms_on_sync; then ks_say "  restarting DroidGuard + Play Store (PIFork killpi.sh)..."; ks_restart_gms; fi

st_set last_sync "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
ks_say "Sync complete — verify with a Play Integrity checker."
