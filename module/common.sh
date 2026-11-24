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
  [ -f "$KS_CONFIG" ] || ks_write_defaults
  [ -f "$KS_STATE" ] || : > "$KS_STATE"
}

# -- Logging ----------------------------------------------------------------
ks_log() {
  mkdir -p "$KS_LOGS" 2>/dev/null
  printf '%s %s\n' "$(date '+%m-%d %H:%M:%S' 2>/dev/null)" "$*" >> "$KS_LOGS/keepstrong.log" 2>/dev/null
  # Also surface to logcat so `logcat -s KeepStrong` works.
  log -p i -t KeepStrong "$*" 2>/dev/null || true
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

ks_write_defaults() {
  mkdir -p "$KS_DIR" 2>/dev/null
  cat > "$KS_CONFIG" <<'EOF'
# KeepStrong settings — one key=value per line. Delete this file to reset.
enabled=1
auto_keybox=1
auto_fp_sync=1
spoof_boot_state=1
spoof_patch_props=1
reassert_pif_flags=1
restart_gms_on_sync=1
interval_sec=3600
keybox_url=
EOF
}

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
ks_restart_gms() {
  killall -9 com.google.android.gms.unstable 2>/dev/null
  am force-stop com.google.android.gms 2>/dev/null
  pm clear com.android.vending >/dev/null 2>&1
}
