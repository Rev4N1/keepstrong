#!/system/bin/sh
# KeepStrong — fetch the attestation keybox from YOUR endpoints.
#
# Endpoints come from $KS_DIR/keybox.urls (one URL per line, tried in order),
# with the legacy single `keybox_url` config value appended if set. The first
# endpoint that returns a valid keybox wins — so put your own first and add
# public mirrors below it as fallbacks in case yours drops. A fresh install is
# seeded with public mirrors (see KS_SEED_URLS in common.sh).
#
# Each payload may be raw keybox XML or base64-encoded XML (both accepted). A
# valid keybox is hashed against the on-disk file to avoid needless rewrites,
# then atomically installed at /data/adb/teesim/keybox.xml and the TEESimulator
# config is rewritten so the daemon re-reads it.
#
# Exit: 0 updated | 2 unchanged / nothing to do | 1 all endpoints failed.

MODDIR=${0%/*}
. "$MODDIR/common.sh"
. "$MODDIR/detect.sh"
ks_init

ks_on auto_keybox || { ks_log "keybox_fetch: auto_keybox off, skipping"; exit 2; }
ks_teesim_present || { ks_log "keybox_fetch: TEESimulator not installed, skipping"; exit 2; }

# Build the endpoint list: keybox.urls file first, then the legacy single value.
URLS=""
if [ -f "$KS_DIR/keybox.urls" ]; then
  while IFS= read -r _u || [ -n "$_u" ]; do
    _u=$(printf '%s' "$_u" | tr -d ' \t\r')
    case "$_u" in ''|'#'*) continue ;; esac
    URLS="$URLS$_u
"
  done < "$KS_DIR/keybox.urls"
fi
_legacy=$(ks_get keybox_url "")
[ -n "$_legacy" ] && case "$URLS" in *"$_legacy"*) : ;; *) URLS="$URLS$_legacy"'
' ;; esac

[ -n "$URLS" ] || { ks_log "keybox_fetch: no endpoints set, skipping"; exit 2; }

mkdir -p "$TEESIM_DIR" 2>/dev/null
TMP=$(mktemp -d 2>/dev/null || { mkdir -p "$KS_DIR/.kb.$$"; echo "$KS_DIR/.kb.$$"; })
trap 'rm -rf "$TMP"' EXIT INT TERM

# Decoder + hasher, resolved once.
B64=""
if echo dGVzdA== | base64 -d >/dev/null 2>&1; then B64="base64 -d"; else
  _bb=$(ks_busybox); [ -n "$_bb" ] && echo dGVzdA== | "$_bb" base64 -d >/dev/null 2>&1 && B64="$_bb base64 -d"
fi
SHA="sha256sum"; command -v sha256sum >/dev/null 2>&1 || { _bb=$(ks_busybox); [ -n "$_bb" ] && SHA="$_bb sha256sum"; }

# Turn $TMP/raw into a validated $TMP/keybox.xml, or fail (rc 1).
_decode_valid() {
  if [ -n "$B64" ] && $B64 < "$TMP/raw" 2>/dev/null > "$TMP/dec" && head -c 4096 "$TMP/dec" 2>/dev/null | grep -q "Keybox"; then
    cp -f "$TMP/dec" "$TMP/keybox.xml"; return 0
  elif head -c 4096 "$TMP/raw" 2>/dev/null | grep -q "Keybox"; then
    cp -f "$TMP/raw" "$TMP/keybox.xml"; return 0
  fi
  return 1
}

if ! ks_check_network; then ks_log "keybox_fetch: no network"; exit 1; fi

printf '%s\n' "$URLS" | while IFS= read -r URL; do
  [ -n "$URL" ] || continue
  if ! ks_fetch "$TMP/raw" "$URL"; then
    ks_log "keybox_fetch: download failed ($URL)"; continue
  fi
  if ! _decode_valid; then
    ks_log "keybox_fetch: not a keybox ($URL)"; continue
  fi
  NEW=$($SHA < "$TMP/keybox.xml" 2>/dev/null | awk '{print tolower($1)}')
  OLD=""; [ -s "$TEESIM_KEYBOX" ] && OLD=$($SHA < "$TEESIM_KEYBOX" 2>/dev/null | awk '{print tolower($1)}')
  if [ -n "$OLD" ] && [ "$OLD" = "$NEW" ]; then
    ks_log "keybox_fetch: already up to date (via $URL)"
    echo 2 > "$TMP/rc"; break
  fi
  if mv -f "$TMP/keybox.xml" "$TEESIM_KEYBOX" 2>/dev/null; then
    chmod 600 "$TEESIM_KEYBOX" 2>/dev/null
    ks_log "keybox_fetch: keybox updated via $URL ($(wc -c < "$TEESIM_KEYBOX" 2>/dev/null) bytes)"
    echo 0 > "$TMP/rc"; break
  fi
  ks_log "keybox_fetch: install failed ($URL)"
done

RC=$(cat "$TMP/rc" 2>/dev/null)
case "$RC" in
  0) sh "$MODDIR/teesim_config.sh" >/dev/null 2>&1; exit 0 ;;
  2) exit 2 ;;
  *) ks_log "keybox_fetch: all endpoints failed"; exit 1 ;;
esac
