#!/system/bin/sh
# KeepStrong — locate the user-installed modules this orchestrator drives.
# Sourced after common.sh. Defines detection helpers only.

# PIF module ids, newest first. osm0sis PlayIntegrityFork ships as
# `playintegrityfork`; the older/inject lines use `playintegrityfix`.
: "${KS_PIF_IDS:=playintegrityfork playintegrityfix}"

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

# ks_pif_kind DIR -> fork | inject | unknown
# Distinguishes osm0sis Fork (spoofVendingFinger flag) from chiteroman/KOWX712
# inject-s (spoofVendingBuild), and rejects id-squatting keystore toolkits.
ks_pif_kind() {
  _mp="$1/module.prop"
  [ -f "$_mp" ] || { echo unknown; return 1; }
  if grep -qiE 'MeowDump|ntegrity.?[Bb]ox|webuiIcon' "$_mp" 2>/dev/null; then
    echo unknown; unset _mp; return 1
  fi
  _id="$(grep -m1 '^name=' "$_mp")$(grep -m1 '^updateJson=' "$_mp")$(grep -m1 '^author=' "$_mp")"
  case "$_id" in
    *Fork*|*osm0sis*)                          echo fork ;;
    *Fix*|*[Ii]nject*|*chiteroman*|*KOWX712*)  echo inject ;;
    *)                                         echo unknown ;;
  esac
  unset _mp _id
}

# The prop file that actually carries the Pixel FINGERPRINT.
#   Fork keeps it in custom.pif.prop; inject-s in pif.prop.
ks_pif_src() {
  _d=$(ks_pif_dir) || { unset _d; return 1; }
  for _c in "$_d/custom.pif.prop" "$_d/pif.prop"; do
    [ -s "$_c" ] && grep -q '^FINGERPRINT=' "$_c" 2>/dev/null && { printf '%s' "$_c"; unset _d _c; return 0; }
  done
  unset _d _c; return 1
}

ks_teesim_present() { [ -f "$MODULES_BASE/teesim/module.prop" ] || [ -f "${MODULES_BASE}_update/teesim/module.prop" ]; }

# HMA-OSS (org.frknkrc44.hma_oss) keeps its config as a single compact-JSON file
# at /data/misc/hide_my_applist_<random>/config.json, created on first boot /
# first launch of the HMA app.
: "${HMAOSS_BASE:=/data/misc}"
ks_hma_dir() {
  for _d in "$HMAOSS_BASE"/hide_my_applist*; do
    [ -d "$_d" ] && { printf '%s' "$_d"; unset _d; return 0; }
  done
  unset _d; return 1
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
