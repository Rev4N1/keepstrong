#!/system/bin/sh
# KeepStrong — generate JingMatrix TEESimulator config from the PIF identity.
#
# This is the crux of reaching STRONG with a bring-your-own stack. Your
# PlayIntegrityFork spoofs android.os.Build to a Pixel; TEESimulator must attest
# the SAME Pixel, or Play Integrity fails on the mismatch. We:
#   1. mirror brand/device/product/manufacturer/model + security patch out of
#      the PIF fingerprint into /data/adb/teesim/config.json,
#   2. target the Play Integrity core (+ your apps) in that profile,
#   3. run the profile in "generation" mode so it works even where the device's
#      real TEE keystore is unavailable (common on custom ROMs),
#   4. write /data/adb/teesim/overrides.json so the attested root of trust is a
#      locked/Verified boot with a stable non-zero key+hash — on an unlocked
#      bootloader TEESimulator would otherwise harvest a zeroed ORANGE root and
#      never reach STRONG.
#
# The TEESimulator daemon watches /data/adb/teesim and re-reads keybox + config
# on every config write, so rewriting config.json is also how it picks up a new
# keybox. We never launch its daemon — its own module does that.
#
# Config/overrides shape adapted from AlwaysStrong (GPL-3.0). Requires the
# user's TEESimulator (JingMatrix) and a keybox at /data/adb/teesim/keybox.xml.

MODDIR=${0%/*}
. "$MODDIR/common.sh"
. "$MODDIR/detect.sh"
ks_init

ks_teesim_present || { ks_log "teesim_config: TEESimulator (teesim) not installed, skipping"; exit 1; }
mkdir -p "$TEESIM_DIR" 2>/dev/null

# --- device identity from the active PIF fingerprint -----------------------
_pif=$(ks_pif_src) || _pif=""
# Quotes, backslashes and control characters are dropped so a value can never
# break the JSON written below.
_pget() { [ -n "$_pif" ] && sed -n "s/^$1=//p" "$_pif" | head -1 | sed 's/["\\]//g; s/[[:cntrl:]]//g'; }
_fp=$(_pget FINGERPRINT)
_brand=$(_pget BRAND);   [ -z "$_brand" ] && [ -n "$_fp" ] && _brand=$(printf '%s' "$_fp" | cut -d/ -f1)
_manu=$(_pget MANUFACTURER)
_model=$(_pget MODEL)
_device=$(_pget DEVICE)
_product=$(_pget PRODUCT)
# Security patch MUST match the value PIFork spoofs into
# ro.build.version.security_patch (the attested device is the Pixel PIF presents
# to Build; a mismatched patch drops STRONG). All three partitions get it. Only
# when PIFork carries none do we fall back to teesim's own "today"/"YYYY-MM-05"
# defaults.
_patch=$(ks_pif_patch) || _patch=""
case "$_patch" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) _sys="$_patch"; _ven="$_patch"; _boot="$_patch" ;;
  *) _sys="today"; _ven="YYYY-MM-05"; _boot="YYYY-MM-05" ;;
esac
# OS version: match the Android release PIF spoofs (fingerprint ".../:<ver>/...").
# Empty = reuse teesim's harvested value.
_osver=$(printf '%s' "$_fp" | sed -n 's#^[^:]*:\([0-9][0-9.]*\)/.*#\1#p')
# Operation mode: generation mints the whole key under the keybox (works even
# where the real TEE keystore is unavailable, as on many custom ROMs); patch
# re-signs the real hardware key. teesim auto-falls-back to generation when
# hardware is unavailable, so generation is the safe default.
_mode=$(ks_get teesim_mode generation)
case "$_mode" in patch|generation) : ;; *) _mode=generation ;; esac

# --- target apps (sanitised into TEESimulator's schema) --------------------
# build_target.sh already de-dupes and validates; wrap each line as a JSON
# string. Command substitution drops the trailing newline; sed drops the final
# comma so the array stays valid JSON.
_apps=$(sh "$MODDIR/build_target.sh" 2>/dev/null | awk 'NF{printf "      \"%s\",\n", $0}' | sed '$ s/,$//')

# --- root of trust: force locked/Verified with a non-zero key+hash ---------
_hex64() { case "$1" in ''|*[!0-9a-f]*) return 1 ;; esac; [ "${#1}" -eq 64 ] || return 1; case "$1" in *[!0]*) return 0 ;; *) return 1 ;; esac; }
_clean() { printf '%s' "$1" | tr 'A-F' 'a-f' | tr -d ' \t\r\n:'; }

_vbh=""
_have_resetprop && _vbh=$(_clean "$(resetprop ro.boot.vbmeta.digest 2>/dev/null)")
_hex64 "$_vbh" || _vbh=$(_clean "$(st_get boot_hash)")
_hex64 "$_vbh" || _vbh=""

_vbk=$(_clean "$(st_get teesim_vbk)")
_hex64 "$_vbk" || _vbk=""
if [ -z "$_vbk" ] && _have_resetprop; then
  _p=$(_clean "$(resetprop ro.boot.vbmeta.public_key_digest 2>/dev/null)")
  _hex64 "$_p" && _vbk="$_p"
fi
if [ -z "$_vbk" ]; then
  _seed="$_fp"; [ -n "$_seed" ] || _seed="${_model}${_device}"; [ -n "$_seed" ] || _seed="keepstrong-teesim"
  _vbk=$(printf 'KeepStrong-vbk:%s' "$_seed" | sha256sum 2>/dev/null | cut -c1-64)
  _vbk=$(_clean "$_vbk"); _hex64 "$_vbk" || _vbk=""
fi
[ -n "$_vbk" ] && st_set teesim_vbk "$_vbk"
if [ -n "$_vbk" ] && _have_resetprop; then
  [ "$(_clean "$(resetprop ro.boot.vbmeta.public_key_digest 2>/dev/null)")" = "$_vbk" ] ||
    resetprop -n ro.boot.vbmeta.public_key_digest "$_vbk" 2>/dev/null
fi

{
  printf '{\n'
  printf '  "deviceLocked": true,\n'
  printf '  "verifiedBootState": 0'
  [ -n "$_vbk" ] && printf ',\n  "verifiedBootKey": "%s"' "$_vbk"
  [ -n "$_vbh" ] && printf ',\n  "verifiedBootHash": "%s"' "$_vbh"
  printf '\n}\n'
} > "$TEESIM_OVERRIDES.tmp" 2>/dev/null && mv -f "$TEESIM_OVERRIDES.tmp" "$TEESIM_OVERRIDES" 2>/dev/null
chmod 0600 "$TEESIM_OVERRIDES" 2>/dev/null

# --- config.json -----------------------------------------------------------
cat > "$TEESIM_CONFIG.tmp" <<EOF
{
  "version": 1,
  "profiles": {
    "default": {
      "keybox": "keybox.xml",
      "mode": "$_mode",
      "patchLevel": { "system": "$_sys", "vendor": "$_ven", "boot": "$_boot" },
      "osVersion": "$_osver",
      "brand": "$_brand",
      "device": "$_device",
      "product": "$_product",
      "manufacturer": "$_manu",
      "model": "$_model",
      "serial": "",
      "imei": "",
      "meid": "",
      "imei2": "",
      "apps": [
$_apps
      ]
    }
  }
}
EOF
mv -f "$TEESIM_CONFIG.tmp" "$TEESIM_CONFIG" 2>/dev/null
chmod 0600 "$TEESIM_CONFIG" 2>/dev/null
ks_log "teesim_config: wrote config.json (model='${_model:-?}' patch='$_sys' apps) + overrides.json"
