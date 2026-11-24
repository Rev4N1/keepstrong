#!/system/bin/sh
# KeepStrong — shared helpers.
#
# Sourced by every other script. No side effects beyond defining functions and
# a few path variables, so it is safe to source from post-fs-data, service,
# action and the WebUI backend alike.
#
# Portions adapted from AlwaysStrong (GPL-3.0, Evokerr) — the prop-spoof set,
# the version-aware PIF flag handling and the TEESimulator config/overrides
# shape. See README credits.

# -- Paths ------------------------------------------------------------------
: "${MODULES_BASE:=/data/adb/modules}"
: "${KS_DIR:=/data/adb/keepstrong}"
: "${KS_CONFIG:=$KS_DIR/config}"
: "${KS_LOGS:=$KS_DIR/logs}"
: "${KS_STATE:=$KS_DIR/state}"
: "${TEESIM_DIR:=/data/adb/teesim}"
: "${TEESIM_CONFIG:=$TEESIM_DIR/config.json}"
: "${TEESIM_OVERRIDES:=$TEESIM_DIR/overrides.json}"
: "${TEESIM_KEYBOX:=$TEESIM_DIR/keybox.xml}"

ks_init() {
  mkdir -p "$KS_DIR" "$KS_LOGS" 2>/dev/null
  # Keep the log bounded (the hourly loop appends forever): past ~256 KB keep
  # the newest 1000 lines.
  _lf="$KS_LOGS/keepstrong.log"
  if [ -f "$_lf" ] && [ "$(wc -c < "$_lf" 2>/dev/null | tr -d " ")" -gt 262144 ] 2>/dev/null; then
    tail -n 1000 "$_lf" > "$_lf.tmp" 2>/dev/null && mv -f "$_lf.tmp" "$_lf" 2>/dev/null
  fi
  if [ -f "$KS_CONFIG" ]; then ks_merge_defaults; else ks_write_defaults; fi
  [ -f "$KS_STATE" ] || : > "$KS_STATE"
  # Public keybox mirrors, seeded once. If you edit or clear the list in the
  # WebUI the file exists and is never re-seeded.
  [ -f "$KS_DIR/keybox.urls" ] || ks_seed_urls
}

# -- Logging ----------------------------------------------------------------
# ks_log: log file + logcat; also echoed (indented) when KS_VERBOSE=1, which
# sync.sh sets for Action / WebUI runs so you can watch each step.
ks_log() {
  mkdir -p "$KS_LOGS" 2>/dev/null
  printf '%s %s\n' "$(date '+%m-%d %H:%M:%S' 2>/dev/null)" "$*" >> "$KS_LOGS/keepstrong.log" 2>/dev/null
  log -p i -t KeepStrong "$*" 2>/dev/null || true
  # Verbose echo to stderr so a step's stdout "return value" stays clean while
  # progress still shows on screen / in the WebUI terminal.
  [ "${KS_VERBOSE:-0}" = "1" ] && printf '     %s\n' "$*" >&2
  return 0
}
# ks_say: a step header — always printed, also logged.
ks_say() {
  printf '%s\n' "$*"
  printf '%s %s\n' "$(date '+%m-%d %H:%M:%S' 2>/dev/null)" "$*" >> "$KS_LOGS/keepstrong.log" 2>/dev/null
  return 0
}

# -- Config store (key=value lines in $KS_CONFIG) ---------------------------
# ks_get KEY [DEFAULT]
ks_get() {
  _kg_v=""
  [ -f "$KS_CONFIG" ] && _kg_v=$(sed -n "s/^$1=//p" "$KS_CONFIG" 2>/dev/null | head -1)
  if [ -n "$_kg_v" ]; then printf '%s' "$_kg_v"; else printf '%s' "${2:-}"; fi
  unset _kg_v
}
# ks_set KEY VALUE
ks_set() {
  mkdir -p "$KS_DIR" 2>/dev/null
  [ -f "$KS_CONFIG" ] || : > "$KS_CONFIG"
  if grep -q "^$1=" "$KS_CONFIG" 2>/dev/null; then
    _ksf=$(sed "s|^$1=.*|$1=$2|" "$KS_CONFIG"); printf '%s\n' "$_ksf" > "$KS_CONFIG"; unset _ksf
  else
    printf '%s=%s\n' "$1" "$2" >> "$KS_CONFIG"
  fi
}
# ks_on KEY  -> true when the value is 1
ks_on() { [ "$(ks_get "$1" 0)" = "1" ]; }
# ks_int KEY DEFAULT -> integer value or default
ks_int() { _v=$(ks_get "$1" "$2"); case "$_v" in ''|*[!0-9]*) printf '%s' "$2" ;; *) printf '%s' "$_v" ;; esac; unset _v; }

# The canonical default settings — one "key value" per line. ks_write_defaults
# writes them all; ks_merge_defaults adds only the ones a pre-existing config is
# missing (so an update picks up new keys without clobbering your choices).
KS_DEFAULTS="
enabled 1
auto_keybox 1
auto_fp_sync 1
reassert_pif_flags 1
run_pif_action 1
auto_target 1
manage_hma 1
restart_gms_on_sync 1
spoof_boot_state 1
spoof_patch_props 1
teesim_mode generation
interval_sec 3600
keybox_url
"
# Public keybox mirrors seeded into keybox.urls on first install, so a fresh
# setup can reach STRONG out of the box. Put your own above these in the WebUI.
KS_SEED_URLS="https://rawbin.dpejoh.com/key
https://rawbin.dpejoh.workers.dev/key
http://evoker.qzz.io/key"

ks_write_defaults() {
  mkdir -p "$KS_DIR" 2>/dev/null
  { echo "# KeepStrong settings — one key=value per line. Delete this file to reset."
    printf '%s\n' "$KS_DEFAULTS" | while read -r _k _v; do
      [ -n "$_k" ] || continue; printf '%s=%s\n' "$_k" "$_v"
    done
  } > "$KS_CONFIG"
}
ks_merge_defaults() {
  printf '%s\n' "$KS_DEFAULTS" | while read -r _k _v; do
    [ -n "$_k" ] || continue
    grep -q "^$_k=" "$KS_CONFIG" 2>/dev/null || printf '%s=%s\n' "$_k" "$_v" >> "$KS_CONFIG"
  done
}
ks_seed_urls() { printf '%s\n' "$KS_SEED_URLS" > "$KS_DIR/keybox.urls"; }

# -- Small state store (separate from user config) --------------------------
st_get() { [ -f "$KS_STATE" ] && sed -n "s/^$1=//p" "$KS_STATE" 2>/dev/null | head -1; }
st_set() {
  mkdir -p "$KS_DIR" 2>/dev/null; [ -f "$KS_STATE" ] || : > "$KS_STATE"
  if grep -q "^$1=" "$KS_STATE" 2>/dev/null; then
    _sf=$(sed "s|^$1=.*|$1=$2|" "$KS_STATE"); printf '%s\n' "$_sf" > "$KS_STATE"; unset _sf
  else printf '%s=%s\n' "$1" "$2" >> "$KS_STATE"; fi
}

# -- resetprop helpers (no-ops where resetprop is absent) -------------------
_have_resetprop() { command -v resetprop >/dev/null 2>&1; }
resetprop_if_diff() {
  _have_resetprop || return 0
  _cur=$(resetprop "$1" 2>/dev/null)
  [ "$_cur" = "$2" ] || resetprop -n "$1" "$2" 2>/dev/null
  unset _cur
}
delprop_if_exist() {
  _have_resetprop || return 0
  [ -n "$(resetprop "$1" 2>/dev/null)" ] && resetprop --delete "$1" 2>/dev/null
}

# -- ABI / busybox / network ------------------------------------------------
ks_abi() {
  case "$(uname -m)" in
    aarch64)        echo arm64-v8a ;;
    armv7*|armv8l)  echo armeabi-v7a ;;
    x86_64)         echo x86_64 ;;
    i?86)           echo x86 ;;
    *)              echo "" ;;
  esac
}
ks_busybox() {
  for _bb in /data/adb/ksu/bin/busybox /data/adb/magisk/busybox /data/adb/ap/bin/busybox \
             "$(command -v busybox 2>/dev/null)"; do
    [ -n "$_bb" ] && [ -x "$_bb" ] && { printf '%s' "$_bb"; return 0; }
  done
  return 1
}
ks_check_network() {
  ping -c1 -W2 1.1.1.1 >/dev/null 2>&1 && return 0
  ping -c1 -W2 8.8.8.8 >/dev/null 2>&1 && return 0
  return 1
}
# ks_fetch OUTFILE URL — first downloader that returns bytes wins.
ks_fetch() {
  _o="$1"; _u="$2"; rm -f "$_o" 2>/dev/null
  _bb=$(ks_busybox)
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 15 --max-time 90 -o "$_o" "$_u" 2>/dev/null && [ -s "$_o" ] && { unset _o _u _bb; return 0; }
  fi
  if [ -n "$_bb" ]; then
    "$_bb" wget -q -T 25 -O "$_o" "$_u" 2>/dev/null && [ -s "$_o" ] && { unset _o _u _bb; return 0; }
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -q -T 25 -O "$_o" "$_u" 2>/dev/null && [ -s "$_o" ] && { unset _o _u _bb; return 0; }
  fi
  unset _o _u _bb; return 1
}

# -- Restart Play Integrity / DroidGuard so a new identity takes effect -----
# Delegate to PlayIntegrityFork's own killpi.sh: it ends DroidGuard
# (com.google.android.gms.unstable) and Play Store (com.android.vending) so they
# restart on the next attestation. No `pm clear` (that would wipe the Play Store
# login every sync), and no fallback for other PIF modules — only PIFork is
# driven, so if its script is missing we leave GMS alone and say so.
ks_restart_gms() {
  _rpif=$(ks_pif_dir 2>/dev/null) || _rpif=""
  if [ -n "$_rpif" ] && [ -f "$_rpif/killpi.sh" ]; then
    sh "$_rpif/killpi.sh" >/dev/null 2>&1
    unset _rpif; return 0
  fi
  ks_log "restart: PIFork killpi.sh not found — GMS/Play Store left running"
  unset _rpif; return 1
}
