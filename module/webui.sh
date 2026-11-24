#!/system/bin/sh
# KeepStrong — WebUI backend. The page calls `sh webui.sh <cmd> [args]` through
# the root manager's ksu.exec bridge. All output on stdout.
#
#   status            -> one-line JSON: presence, settings, last sync
#   get KEY           -> raw value
#   set KEY VALUE     -> persist a setting
#   apps-get          -> contents of apps.list
#   apps-set <b64>    -> replace apps.list from base64
#   urls-get          -> keybox endpoints, one per line (file + legacy value)
#   urls-set <b64>    -> replace keybox.urls from base64
#   hide-get          -> HMA extra hide-list (hma_hide.list)
#   hide-set <b64>    -> replace hma_hide.list from base64
#   sync              -> run one full sync, stream the pipeline log
#   log               -> tail of the log
#   version           -> module version

MODDIR=${0%/*}
. "$MODDIR/common.sh"
. "$MODDIR/detect.sh"
ks_init

_jesc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
_bool() { if [ "$1" = present ] || [ "$1" = "1" ]; then echo true; else echo false; fi; }

cmd="$1"; shift 2>/dev/null

case "$cmd" in
  status)
    _dir=$(ks_pif_dir 2>/dev/null) && _kind=$(ks_pif_kind "$_dir" 2>/dev/null) || _kind=none
    _tee=absent; ks_teesim_present && _tee=present
    _hma=absent; ks_hma_present && _hma=present
    _hmacfg=false; ks_hma_config >/dev/null 2>&1 && _hmacfg=true
    _kb=false; [ -s "$TEESIM_KEYBOX" ] && _kb=true
    printf '{'
    printf '"pif":"%s",' "$_kind"
    printf '"teesim":%s,' "$(_bool "$_tee")"
    printf '"hma":%s,' "$(_bool "$_hma")"
    printf '"hma_config":%s,' "$_hmacfg"
    printf '"keybox":%s,' "$_kb"
    printf '"last_sync":"%s",' "$(_jesc "$(st_get last_sync)")"
    printf '"enabled":%s,' "$(_bool "$(ks_get enabled 0)")"
    printf '"auto_keybox":%s,' "$(_bool "$(ks_get auto_keybox 0)")"
    printf '"auto_fp_sync":%s,' "$(_bool "$(ks_get auto_fp_sync 0)")"
    printf '"reassert_pif_flags":%s,' "$(_bool "$(ks_get reassert_pif_flags 0)")"
    printf '"run_pif_action":%s,' "$(_bool "$(ks_get run_pif_action 0)")"
    printf '"auto_target":%s,' "$(_bool "$(ks_get auto_target 0)")"
    printf '"manage_hma":%s,' "$(_bool "$(ks_get manage_hma 0)")"
    printf '"restart_gms_on_sync":%s,' "$(_bool "$(ks_get restart_gms_on_sync 0)")"
    printf '"spoof_boot_state":%s,' "$(_bool "$(ks_get spoof_boot_state 0)")"
    printf '"spoof_patch_props":%s,' "$(_bool "$(ks_get spoof_patch_props 0)")"
    printf '"teesim_mode":"%s",' "$(_jesc "$(ks_get teesim_mode generation)")"
    printf '"interval_sec":"%s",' "$(_jesc "$(ks_get interval_sec 3600)")"
    _n=0; [ -f "$KS_DIR/keybox.urls" ] && _n=$(grep -cE '^[[:space:]]*[^#[:space:]]' "$KS_DIR/keybox.urls" 2>/dev/null)
    [ -n "$(ks_get keybox_url)" ] && _n=$((_n + 1))
    printf '"keybox_url_count":%s' "${_n:-0}"
    printf '}\n'
    ;;
  get) ks_get "$1" "$2" ;;
  set) ks_set "$1" "$2"; echo ok ;;
  apps-get) [ -f "$KS_DIR/apps.list" ] && cat "$KS_DIR/apps.list" || echo "" ;;
  apps-set)
    printf '%s' "$1" | base64 -d > "$KS_DIR/apps.list" 2>/dev/null || {
      _bb=$(ks_busybox); [ -n "$_bb" ] && printf '%s' "$1" | "$_bb" base64 -d > "$KS_DIR/apps.list" 2>/dev/null; }
    echo ok ;;
  urls-get)
    # Merge the list file with the legacy single value, de-duplicated.
    { [ -f "$KS_DIR/keybox.urls" ] && cat "$KS_DIR/keybox.urls"; _lv=$(ks_get keybox_url); [ -n "$_lv" ] && printf '%s\n' "$_lv"; } \
      | awk 'NF && !/^#/ && !seen[$0]++' ;;
  urls-set)
    printf '%s' "$1" | base64 -d > "$KS_DIR/keybox.urls" 2>/dev/null || {
      _bb=$(ks_busybox); [ -n "$_bb" ] && printf '%s' "$1" | "$_bb" base64 -d > "$KS_DIR/keybox.urls" 2>/dev/null; }
    # The list supersedes the single legacy value; clear it to avoid confusion.
    ks_set keybox_url ""
    echo ok ;;
  hide-get) [ -f "$KS_DIR/hma_hide.list" ] && cat "$KS_DIR/hma_hide.list" || echo "" ;;
  hide-set)
    printf '%s' "$1" | base64 -d > "$KS_DIR/hma_hide.list" 2>/dev/null || {
      _bb=$(ks_busybox); [ -n "$_bb" ] && printf '%s' "$1" | "$_bb" base64 -d > "$KS_DIR/hma_hide.list" 2>/dev/null; }
    echo ok ;;
  sync) sh "$MODDIR/sync.sh" action 2>&1; echo "---"; echo "sync complete" ;;
  log) tail -n 200 "$KS_LOGS/keepstrong.log" 2>/dev/null ;;
  version) grep '^version=' "$MODDIR/module.prop" 2>/dev/null | cut -d= -f2 ;;
  *) echo "unknown command: $cmd" >&2; exit 1 ;;
esac
