#!/bin/bash
# exokyoto_publish.sh — One-shot: new xlsx → pipeline → GitHub push
#
# Usage:
#   ./exokyoto_publish.sh <new-xlsx> [<release-notes>] [<data-version>]
#
# Examples:
#   # most common: data_version is auto-derived from xlsx filename (date stamp)
#   ./exokyoto_publish.sh ExoKyotoDataF20260520_Cleaned_FullPapers_v2.xlsx \
#       "Added 3 new TESS planets"
#
#   # explicit data_version override
#   ./exokyoto_publish.sh new.xlsx "tweak A" 2026.05.20-stable
#
# What this script does (in order):
#   1. python3 exokyoto_update_pipeline.py
#        - copies xlsx → internal/latest/ (working copy)
#        - queries NASA Exoplanet Archive for any *new* planets (vs internal/latest)
#        - queries ADS for paper references for any *new* planets
#        - runs duplicate sanity check
#        - xlsx → CSV → bin (EKDBIN1)
#        - rotates: data/past/* → internal/historical/data/
#                   data/latest/ExoKyotoDataF.bin → data/past/<stamp>
#        - installs new bin → data/latest/
#        - writes ExoKyotoData/version.json
#   2. ./exokyoto_github_push.sh
#        - commits + pushes the changed files to GitHub via SSH
#        - default commit message:  "data: <data_version> — <notes>"

set -e

if [ $# -lt 1 ]; then
    sed -n '2,/^set -e/p' "$0" | sed 's/^# \?//' | head -30
    exit 2
fi

XLSX="$1"
NOTES="${2:-}"
DV="${3:-}"

GAIA_DIR="/Users/yosukeair3/unix/gaia"
cd "$GAIA_DIR"

# Auto-derive data_version from xlsx filename if not given:
#   ExoKyotoDataF20260520N_Cleaned_FullPapers_v2.xlsx  →  2026.05.20N-preview
if [ -z "$DV" ]; then
    BASE=$(basename "$XLSX" .xlsx)
    # Extract leading "YYYYMMDD<letter?>" from ExoKyotoDataF<stamp>_*
    STAMP=$(echo "$BASE" | sed -E 's/^ExoKyotoDataF([0-9]{4})([0-9]{2})([0-9]{2})([A-Za-z]?).*$/\1.\2.\3\4/')
    if [ "$STAMP" = "$BASE" ]; then
        STAMP=$(date +%Y.%m.%d)
    fi
    DV="${STAMP}-preview"
fi

echo "================================================================"
echo "  ExoKyoto publish"
echo "  xlsx          : $XLSX"
echo "  data_version  : $DV"
echo "  release notes : ${NOTES:-(auto from added planets)}"
echo "================================================================"
echo ""

# Step 1: pipeline
PIPELINE_ARGS=(
    --in-xlsx "$XLSX"
    --data-version "$DV"
)
[ -n "$NOTES" ] && PIPELINE_ARGS+=(--release-notes "$NOTES")
[ -n "$ADS_TOKEN" ] || echo "WARNING: ADS_TOKEN not set — paper lookup for new planets will be skipped"

python3 exokyoto_update_pipeline.py "${PIPELINE_ARGS[@]}"

echo ""
echo "================================================================"
echo "  Pushing to GitHub"
echo "================================================================"

# Step 2: git push
./exokyoto_github_push.sh

echo ""
echo "================================================================"
echo "  Done."
echo "================================================================"
echo "Verify clients pick it up:"
echo "  rm -f ~/Library/Logs/ExoKyoto/update_check.log"
echo "  open /Users/yosukeair3/unix/ExoKyoto3D_AppleSilicon_20260519/ExoKyoto3D.app"
echo "  sleep 10 && cat ~/Library/Logs/ExoKyoto/update_check.log"
