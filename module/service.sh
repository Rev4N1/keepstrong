#!/system/bin/sh
# KeepStrong — late boot (service): re-assert props, first sync, hourly loop.

MODDIR="${0%/*}"
. "$MODDIR/common.sh"
. "$MODDIR/detect.sh"
ks_init
ks_on enabled || exit 0

# Re-assert the locked/green props once the system is up (some ROMs overwrite
# them after post-fs-data).
{
  until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 1; done
  if ks_on spoof_boot_state; then sh "$MODDIR/post-fs-data.sh" 2>/dev/null; fi

  # Resolve ro.boot.vbmeta.digest early if it is still zero, and cache it so the
  # root-of-trust override has a real hash to use.
  _vh=$(resetprop ro.boot.vbmeta.digest 2>/dev/null | tr 'A-F' 'a-f' | tr -d ' \t\r\n')
  case "$_vh" in
    ''|*[!0-9a-f]*|0000000000000000000000000000000000000000000000000000000000000000)
      for p in /dev/block/by-name/vbmeta /dev/block/by-name/vbmeta_a /dev/block/bootdevice/by-name/vbmeta; do
        [ -e "$p" ] && { _calc=$(dd if="$p" bs=4096 count=16 2>/dev/null | sha256sum 2>/dev/null | cut -d' ' -f1 | tr -d ' \t\r\n'); break; }
      done
      case "$_calc" in
        [0-9a-f]*) [ "${#_calc}" -eq 64 ] && { st_set boot_hash "$_calc"; _have_resetprop && resetprop -n ro.boot.vbmeta.digest "$_calc" 2>/dev/null; } ;;
      esac ;;
    *) st_set boot_hash "$_vh" ;;
  esac

  # First full sync a little after boot (let PIF + TEESimulator come up).
  sleep 20
  ks_check_network || sleep 10
  sh "$MODDIR/sync.sh" boot 2>&1 | log -t KeepStrong-boot 2>/dev/null
} &

# Hourly (configurable) refresh loop.
{
  while true; do
    sleep "$(ks_int interval_sec 3600)"
    ks_on enabled || continue
    sh "$MODDIR/sync.sh" 2>&1 | log -t KeepStrong-hourly 2>/dev/null
  done
} &
exit 0
