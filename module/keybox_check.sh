#!/system/bin/sh
# KeepStrong — keybox revocation check.
#
# A keybox only yields STRONG while its attestation key is NOT on Google's
# revocation list. This extracts the leaf certificate's serial from the keybox
# and checks it against Google's published status list, so you get a clear
# warning the moment your keybox is burned (instead of a silent drop to BASIC).
#
# Read-only: never edits the keybox. Serial is parsed from the cert's ASN.1 in
# awk (busybox-safe, no openssl needed). Method mirrors Specter (GPL-3.0).
#
# Usage: keybox_check.sh [keybox.xml]   (default /data/adb/teesim/keybox.xml)
# Prints one of: OK | REVOKED:<reason> | UNKNOWN:<why>. Sets state keys
# keybox_revoked / keybox_serial / keybox_checked for the WebUI.

MODDIR=${0%/*}
. "$MODDIR/common.sh"
ks_init

KB="${1:-$TEESIM_KEYBOX}"
GOOGLE_URL="https://android.googleapis.com/attestation/status?encrypted=0"
CACHE="$KS_DIR/.revocation.json"
CACHE_TTL=21600   # 6h

[ -s "$KB" ] || { echo "UNKNOWN:no keybox"; ks_log "keybox_check: no keybox at $KB"; exit 2; }

# --- extract the leaf certificate serial (hex) -----------------------------
_b64=$(sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p; /-----END CERTIFICATE-----/q' "$KB" \
       | grep -v 'CERTIFICATE' | tr -d ' \t\r\n')
[ -n "$_b64" ] || { echo "UNKNOWN:no certificate"; exit 2; }

_dec="base64 -d"; echo dGVzdA== | base64 -d >/dev/null 2>&1 || { _bb=$(ks_busybox); [ -n "$_bb" ] && _dec="$_bb base64 -d"; }
_hex=$(printf '%s' "$_b64" | $_dec 2>/dev/null | od -An -v -tx1 2>/dev/null | tr -d ' \n')
[ -n "$_hex" ] || { echo "UNKNOWN:decode failed"; exit 2; }

_awk="awk"; command -v awk >/dev/null 2>&1 || { _bb=$(ks_busybox); [ -n "$_bb" ] && _awk="$_bb awk"; }
_serial=$(printf '%s' "$_hex" | $_awk '
  function h2d(hh,   a,b){ a=index("0123456789abcdef",substr(hh,1,1))-1; b=index("0123456789abcdef",substr(hh,2,1))-1; if(a<0||b<0) return -1; return a*16+b }
  function declen(s,p){ _b=h2d(substr(s,p,2)); p+=2; if(_b<0){_LV=-1;return} if(_b<128){_LV=_b;_LP=p;return} _n=_b-128;_LV=0; while(_n-->0){_d=h2d(substr(s,p,2)); if(_d<0){_LV=-1;return} _LV=_LV*256+_d; p+=2} _LP=p }
  { s=$0; p=1
    if(substr(s,p,2)!="30") exit 1; p+=2; declen(s,p); if(_LV<0) exit 1; p=_LP      # Certificate SEQUENCE
    if(substr(s,p,2)!="30") exit 1; p+=2; declen(s,p); if(_LV<0) exit 1; p=_LP      # tbsCertificate SEQUENCE
    if(substr(s,p,2)=="a0"){ p+=2; declen(s,p); if(_LV<0) exit 1; p=_LP + _LV*2 }   # optional [0] version
    if(substr(s,p,2)!="02") exit 1; p+=2; declen(s,p); if(_LV<0) exit 1             # serialNumber INTEGER
    ser=substr(s,_LP,_LV*2); sub(/^(00)+/,"",ser); if(ser=="") ser="00"
    print tolower(ser)
  }')
[ -n "$_serial" ] || { echo "UNKNOWN:serial parse failed"; ks_log "keybox_check: could not parse serial"; exit 2; }
st_set keybox_serial "$_serial"

# --- revocation list (cached) ----------------------------------------------
_fresh=0
if [ -s "$CACHE" ] && grep -q '"entries"' "$CACHE" 2>/dev/null; then
  _age=$(( $(date +%s 2>/dev/null || echo 0) - $(date -r "$CACHE" +%s 2>/dev/null || echo 0) ))
  [ "$_age" -ge 0 ] && [ "$_age" -lt "$CACHE_TTL" ] && _fresh=1
fi
if [ "$_fresh" = 0 ]; then
  if ks_check_network && ks_fetch "$CACHE.tmp" "$GOOGLE_URL" && grep -q '"entries"' "$CACHE.tmp" 2>/dev/null; then
    mv -f "$CACHE.tmp" "$CACHE" 2>/dev/null
  else
    rm -f "$CACHE.tmp" 2>/dev/null
    [ -s "$CACHE" ] || { echo "UNKNOWN:no revocation list"; ks_log "keybox_check: revocation list unavailable"; exit 2; }
  fi
fi

# Google lists revoked serials as lowercase hex keys. Match our serial (and its
# zero-stripped form) as a JSON key.
_entry=""
for _s in "$_serial" "$(printf '%s' "$_serial" | sed 's/^0*//')"; do
  [ -n "$_s" ] || continue
  _entry=$(tr -d '\n\r' < "$CACHE" | grep -o "\"$_s\"[[:space:]]*:[[:space:]]*{[^}]*}" | head -1)
  [ -n "$_entry" ] && break
done

st_set keybox_checked "$(date '+%Y-%m-%d %H:%M' 2>/dev/null)"
if [ -n "$_entry" ]; then
  _reason=$(printf '%s' "$_entry" | sed -n 's/.*"reason"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  [ -n "$_reason" ] || _reason=$(printf '%s' "$_entry" | sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  [ -n "$_reason" ] || _reason="listed"
  st_set keybox_revoked true
  echo "REVOKED:$_reason"
  ks_log "keybox_check: KEYBOX REVOKED (serial ${_serial}, $_reason) — fetch a fresh keybox"
  exit 1
fi
st_set keybox_revoked false
echo "OK"
ks_log "keybox_check: keybox OK (serial $_serial not revoked)"
exit 0
