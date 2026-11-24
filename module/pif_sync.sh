#!/system/bin/sh
# KeepStrong — keep the user's PlayIntegrityFork in STRONG shape.
#
# PlayIntegrityFork's own autopif rewrites custom.pif.prop on every fetch/Action
# and resets spoof flags to weaker defaults (notably spoofVendingFinger 1 -> 0).
# When reassert_pif_flags is on we re-assert the STRONG Fork flags (version
# aware: the vending-finger flag is off on Android <= 12L). inject-s owns its
# own flags through its own WebUI, so we never fight its settings — we only
# mirror its fingerprint (done by teesim_config.sh).
#
# Then we restart DroidGuard so android.os.Build reflects the re-asserted flags.
# Flag enforcement adapted from AlwaysStrong (GPL-3.0).
#
# Prints "fork" / "inject" / "none" so callers can report what was synced.

MODDIR=${0%/*}
. "$MODDIR/common.sh"
. "$MODDIR/detect.sh"
ks_init

_dir=$(ks_pif_dir) || { echo none; exit 0; }
_kind=$(ks_pif_kind "$_dir")
[ "$_kind" = "fork" ] || [ "$_kind" = "inject" ] || { echo none; exit 0; }

_src=$(ks_pif_src) || { echo "$_kind"; exit 0; }

if ks_on reassert_pif_flags && [ "$_kind" = "fork" ]; then
  _bb=$(ks_busybox); SED_I="sed -i"; [ -n "$_bb" ] && SED_I="$_bb sed -i"
  _svf=1
  _sdk=$(getprop ro.build.version.sdk 2>/dev/null)
  case "$_sdk" in ''|*[!0-9]*) : ;; *) [ "$_sdk" -le 32 ] && _svf=0 ;; esac
  for _kv in "spoofProvider=0" "spoofVendingFinger=$_svf" "spoofBuild=1" "spoofProps=1" "spoofSignature=0" "spoofVendingSdk=0"; do
    _k=${_kv%%=*}; _v=${_kv#*=}
    if grep -q "^$_k=" "$_src"; then $SED_I "s|^$_k=.*|$_k=$_v|" "$_src"; else printf '%s=%s\n' "$_k" "$_v" >> "$_src"; fi
  done
  unset _bb SED_I _svf _sdk _kv _k _v
fi

if ks_on restart_gms_on_sync; then
  if [ -f "$_dir/killpi.sh" ]; then sh "$_dir/killpi.sh" >/dev/null 2>&1
  else killall -9 com.google.android.gms.unstable 2>/dev/null; fi
fi
printf '%s\n' "$_kind"
