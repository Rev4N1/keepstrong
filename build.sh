#!/usr/bin/env bash
# KeepStrong — package the flashable module zip from module/.
# Usage: ./build.sh            -> keepstrong-<version>.zip
#        ./build.sh --out foo.zip
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT/module"

VER=$(sed -n 's/^version=//p' module.prop | head -1)
OUT="$ROOT/keepstrong-${VER}.zip"
[ "${1:-}" = "--out" ] && OUT="$2"
rm -f "$OUT"

if command -v zip >/dev/null 2>&1; then
  zip -r -X "$OUT" . -x '*.DS_Store' >/dev/null
else
  # Fallback: Python zip with exec bits on scripts + update-binary.
  python - "$OUT" <<'PY'
import os,sys,zipfile,stat
out=sys.argv[1]
with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as z:
    for root,_,files in os.walk('.'):
        for f in files:
            p=os.path.join(root,f); arc=os.path.relpath(p,'.').replace(os.sep,'/')
            if arc.endswith('.DS_Store'): continue
            zi=zipfile.ZipInfo.from_file(p,arc); zi.compress_type=zipfile.ZIP_DEFLATED
            exe = arc.endswith('.sh') or arc.endswith('update-binary')
            zi.external_attr=((0o755 if exe else 0o644)|stat.S_IFREG)<<16
            with open(p,'rb') as fh: z.writestr(zi,fh.read())
PY
fi
echo "built: $OUT ($(wc -c < "$OUT") bytes)"
