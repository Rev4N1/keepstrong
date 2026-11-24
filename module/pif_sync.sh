#!/system/bin/sh
# KeepStrong — keep the user's PlayIntegrityFork in STRONG shape.
#
# PlayIntegrityFork's own autopif rewrites custom.pif.prop on every fetch/Action
# and can reset spoof flags. When reassert_pif_flags is on we set ONLY the three
# flags STRONG depends on:
#   spoofBuild=1
#   spoofProps=1
#   spoofVendingFinger=1 on SDK 33+ (Android 13+), 0 on SDK 32 and older
# Every other flag (spoofProvider, spoofSignature, spoofVendingSdk, ...) is left
# exactly as PIFork wrote it.
#
# Prints "installed" / "none" so callers can report what was synced.

MODDIR=${0%/*}
. "$MODDIR/common.sh"
. "$MODDIR/detect.sh"
ks_init

_dir=$(ks_pif_dir) || { echo none; exit 0; }
[ "$(ks_pif_kind "$_dir")" = "installed" ] || { echo none; exit 0; }

_src=$(ks_pif_src) || { ks_log "pif_sync: custom.pif.prop has no FINGERPRINT yet, flags not touched"; echo installed; exit 0; }

if ks_on reassert_pif_flags; then
  _bb=$(ks_busybox); SED_I="sed -i"; [ -n "$_bb" ] && SED_I="$_bb sed -i"
  _svf=1
  _sdk=$(getprop ro.build.version.sdk 2>/dev/null)
  case "$_sdk" in ''|*[!0-9]*) : ;; *) [ "$_sdk" -le 32 ] && _svf=0 ;; esac
  for _kv in "spoofBuild=1" "spoofProps=1" "spoofVendingFinger=$_svf"; do
    _k=${_kv%%=*}; _v=${_kv#*=}
    if grep -q "^$_k=" "$_src"; then $SED_I "s|^$_k=.*|$_k=$_v|" "$_src"; else printf '%s=%s\n' "$_k" "$_v" >> "$_src"; fi
  done
  ks_log "pif_sync: spoofBuild=1 spoofProps=1 spoofVendingFinger=$_svf (SDK ${_sdk:-?}); other flags untouched"
  unset _bb SED_I _svf _sdk _kv _k _v
fi

printf 'installed\n'
