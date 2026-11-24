#!/system/bin/sh
# KeepStrong — hot install: make a freshly flashed UPDATE live without a reboot.
#
# Managers resolve a module's scripts/WebUI/config from the live dir by path at
# use time; only mounted partition payload is bound to boot. KeepStrong ships
# none (no system/vendor/product/system_ext, no sepolicy.rule, system.prop or
# zygisk), so an update can simply be swapped into the live dir and re-applied.
#
# Sourced by customize.sh, which provides MODPATH, ui_print and the installer's
# root markers. Adapted from Specter's hotinstall (GPL-3.0).

# Updates only (live + staged both present), not disabled / pending removal, and
# a strictly userspace payload.
_ks_hot_gate() {
  [ -d "$1" ] && [ -d "$2" ] || return 1
  [ ! -e "$1/disable" ] && [ ! -e "$1/remove" ] || return 1
  for _hg in system vendor product system_ext sepolicy.rule system.prop zygisk; do
    [ ! -e "$2/$_hg" ] || { unset _hg; return 1; }
  done
  unset _hg; return 0
}

ks_hot_install() {
  _hi_id="$(basename "${MODPATH:-}")"; [ -n "$_hi_id" ] || return 0
  _hi_live="$MODULES_BASE/$_hi_id"
  _hi_stage="${MODULES_BASE}_update/$_hi_id"
  _ks_hot_gate "$_hi_live" "$_hi_stage" || { unset _hi_id _hi_live _hi_stage; return 0; }

  _hi_sol=$(ks_root_sol)

  # Prefer a native consumer that owns the swap (ksud native hot install, or
  # mountify, which exports MOUNTIFY_HAS_HOT_INSTALL into the install shell).
  _hi_del=0
  case "$_hi_sol" in
    kernelsu) [ "${KSU_HAS_HOT_INSTALL:-}" = "true" ] && _hi_del=1
              [ "${MOUNTIFY_HAS_HOT_INSTALL:-}" = "true" ] && _hi_del=1 ;;
    apatch)   [ "${MOUNTIFY_HAS_HOT_INSTALL:-}" = "true" ] && _hi_del=1 ;;
  esac
  if [ "$_hi_del" = "1" ]; then
    # Read by the installer's shell after customize.sh returns.
    MODULE_HOT_INSTALL_REQUEST=true
    MODULE_HOT_RUN_SCRIPT="hotinstall-launcher.sh"
    ui_print "- Hot install requested — no reboot needed"
    unset _hi_id _hi_live _hi_stage _hi_sol _hi_del
    return 0
  fi

  case "$_hi_sol" in kernelsu|magisk|apatch) ;; *) unset _hi_id _hi_live _hi_stage _hi_sol _hi_del; return 0 ;; esac

  ui_print "- Hot install: applying update without a reboot..."

  # Stash the old live dir (running processes may still reference it) rather
  # than delete it; roll back if either move fails.
  _hi_trash="$KS_DIR/.hot_trash"
  rm -rf "$_hi_trash" 2>/dev/null; mkdir -p "$_hi_trash" 2>/dev/null
  if ! mv "$_hi_live" "$_hi_trash/$_hi_id" 2>/dev/null; then
    ui_print "- Hot install skipped — reboot to apply"
    unset _hi_id _hi_live _hi_stage _hi_sol _hi_del _hi_trash; return 0
  fi
  if ! mv "$_hi_stage" "$_hi_live" 2>/dev/null; then
    mv "$_hi_trash/$_hi_id" "$_hi_live" 2>/dev/null
    ui_print "- Hot install failed — reboot to apply"
    unset _hi_id _hi_live _hi_stage _hi_sol _hi_del _hi_trash; return 0
  fi

  rm -f "$KS_DIR/.hotinstall_failed" 2>/dev/null
  sh "$_hi_live/hotinstall.sh" 2>&1 | while IFS= read -r _hl; do [ -n "$_hl" ] && ui_print "    $_hl"; done

  # KernelSU copies module.prop from the staged dir after customize.sh returns;
  # leave a stub so it has one. Only for a genuine KernelSU install.
  if [ "$_hi_sol" = "kernelsu" ] && [ -n "${KSU_VER:-}${KSU_VER_CODE:-}" ]; then
    mkdir -p "$_hi_stage" 2>/dev/null
    cp "$_hi_live/module.prop" "$_hi_stage/module.prop" 2>/dev/null
  fi

  # Delayed cleanup: the installers write an `update` flag into the live dir and
  # may re-touch the staged dir after customize.sh returns.
  ( sleep "${KS_HOT_CLEANUP_DELAY:-3}"
    rm -rf "$_hi_live/update" 2>/dev/null
    rm -rf "$_hi_stage" 2>/dev/null
    rm -rf "$_hi_trash" 2>/dev/null ) &

  if [ -f "$KS_DIR/.hotinstall_failed" ]; then
    rm -f "$KS_DIR/.hotinstall_failed"
    ui_print "- WARNING: live-apply failed — tap Action in the WebUI or reboot"
  else
    ui_print "- Update applied live — no reboot needed (refresh the module page)"
  fi
  unset _hi_id _hi_live _hi_stage _hi_sol _hi_del _hi_trash _hl
}
