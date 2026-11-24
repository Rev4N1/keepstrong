#!/system/bin/sh
# KeepStrong — fetch the attestation keybox from YOUR endpoint.
#
# The endpoint is whatever you set in `keybox_url` (WebUI field or
# $KS_DIR/config). KeepStrong ships NO default server. The payload may be the
# raw keybox XML, or base64-encoded XML (both are accepted). It is validated to
# actually look like a keybox, hashed against the on-disk file to avoid
# needless rewrites, then atomically installed at /data/adb/teesim/keybox.xml
# and the TEESimulator config is rewritten so the daemon re-reads it.
#
# Exit: 0 updated | 2 unchanged / nothing to do | 1 fetch or verify failed.

MODDIR=${0%/*}
. "$MODDIR/common.sh"
. "$MODDIR/detect.sh"
ks_init

URL=$(ks_get keybox_url "")
[ -n "$URL" ] || { ks_log "keybox_fetch: no keybox_url set, skipping"; exit 2; }
ks_on auto_keybox || { ks_log "keybox_fetch: auto_keybox off, skipping"; exit 2; }
ks_teesim_present || { ks_log "keybox_fetch: TEESimulator not installed, skipping"; exit 2; }

mkdir -p "$TEESIM_DIR" 2>/dev/null
TMP=$(mktemp -d 2>/dev/null || { mkdir -p "$KS_DIR/.kb.$$"; echo "$KS_DIR/.kb.$$"; })
trap 'rm -rf "$TMP"' EXIT INT TERM

ks_check_network || { ks_log "keybox_fetch: no network"; exit 1; }
ks_fetch "$TMP/raw" "$URL" || { ks_log "keybox_fetch: download failed ($URL)"; exit 1; }

# Decode: try base64 first, fall back to raw.
B64=""
if echo dGVzdA== | base64 -d >/dev/null 2>&1; then B64="base64 -d"; else
  _bb=$(ks_busybox); [ -n "$_bb" ] && echo dGVzdA== | "$_bb" base64 -d >/dev/null 2>&1 && B64="$_bb base64 -d"
fi
if [ -n "$B64" ] && $B64 < "$TMP/raw" 2>/dev/null > "$TMP/dec" && head -c 4096 "$TMP/dec" 2>/dev/null | grep -q "Keybox"; then
  cp -f "$TMP/dec" "$TMP/keybox.xml"
elif head -c 4096 "$TMP/raw" 2>/dev/null | grep -q "Keybox"; then
  cp -f "$TMP/raw" "$TMP/keybox.xml"
else
  ks_log "keybox_fetch: payload is not a keybox — discarding"
  exit 1
fi

SHA="sha256sum"; command -v sha256sum >/dev/null 2>&1 || { _bb=$(ks_busybox); [ -n "$_bb" ] && SHA="$_bb sha256sum"; }
NEW=$($SHA < "$TMP/keybox.xml" 2>/dev/null | awk '{print tolower($1)}')
OLD=""; [ -s "$TEESIM_KEYBOX" ] && OLD=$($SHA < "$TEESIM_KEYBOX" 2>/dev/null | awk '{print tolower($1)}')
if [ -n "$OLD" ] && [ "$OLD" = "$NEW" ]; then
  ks_log "keybox_fetch: already up to date"
  exit 2
fi

mv -f "$TMP/keybox.xml" "$TEESIM_KEYBOX" 2>/dev/null || { ks_log "keybox_fetch: install failed"; exit 1; }
chmod 600 "$TEESIM_KEYBOX" 2>/dev/null
ks_log "keybox_fetch: keybox updated ($(wc -c < "$TEESIM_KEYBOX" 2>/dev/null) bytes)"

# Rewrite config so the TEESimulator daemon re-reads the new keybox.
sh "$MODDIR/teesim_config.sh" >/dev/null 2>&1
exit 0
