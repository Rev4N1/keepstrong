#!/system/bin/sh
# KeepStrong — keep the user's PlayIntegrityFork in STRONG shape.
#
# PlayIntegrityFork's own autopif rewrites custom.pif.prop on every fetch/Action
# and resets spoof flags to weaker defaults (notably spoofProvider 0 -> 1 and
# spoofVendingFinger 1 -> 0). When reassert_pif_flags is on we re-assert the
# STRONG set below. Only osm0sis PlayIntegrityFork is driven — PlayIntegrityFix
# / inject-s is not supported.
#
# Prints "fork" / "none" so callers can report what was synced.

MODDIR=${0%/*}
. "$MODDIR/common.sh"
. "$MODDIR/detect.sh"
ks_init

_dir=$(ks_pif_dir) || { echo none; exit 0; }
[ "$(ks_pif_kind "$_dir")" = "fork" ] || { echo none; exit 0; }

_src=$(ks_pif_src) || { echo fork; exit 0; }

if ks_on reassert_pif_flags; then
  _bb=$(ks_busybox); SED_I="sed -i"; [ -n "$_bb" ] && SED_I="$_bb sed -i"
  _svf=1
  _sdk=$(getprop ro.build.version.sdk 2>/dev/null)
  case "$_sdk" in ''|*[!0-9]*) : ;; *) [ "$_sdk" -le 32 ] && _svf=0 ;; esac
  # STRONG: provider/signature/vending-SDK spoofing off, Build+Props on, and the
  # Vending fingerprint on for A13+ (off on 12L and older).
  for _kv in "spoofProvider=0" "spoofVendingFinger=$_svf" "spoofBuild=1" "spoofProps=1" "spoofSignature=0" "spoofVendingSdk=0"; do
    _k=${_kv%%=*}; _v=${_kv#*=}
    if grep -q "^$_k=" "$_src"; then $SED_I "s|^$_k=.*|$_k=$_v|" "$_src"; else printf '%s=%s\n' "$_k" "$_v" >> "$_src"; fi
  done
  unset _bb SED_I _svf _sdk _kv _k _v
fi

printf 'fork\n'
