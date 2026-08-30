#!/bin/bash
# install_and_push_20260602.sh — Final push trigger for the 2026-06-02 重大データ更新
#
# Run ONLY when:
#   (1) TESSAll upstream flare data final fix has landed (CSV no longer mutating)
#   (2) optionally re-run apply_sempac_master_restoration_20260602.py one more time
#       to catch any final E_max updates
#   (3) user has explicitly approved push
#
# Steps:
#   A) Archive current published bin → data/past/
#   B) Install staged bin → data/latest/
#   C) Update version.json with finalized timestamp
#   D) git commit + push via exokyoto_github_push.sh
#   E) ALEX_MAIN backup
#
# DO NOT RUN unattended.

set -euo pipefail

GAIA=/Users/yosukeair3/unix/gaia
EKDATA=$GAIA/ExoKyotoData
STAGE=$EKDATA/internal/latest
LIVE=$EKDATA/data/latest
PAST=$EKDATA/data/past

NOW_JST=$(TZ=Asia/Tokyo date '+%Y.%m.%d-%H%M-JST')
NOW_ISO_JST=$(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S%z' | sed 's/\(..\)$/:\1/')
NOW_ISO_UTC=$(TZ=UTC date '+%Y-%m-%d %H:%M:%SZ')
NOW_DATE=$(TZ=Asia/Tokyo date '+%Y-%m-%d')
NOW_TIME_JST=$(TZ=Asia/Tokyo date '+%H:%M:%S')
ARCHIVE_STAMP=$(TZ=Asia/Tokyo date '+%Y%m%d')01

echo "=== Step A: Archive current published bin ==="
ARCHIVE_NAME="ExoKyotoDataF${ARCHIVE_STAMP}.bin"
if [ -f "$LIVE/ExoKyotoDataF.bin" ]; then
    cp "$LIVE/ExoKyotoDataF.bin" "$PAST/$ARCHIVE_NAME"
    echo "  archived: $PAST/$ARCHIVE_NAME"
fi

echo "=== Step B: Install staged bin → data/latest/ ==="
cp "$STAGE/ExoKyotoDataF.bin" "$LIVE/ExoKyotoDataF.bin"
ls -l "$LIVE/ExoKyotoDataF.bin"
md5sum "$LIVE/ExoKyotoDataF.bin" 2>/dev/null || md5 "$LIVE/ExoKyotoDataF.bin"

echo "=== Step C: Update version.json ==="
python3 - <<PY
import json, hashlib
from pathlib import Path
vj = Path("$EKDATA/version.json")
cur = json.loads(vj.read_text())
bin_p = Path("$LIVE/ExoKyotoDataF.bin")
md5 = hashlib.md5(bin_p.read_bytes()).hexdigest()
cur['data_version']        = "$NOW_JST"
cur['release_date']        = "$NOW_DATE"
cur['release_time_jst']    = "$NOW_TIME_JST"
cur['release_datetime_jst']= "$NOW_ISO_JST"
cur['release_datetime_utc']= "$NOW_ISO_UTC"
cur['notes']               = ("NASA以来の重大データ更新: 5/26 SEMPAC + 6/2 Kepler-mission resolutions 全 53 stars "
                              "(SEMPAC 123 planet rows: FULL_RERUN 93 / RESOLVED_KEPLER_MISSION 19 / FLAG_PROT_ALIAS 11), "
                              "paleo (ASol系11行) を別配布へ移行, 重複6件解消, "
                              "新規6 host追加 (KMT-2021-BLG-0690 b / TOI-7394 b / 41 Her Ab / HD 85512 b / Kapteyn's b/c). "
                              "6471 rows × 158 cols.")
cur['md5_bin']             = md5
cur['bin_size']            = bin_p.stat().st_size
vj.write_text(json.dumps(cur, indent=2, ensure_ascii=False))
print(f"version.json updated: data_version={cur['data_version']}, md5={md5}")
PY

echo "=== Step D: Git commit + push ==="
cd "$EKDATA"
git status -s
echo "---"
bash "$EKDATA/exokyoto_github_push.sh"

echo "=== Step E: ALEX_MAIN backup ==="
ALEX_BACKUP=/Volumes/ALEX_MAIN/ExoKyotoBC/ExoKyotoAll/ExoKyotoDataF_20260602
if [ -d /Volumes/ALEX_MAIN ]; then
    mkdir -p "$ALEX_BACKUP"
    cp "$GAIA/ExoKyotoDataF20260602.xlsx" "$ALEX_BACKUP/"
    cp "$GAIA/ExoKyotoDataF20260521.xlsx.bak_before_20260602" "$ALEX_BACKUP/" 2>/dev/null || true
    cp "$LIVE/ExoKyotoDataF.bin" "$ALEX_BACKUP/"
    cp "$STAGE/ExoKyotoDataF.csv" "$ALEX_BACKUP/"
    cp "$EKDATA/version.json" "$ALEX_BACKUP/"
    cp "$GAIA/DATA_UPDATE_PROTOCOL_20260602.md" "$ALEX_BACKUP/"
    cp "$GAIA/apply_sempac_master_restoration_20260602.py" "$ALEX_BACKUP/"
    cp "$GAIA/TESS/E_max_FINAL_20260526.csv" "$ALEX_BACKUP/"
    cp "$GAIA/audit_sempac_vs_master_20260602.csv" "$ALEX_BACKUP/" 2>/dev/null || true
    echo "  ALEX_MAIN backup: $ALEX_BACKUP/"
    ls -l "$ALEX_BACKUP/"
else
    echo "  ALEX_MAIN not mounted — skip backup, run manually later"
fi

echo "=== DONE ==="
