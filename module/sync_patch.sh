#!/system/bin/sh
# KeepStrong — security-patch sync.
#
# Reads the patch PIFork spoofs (ro.build.version.security_patch, falling back
# to SECURITY_PATCH, in custom.pif.prop) and writes it to
# $KS_DIR/security_patch.txt (system/vendor/boot), and — when spoof_patch_props
# is on and this is a boot run — pins the ro.*.security_patch props so the
# OS-reported patch matches the attested one. The attested patch level itself is
# consumed by teesim_config.sh; keeping them equal is what stops Play Integrity
# from failing on a Build/attestation mismatch.
#
# No fallback to the device's own patch: if PIFork presents none, attest the
# TEESimulator default rather than a patch Build never claimed.
#
# Usage: sync_patch.sh [boot]

MODDIR=${0%/*}
. "$MODDIR/common.sh"
. "$MODDIR/detect.sh"
ks_init
MODE="${1:-}"

DOT=$(ks_pif_patch) || DOT=""
if [ -z "$DOT" ]; then
  ks_log "sync_patch: PIFork carries no usable security patch, skipping"
  exit 1
fi

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
