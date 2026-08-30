#!/bin/bash
# exokyoto_github_push.sh — Push ExoKyoto3D-Data to GitHub via SSH
#
# Sync the local working tree at ExoKyotoData/ to
# https://github.com/YosukeAlex/ExoKyoto3D-Data
# without ChatGPT, without the GitHub web UI, and without gh CLI.
#
# Auth: uses your existing SSH key (~/.ssh/id_ed25519).
# Already verified to GitHub (`ssh -T git@github.com` → Hi YosukeAlex!).
#
# Usage:
#   ./exokyoto_github_push.sh                       # commit + push current state
#   ./exokyoto_github_push.sh -m "custom message"   # override commit message
#   ./exokyoto_github_push.sh --init                # one-time setup: bind local
#                                                     ExoKyotoData/ to the GitHub
#                                                     clone, then push
#   ./exokyoto_github_push.sh --dry-run             # show what would happen
#   ./exokyoto_github_push.sh --status              # local vs remote status
#
# Default commit message:  "data: <data_version from version.json>"

set -e

REPO_DIR="/Users/yosukeair3/unix/gaia/ExoKyotoData"
REMOTE="git@github.com:YosukeAlex/ExoKyoto3D-Data.git"
DEFAULT_BRANCH="main"

INIT=0
DRY_RUN=0
SHOW_STATUS=0
MESSAGE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --init)     INIT=1; shift ;;
        --dry-run)  DRY_RUN=1; shift ;;
        --status)   SHOW_STATUS=1; shift ;;
        -m|--message) MESSAGE="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,/^set -e/p' "$0" | sed 's/^# \?//' | head -25
            exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

# Sanity: repo dir exists
if [ ! -d "$REPO_DIR" ]; then
    echo "ERROR: $REPO_DIR does not exist" >&2
    exit 1
fi

# --status
if [ $SHOW_STATUS -eq 1 ]; then
    cd "$REPO_DIR"
    if [ ! -d .git ]; then
        echo "Not a git repo. Run with --init first."
        exit 0
    fi
    git fetch origin "$DEFAULT_BRANCH" 2>/dev/null || true
    echo "=== local branch ==="
    git status -sb
    echo ""
    echo "=== unpushed commits ==="
    git log --oneline @{u}.. 2>/dev/null || echo "(no upstream tracked)"
    echo ""
    echo "=== last 3 remote commits ==="
    git log --oneline origin/$DEFAULT_BRANCH 2>/dev/null | head -3
    exit 0
fi

# --init: bootstrap repo
if [ $INIT -eq 1 ] || [ ! -d "$REPO_DIR/.git" ]; then
    echo "=== one-time setup: cloning $REMOTE into $REPO_DIR ==="
    BACKUP="/tmp/exokyoto-data-backup-$$"
    mkdir -p "$BACKUP"
    # Preserve local files (the ones we already produced via the pipeline)
    (cd "$REPO_DIR" && cp -R . "$BACKUP/")
    if [ $DRY_RUN -eq 1 ]; then
        echo "  [dry-run] would: rm -rf $REPO_DIR && git clone $REMOTE $REPO_DIR"
        echo "  [dry-run] would: restore local files from $BACKUP/"
        rm -rf "$BACKUP"
        exit 0
    fi
    rm -rf "$REPO_DIR"
    git clone "$REMOTE" "$REPO_DIR"
    cd "$REPO_DIR"
    # Restore local files OVER the fresh clone. rsync handles weird filenames
    # (Word lock "~$*", spaces, etc.) and skips the cloned .git directory.
    rsync -a --delete-excluded \
        --exclude='.git/' \
        --exclude='.DS_Store' \
        --exclude='~$*' \
        --exclude='*.tmp' \
        "$BACKUP/" "$REPO_DIR/"
    rm -rf "$BACKUP"
    echo "  ✓ initialized + local files restored (via rsync)"
fi

# Normal flow: commit + push
cd "$REPO_DIR"

# Determine commit message
if [ -z "$MESSAGE" ]; then
    if [ -f version.json ]; then
        DV=$(python3 -c "import json; print(json.load(open('version.json'))['data_version'])" 2>/dev/null || true)
        NOTES=$(python3 -c "import json; print(json.load(open('version.json')).get('notes',''))" 2>/dev/null || true)
        MESSAGE="data: ${DV:-update}"
        [ -n "$NOTES" ] && MESSAGE="$MESSAGE — $NOTES"
    else
        MESSAGE="data update"
    fi
fi

# Stage
git add -A

# Anything to commit?
if git diff --cached --quiet; then
    echo "Nothing changed since last commit. Nothing to push."
    exit 0
fi

echo "=== about to commit ==="
git status -s
echo ""
echo "commit message: $MESSAGE"
echo ""

if [ $DRY_RUN -eq 1 ]; then
    echo "[dry-run] would: git commit -m \"$MESSAGE\" && git push origin $DEFAULT_BRANCH"
    exit 0
fi

git commit -m "$MESSAGE"
git push origin "$DEFAULT_BRANCH"
echo ""
echo "✓ pushed to $REMOTE  branch=$DEFAULT_BRANCH"
echo "  commit: $MESSAGE"
echo ""
echo "Live URLs:"
echo "  https://github.com/YosukeAlex/ExoKyoto3D-Data"
echo "  https://raw.githubusercontent.com/YosukeAlex/ExoKyoto3D-Data/main/version.json"
echo "  https://raw.githubusercontent.com/YosukeAlex/ExoKyoto3D-Data/main/data/latest/ExoKyotoDataF.bin"
