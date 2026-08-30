# ExoKyoto3D-Data — GitHub push (script-only, no web UI / no ChatGPT)

This is the single-command path to publish a new `ExoKyotoDataF.bin` to
`https://github.com/YosukeAlex/ExoKyoto3D-Data`. No GitHub web UI, no `gh`
CLI, no Personal Access Tokens — only your existing SSH key.

---

## 1. One-time setup (about 30 seconds)

Confirm SSH already works (you've done this once before, so this should just print "Hi YosukeAlex"):

```bash
ssh -T git@github.com
# expected: Hi YosukeAlex! You've successfully authenticated, ...
```

Then bind the local working tree to the GitHub repo:

```bash
cd /Users/yosukeair3/unix/gaia
./exokyoto_github_push.sh --init
```

What `--init` does:
1. Backs up the current contents of `gaia/ExoKyotoData/` to
   `/tmp/exokyoto-data-backup-<pid>/`.
2. `rm -rf gaia/ExoKyotoData` then
   `git clone git@github.com:YosukeAlex/ExoKyoto3D-Data.git gaia/ExoKyotoData`.
3. **`rsync`** the backed-up local files on top of the clone (so your pipeline
   outputs are preserved and become the next commit). Excluded from the rsync:
   `.git/` (just cloned, don't clobber), `.DS_Store`, `~$*` (Word lock files
   that appear when you have the .docx open), `*.tmp`.

After this, `gaia/ExoKyotoData/` is a normal git clone bound to origin =
`git@github.com:YosukeAlex/ExoKyoto3D-Data.git`, branch = `main`.

You only need `--init` once.

> **If `--init` ever errors in the middle**, the backup is preserved at
> `/tmp/exokyoto-data-backup-<pid>/` for recovery. Re-run with `rsync` or
> `cp -R` to restore manually.

---

## 2. Normal release flow (every time the data changes)

```bash
cd /Users/yosukeair3/unix/gaia

# Step 1 — regenerate bin + version.json from a new xlsx
python3 exokyoto_update_pipeline.py \
    --in-xlsx ExoKyotoDataF<DATE><LETTER>_Cleaned_FullPapers_v2.xlsx \
    --data-version "<YYYY.MM.DD<letter>-<channel>>" \
    --release-notes "<short release note>"

# Step 2 — push to GitHub
./exokyoto_github_push.sh
```

The script auto-derives the commit message from `version.json`
(`data: <data_version> — <notes>`). Override with `-m "custom"` if needed.

---

## 3. Useful flags

| Command | Purpose |
|---|---|
| `./exokyoto_github_push.sh` | Standard commit + push |
| `./exokyoto_github_push.sh -m "msg"` | Custom commit message |
| `./exokyoto_github_push.sh --status` | Show local vs remote diff, unpushed commits |
| `./exokyoto_github_push.sh --dry-run` | Print what would happen, don't push |
| `./exokyoto_github_push.sh --init` | Bind local dir to GitHub clone (once only) |
| `./exokyoto_github_push.sh --help` | Inline help text |

---

## 4. What actually gets pushed

The `.gitignore` in `ExoKyotoData/` excludes:
- `internal/` — working xlsx/csv/report files (3-12 MB each, not for distribution)
- `*.csv`, `*.xlsx`, `~$*`, `.DS_Store`

So a normal push touches only:
- `version.json` — the small manifest the apps fetch
- `data/latest/ExoKyotoDataF.bin` — the new bin (~12 MB)
- `data/past/ExoKyotoDataF<YYYYMMDDNN>.bin` — the archived previous bin (~12 MB)
- (occasionally) `README.md`, `UPDATE_PIPELINE.md`, `GITHUB_PUSH.md`

The repo will accumulate `data/past/` history over time — that's intentional
(easy rollback by editing `version.json:binary_url`).

---

## 5. Live URLs (post-push)

| Resource | URL |
|---|---|
| Repo home | https://github.com/YosukeAlex/ExoKyoto3D-Data |
| `version.json` (raw) | https://raw.githubusercontent.com/YosukeAlex/ExoKyoto3D-Data/main/version.json |
| Current bin (raw)    | https://raw.githubusercontent.com/YosukeAlex/ExoKyoto3D-Data/main/data/latest/ExoKyotoDataF.bin |

Every running ExoKyoto3D / 4D / 4Dalpha app hits the first URL on startup and
detects the new `data_version` automatically.

---

## 6. Auth model — web login is irrelevant; SSH key is what matters

**Common misconception**: "I logged out of github.com, will `git push` stop working?"
→ No. `git push` over `git@github.com:…` ignores your browser cookies entirely.
What it cares about is:

1. `~/.ssh/id_ed25519` (your private key) exists on this machine.
2. The matching `id_ed25519.pub` (public key) is registered with GitHub under
   your account `YosukeAlex`.

Quick verification (web-login irrelevant):

```bash
ssh -T git@github.com
# expected: Hi YosukeAlex! You've successfully authenticated, ...
```

If that prints `Hi YosukeAlex!` then push will work — log out of github.com if
you want, kill all browsers, change networks; it makes no difference.

### When does auth break, and how to fix

| Situation | Symptom | Fix |
|---|---|---|
| You logged out of github.com in the browser | nothing — push still works | (no action needed) |
| You're on a different network / coffee shop | nothing — TCP+SSH works through any wifi | (no action needed) |
| `Permission denied (publickey)` on push | ssh-agent stopped, or key permissions wrong | `chmod 600 ~/.ssh/id_ed25519` then `eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519` |
| `id_ed25519` file disappeared | full re-keying needed | see § Re-keying below |
| You revoked the SSH key on GitHub | `Permission denied (publickey)` | re-add `~/.ssh/id_ed25519.pub` content under https://github.com/settings/keys |
| Repo was made private and your key is on a different account | `Repository not found` | use the right key, or add this key to the right account |

### Re-keying from scratch (if `id_ed25519` is lost)

```bash
# 1) Generate a new key
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "yosukeair3@<machine>"
# 2) Print the public key and paste into GitHub web UI:
cat ~/.ssh/id_ed25519.pub
#    → https://github.com/settings/keys → "New SSH key"
# 3) Verify
ssh -T git@github.com
# Hi YosukeAlex! ...
```

(This is the only flow that requires a web login — to register the new public
key. After that, push works script-only forever.)

---

## 6a. What the `exokyoto_github_push.sh` script actually does (line by line)

To answer "what is this script doing under the hood":

```bash
#!/bin/bash
set -e                    # abort on any error (no silent failures)

REPO_DIR="/Users/yosukeair3/unix/gaia/ExoKyotoData"
REMOTE="git@github.com:YosukeAlex/ExoKyoto3D-Data.git"
DEFAULT_BRANCH="main"
```

These three lines are the only "configuration". Everything else operates on
these paths.

### Phase A — argument parsing

The script accepts these flags (parsed by the `while` loop):

| Flag | Action |
|---|---|
| `--init` | force the one-time setup path even if `.git` already exists |
| `--dry-run` | print what would be done, change nothing |
| `--status` | only show local vs remote diff, no commit |
| `-m "msg"` / `--message "msg"` | override the auto-generated commit message |
| `-h` / `--help` | print the comment block at the top of the script |

### Phase B — `--status` (read-only inspection)

```bash
cd "$REPO_DIR"
git fetch origin main           # refresh knowledge of remote (read-only)
git status -sb                  # local branch + uncommitted files
git log --oneline @{u}..        # commits I have but remote doesn't
git log --oneline origin/main | head -3   # last 3 remote commits
```

Pure diagnostic. Does not push.

### Phase C — `--init` (one-time setup, or any time `.git` is missing)

```bash
BACKUP=/tmp/exokyoto-data-backup-<pid>   # unique per-run path
mkdir -p "$BACKUP"
(cd "$REPO_DIR" && cp -R . "$BACKUP/")   # snapshot current contents
rm -rf "$REPO_DIR"                       # wipe target
git clone <REMOTE> "$REPO_DIR"           # fresh clone from GitHub
rsync -a --exclude='.git/' \
         --exclude='.DS_Store' \
         --exclude='~$*' \                # Word lock files (skipped!)
         --exclude='*.tmp' \
         "$BACKUP/" "$REPO_DIR/"          # put our local files back on top
rm -rf "$BACKUP"                          # cleanup temp
```

Net effect: `ExoKyotoData/` is now a git working copy bound to GitHub origin,
but the *contents* are our local files (new bin, new version.json, etc.)
ready to commit as the next push.

The rsync `--exclude='~$*'` is what fixes the earlier
`cp: ~.docx: No such file or directory` error: Word creates these lock files
when a .docx is open, and they don't belong in the repo.

### Phase D — commit message resolution

```bash
if [ -z "$MESSAGE" ]; then
    DV=<read version.json data_version field>
    NOTES=<read version.json notes field>
    MESSAGE="data: $DV — $NOTES"
fi
```

So `data: 2026.05.19N-preview — Added KMT-2021-BLG-0424 b and TOI-7716 b
(2 new entries)` is auto-derived from version.json. Override with `-m "..."`.

### Phase E — stage, check, commit, push

```bash
git add -A                       # stage every change (new/modified/deleted)
if git diff --cached --quiet; then
    echo "Nothing changed since last commit. Nothing to push."
    exit 0
fi
git status -s                    # show what's about to be committed
git commit -m "$MESSAGE"
git push origin main             # uses SSH key — no password, no PAT
```

The push uses the URL `git@github.com:YosukeAlex/ExoKyoto3D-Data.git`. Git's
SSH transport reads `~/.ssh/id_ed25519` (no agent required on macOS) and
authenticates to GitHub. **Web login state is never consulted.**

### Phase F — confirmation output

After a successful push, the script prints the three live URLs (repo home,
raw version.json, raw bin) so you can `curl` to verify or eyeball in the
browser.

---

---

## 7. Recovery: undo the last push

```bash
cd /Users/yosukeair3/unix/gaia/ExoKyotoData

# locally
git reset --hard HEAD~1

# then force-push (only do this if no one else has pulled yet)
git push --force-with-lease
```

Alternatively, just publish a new commit that restores the previous bin from
`data/past/`:

```bash
cp data/past/ExoKyotoDataF2026051901.bin data/latest/ExoKyotoDataF.bin
# edit version.json's data_version field manually
./exokyoto_github_push.sh -m "data: rollback to 2026.05.19-preview"
```

---

## 8. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Permission denied (publickey)` | SSH key not loaded | `ssh-add ~/.ssh/id_ed25519` |
| `error: src refspec main does not match any` | First push of brand-new clone | Already handled by `--init`; if you skipped, run `git push -u origin main` once |
| `nothing changed since last commit` | Pipeline produced identical bin | OK, nothing to do |
| `xargs: command line cannot be assembled, too long` / `cp: ~.docx: No such file or directory` | Old (pre-rsync) script; you have Word open on a .docx in the repo | Update to the current script (uses `rsync`). Or close all Word files in `ExoKyotoData/` and retry. |
| `! [rejected] main -> main (fetch first)` | Someone else pushed | `cd ExoKyotoData && git pull --rebase && ./exokyoto_github_push.sh` |
| `fatal: Authentication failed` | SSH agent stopped | Restart agent: `eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519` |

---

## 9. Verification after push

```bash
# 1) version.json on GitHub
curl -s https://raw.githubusercontent.com/YosukeAlex/ExoKyoto3D-Data/main/version.json | head

# 2) bin size matches what you pushed
curl -sI https://raw.githubusercontent.com/YosukeAlex/ExoKyoto3D-Data/main/data/latest/ExoKyotoDataF.bin | grep content-length

# 3) launch a deployed app and watch the log
rm -f ~/Library/Logs/ExoKyoto/update_check.log
open /Users/yosukeair3/unix/ExoKyoto3D_AppleSilicon_20260519/ExoKyoto3D.app
sleep 10
cat ~/Library/Logs/ExoKyoto/update_check.log
# Expected: "UPDATE AVAILABLE: 2026.05.19-preview -> 2026.05.19N-preview"
```
