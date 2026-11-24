#!/system/bin/sh
# KeepStrong — compose the attestation / hide target list.
#
# Prints one package (or uid:N) per line, de-duplicated. Like AlwaysStrong and
# Specter, with auto_target on (default) it targets EVERY user-installed app
# (pm list packages -3) plus the Play Integrity core, so a newly installed app
# is covered without hand-editing. The core is always present and pinned by real
# uid (name resolution can miss GMS at early boot / multi-user / shared uid).
# Add more in $KS_DIR/apps.list.
#
# Xposed / LSPosed manager apps are excluded: attesting through a hooked process
# breaks STRONG, and these are the managers the other modules keep out too.
#
# Consumed by teesim_config.sh (attestation targets) and hma_sync.sh (apps to
# hide root/modules from — it drops the uid: lines).

MODDIR=${0%/*}
. "$MODDIR/common.sh"
ks_init

# Xposed/LSPosed/hook-framework managers kept OUT of the target list.
XPOSED_EXCLUDE="org.lsposed.manager|io.github.lsposed.manager|org.meowcat.edxposed.manager|de.robv.android.xposed.installer|top.canyie.dreamland.manager|me.weishu.exp|io.github.libxposed.api"

{
  # Play Integrity core — always, pinned by uid too.
  for _p in com.google.android.gms com.android.vending com.google.android.gsf; do
    printf '%s\n' "$_p"
    _u=$(sed -n "s/^$_p \([0-9][0-9]*\) .*/\1/p" /data/system/packages.list 2>/dev/null | head -1)
    case "$_u" in [0-9]*) printf 'uid:%s\n' "$_u" ;; esac
  done

  # Every user-installed app (auto targeting, default on).
  if ks_on auto_target; then
    pm list packages -3 2>/dev/null | sed 's/^package://'
  fi

  # User extras — strip TrickyStore force/leaf suffixes, keep comments out.
  if [ -f "$KS_DIR/apps.list" ]; then
    while IFS= read -r _line || [ -n "$_line" ]; do
      _line=$(printf '%s' "$_line" | tr -d ' \t\r')
      case "$_line" in ''|'#'*) continue ;; esac
      _line=${_line%!}; _line=${_line%\?}
      printf '%s\n' "$_line"
    done < "$KS_DIR/apps.list"
  fi
} | tr -d ' \t\r' \
  | grep -E '^(uid:[0-9]+|[A-Za-z0-9_.]+)$' \
  | grep -Ewv "$XPOSED_EXCLUDE" \
  | awk '!seen[$0]++'
