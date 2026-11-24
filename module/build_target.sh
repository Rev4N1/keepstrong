#!/system/bin/sh
# KeepStrong — compose the attestation target app list.
#
# Prints one package (or uid:N) per line. The Play Integrity core is always
# covered and pinned by real uid (name resolution can miss GMS at early boot /
# multi-user / shared uid). The user can add their own packages, one per line,
# in $KS_DIR/apps.list. Xposed/LSPosed managers are deliberately excluded —
# attesting through a hooked process breaks STRONG.
#
# teesim_config.sh consumes this and sanitises it into TEESimulator's schema.

MODDIR=${0%/*}
. "$MODDIR/common.sh"
ks_init

_seen=" "
_emit() { case "$_seen" in *" $1 "*) return ;; esac; _seen="$_seen$1 "; printf '%s\n' "$1"; }

for _p in com.google.android.gms com.android.vending com.google.android.gsf; do
  _emit "$_p"
  _u=$(sed -n "s/^$_p \([0-9][0-9]*\) .*/\1/p" /data/system/packages.list 2>/dev/null | head -1)
  case "$_u" in [0-9]*) _emit "uid:$_u" ;; esac
done

if [ -f "$KS_DIR/apps.list" ]; then
  while IFS= read -r _line || [ -n "$_line" ]; do
    _line=$(printf '%s' "$_line" | tr -d ' \t\r')
    case "$_line" in ''|'#'*) continue ;; esac
    _line=${_line%!}; _line=${_line%\?}
    _valid=$(printf '%s' "$_line" | grep -oE '^[A-Za-z0-9_.]+(@[0-9]+)?$')
    [ -n "$_valid" ] && _emit "$_valid"
  done < "$KS_DIR/apps.list"
fi
unset _p _u _line _valid _seen
