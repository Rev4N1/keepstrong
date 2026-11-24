#!/system/bin/sh
# KeepStrong — locate the user-installed modules this orchestrator drives.
# Sourced after common.sh. Defines detection helpers only.

# Only osm0sis PlayIntegrityFork is supported, under its module id
# `playintegrityfork`. ks_pif_kind also checks name + author so another module
# squatting that id is not driven.
: "${KS_PIF_IDS:=playintegrityfork}"

# ks_pif_dir -> prints the installed/staged PIF module dir, or nothing (rc 1).
ks_pif_dir() {
  for _id in $KS_PIF_IDS; do
    for _base in "$MODULES_BASE" "${MODULES_BASE}_update"; do
      if [ -f "$_base/$_id/module.prop" ]; then
        printf '%s' "$_base/$_id"; unset _id _base; return 0
      fi
    done
  done
  unset _id _base; return 1
}

# ks_pif_kind DIR -> installed | unknown
# Confirms the module is osm0sis PlayIntegrityFork by its name + author, so an
# impostor squatting the id (e.g. a keystore toolkit) is not accepted.
ks_pif_kind() {
  _mp="$1/module.prop"
  [ -f "$_mp" ] || { echo unknown; return 1; }
  if grep -qiE 'MeowDump|ntegrity.?[Bb]ox|webuiIcon' "$_mp" 2>/dev/null; then
    echo unknown; unset _mp; return 1
  fi
  _name=$(grep -m1 '^name=' "$_mp" 2>/dev/null | cut -d= -f2-)
  _author=$(grep -m1 '^author=' "$_mp" 2>/dev/null | cut -d= -f2-)
  case "$_name $_author" in
    *"Play Integrity Fork"*osm0sis*) echo installed ;;
    *)                              echo unknown ;;
  esac
  unset _mp _name _author
}

# The prop file that carries the Pixel FINGERPRINT. PIFork uses
# custom.pif.prop; the legacy custom.pif.json is not mirrored.
ks_pif_src() {
  _d=$(ks_pif_dir) || { unset _d; return 1; }
  [ "$(ks_pif_kind "$_d")" = "installed" ] || { unset _d; return 1; }
  _c="$_d/custom.pif.prop"
  [ -s "$_c" ] && grep -q '^FINGERPRINT=' "$_c" 2>/dev/null && { printf '%s' "$_c"; unset _d _c; return 0; }
  unset _d _c; return 1
}

# ks_pif_patch -> the security patch PIFork presents, as YYYY-MM-DD, or
# nothing (rc 1). PIFork's custom.pif.prop carries both the Build field
# (SECURITY_PATCH) and the system property (ro.build.version.security_patch)
# that becomes what DroidGuard sees; the property wins when present.
ks_pif_patch() {
  _f=$(ks_pif_src) || { unset _f; return 1; }
  _p=$(sed -n 's/^ro\.build\.version\.security_patch=//p' "$_f" 2>/dev/null | head -1)
  [ -n "$_p" ] || _p=$(sed -n 's/^SECURITY_PATCH=//p' "$_f" 2>/dev/null | head -1)
  _p=$(printf '%s' "$_p" | cut -d'#' -f1 | tr -d ' "\r')
  _d=$(printf '%s' "$_p" | tr -cd '0-9')
  [ "${#_d}" -eq 8 ] || { unset _f _p _d; return 1; }
  printf '%s-%s-%s' "$(printf '%s' "$_d" | cut -c1-4)" "$(printf '%s' "$_d" | cut -c5-6)" "$(printf '%s' "$_d" | cut -c7-8)"
  unset _f _p _d
}

ks_teesim_present() { [ -f "$MODULES_BASE/teesim/module.prop" ] || [ -f "${MODULES_BASE}_update/teesim/module.prop" ]; }

# HMA-OSS (org.frknkrc44.hma_oss) keeps its config as a single compact-JSON file
# at /data/misc/hide_my_applist_<random>/config.json, created on first boot /
# first launch of the HMA app.
: "${HMAOSS_BASE:=/data/misc}"
# A reinstall of HMA can leave an older hide_my_applist_* dir behind, so prefer
# the one whose config.json was written most recently.
ks_hma_dir() {
  _best=""
  for _d in "$HMAOSS_BASE"/hide_my_applist*; do
    [ -d "$_d" ] || continue
    if [ -z "$_best" ]; then _best="$_d"
    elif [ -f "$_d/config.json" ] && { [ ! -f "$_best/config.json" ] || [ "$_d/config.json" -nt "$_best/config.json" ]; }; then _best="$_d"
    fi
  done
  [ -n "$_best" ] && printf '%s' "$_best"
  [ -n "$_best" ]; _rc=$?; unset _d _best; return $_rc
}
ks_hma_config() {
  _hd=$(ks_hma_dir) || { unset _hd; return 1; }
  [ -f "$_hd/config.json" ] && { printf '%s' "$_hd/config.json"; unset _hd; return 0; }
  unset _hd; return 1
}
ks_hma_present() { ks_hma_dir >/dev/null 2>&1; }

# Root solution — for hot install's per-manager swap. The installers export
# their markers (KSU_VER / APATCH) into customize.sh's shell; the /data/adb/*
# dirs are the fallback.
ks_root_sol() {
  if [ -n "${KSU_VER:-}${KSU_VER_CODE:-}" ] || [ -d /data/adb/ksu ]; then echo kernelsu
  elif [ -n "${APATCH:-}${APATCH_VER:-}" ] || [ -d /data/adb/ap ]; then echo apatch
  else echo magisk; fi
}
