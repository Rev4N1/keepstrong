#!/system/bin/sh
# KeepStrong — security-patch sync.
#
# Reads SECURITY_PATCH from the PIF fingerprint and writes a matching patch
# level to $KS_DIR/security_patch.txt (system/vendor/boot), and — when
# spoof_patch_props is on and this is a boot run — pins the ro.*.security_patch
# props so the OS-reported patch matches the attested one. The attested patch
# level itself is consumed by teesim_config.sh; keeping them equal is what
# stops Play Integrity from failing on a Build/attestation mismatch.
#
# Usage: sync_patch.sh [boot]

MODDIR=${0%/*}
. "$MODDIR/common.sh"
. "$MODDIR/detect.sh"
ks_init
MODE="${1:-}"

SP=""
SRC=$(ks_pif_src) || SRC=""
[ -n "$SRC" ] && SP=$(sed -n 's/^SECURITY_PATCH=//p' "$SRC" | head -1 | tr -d ' "'\''\r')
[ -z "$SP" ] && SP=$(getprop ro.build.version.security_patch 2>/dev/null)

RAW=$(printf '%s' "$SP" | tr -cd '0-9')
if [ "${#RAW}" -ne 8 ]; then
  ks_log "sync_patch: no usable SECURITY_PATCH ($SP), skipping"
  exit 1
fi
DOT="$(printf '%s' "$RAW" | cut -c1-4)-$(printf '%s' "$RAW" | cut -c5-6)-$(printf '%s' "$RAW" | cut -c7-8)"

mkdir -p "$KS_DIR" 2>/dev/null
printf 'system=%s\nvendor=%s\nboot=%s\n' "$DOT" "$DOT" "$DOT" > "$KS_DIR/security_patch.txt"

if [ "$MODE" = "boot" ] && ks_on spoof_patch_props && _have_resetprop; then
  for _p in ro.build.version.security_patch ro.vendor.build.security_patch ro.system.build.version.security_patch; do
    _cur=$(resetprop "$_p" 2>/dev/null)
    [ -n "$_cur" ] && [ "$_cur" != "$DOT" ] && resetprop -n "$_p" "$DOT" 2>/dev/null
  done
  unset _p _cur
fi
printf '%s\n' "$DOT"
