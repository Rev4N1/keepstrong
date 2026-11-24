#!/system/bin/sh
# KeepStrong — configure HMA-OSS (org.frknkrc44.hma_oss) to hide your root /
# module / detector apps from the attestation targets.
#
# This is OPTIONAL and conservative: it only edits an EXISTING HMA-OSS config
# (open the HMA app once, or reboot, so it creates one), it preserves your own
# templates, every other scope entry and the configVersion, and it bails without
# touching the file if the merge can't parse it cleanly. It adds one managed
# blacklist template ("KeepStrong") listing the apps to hide, and applies that
# template to the Play Integrity targets (+ your apps.list). Hide-list is
# overridable in $KS_DIR/hma_hide.list.
#
# Exit: 0 applied / nothing to do | 1 skipped (no HMA / no config / merge failed).

MODDIR=${0%/*}
. "$MODDIR/common.sh"
. "$MODDIR/detect.sh"
ks_init

ks_on manage_hma || { ks_log "hma_sync: manage_hma off, skipping"; exit 0; }
ks_hma_present || { ks_log "hma_sync: HMA-OSS not installed, skipping"; exit 0; }
CFG=$(ks_hma_config) || { ks_log "hma_sync: no HMA config yet — open the HMA app once (or reboot), then re-run"; exit 1; }

_bb=$(ks_busybox)
command -v awk >/dev/null 2>&1 && AWK="awk" || AWK=""
[ -z "$AWK" ] && [ -n "$_bb" ] && AWK="$_bb awk"
[ -n "$AWK" ] || { ks_log "hma_sync: no awk available, skipping"; exit 1; }

TMP=$(mktemp -d 2>/dev/null || { mkdir -p "$KS_DIR/.hma.$$"; echo "$KS_DIR/.hma.$$"; })
trap 'rm -rf "$TMP"' EXIT INT TERM

# Hide-list: the apps HMA should hide from the targets. Default set covers the
# common root managers, Xposed managers and HMA itself; extend in hma_hide.list.
cat > "$TMP/hide" <<'EOF'
# Root managers
com.topjohnwu.magisk
io.github.huskydg.magisk
io.github.vvb2060.magisk
me.weishu.kernelsu
com.rifsxd.ksunext
com.sukisu.ultra
me.bmax.apatch
me.garfieldhan.apatch
# Xposed / LSPosed managers
org.lsposed.manager
de.robv.android.xposed.installer
# HMA-OSS itself
org.frknkrc44.hma_oss
icu.nullptr.hidemyapplist
EOF
if [ -f "$KS_DIR/hma_hide.list" ]; then
  while IFS= read -r _l || [ -n "$_l" ]; do
    _l=$(printf '%s' "$_l" | tr -d ' \t\r'); case "$_l" in ''|'#'*) continue ;; esac
    grep -qxF "$_l" "$TMP/hide" 2>/dev/null || printf '%s\n' "$_l" >> "$TMP/hide"
  done < "$KS_DIR/hma_hide.list"
fi

# Targets: the apps to blind (packages only — HMA scope keys are package names,
# so drop the uid: entries build_target adds for TEESimulator).
# The hidden apps themselves (root managers, HMA) are left out of the scope so
# they are never blinded to each other.
grep -vE '^(#|$)' "$TMP/hide" > "$TMP/hidepk"
sh "$MODDIR/build_target.sh" 2>/dev/null | grep -vE '^uid:' | grep -E '\.' | grep -vxF -f "$TMP/hidepk" > "$TMP/tgt"
[ -s "$TMP/tgt" ] || { ks_log "hma_sync: no targets, skipping"; exit 0; }

# Merge (brace-aware; prints nothing + rc 2 on any parse problem).
if ! $AWK -v cfg="$CFG" -v hide="$TMP/hide" -v tgt="$TMP/tgt" -v tname="KeepStrong" \
     -f "$MODDIR/hma_merge.awk" > "$TMP/merged" 2>/dev/null || [ ! -s "$TMP/merged" ]; then
  ks_log "hma_sync: merge failed — HMA config left untouched"
  exit 1
fi
case "$(head -c1 "$TMP/merged")" in '{') : ;; *) ks_log "hma_sync: merge output not an object — skipping"; exit 1 ;; esac

# No change? leave it (avoids a needless HMA reload).
if cmp -s "$TMP/merged" "$CFG" 2>/dev/null; then
  ks_log "hma_sync: HMA config already current"
  exit 0
fi

# Back up once, then content-replace in place (preserves owner + mode + inode,
# which matters because HMA owns this file under its service uid).
[ -f "$CFG.keepstrong.bak" ] || cp -f "$CFG" "$CFG.keepstrong.bak" 2>/dev/null
if cat "$TMP/merged" > "$CFG" 2>/dev/null; then
  ks_log "hma_sync: HMA config updated ($(grep -c . "$TMP/tgt") targets hidden)"
  exit 0
fi
ks_log "hma_sync: write failed"
exit 1
