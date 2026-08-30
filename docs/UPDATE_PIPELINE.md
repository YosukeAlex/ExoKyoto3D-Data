# ExoKyotoDataF Update Pipeline (routine version)

End-to-end **single-command** workflow for: **edit xlsx → distribute new bin to all
running apps via GitHub**, with rotation policy that keeps the public repo slim.

This document is the single source of truth. All step-by-step actions, scripts,
file layouts, and version semantics are described here. When the process changes,
update this file *and* the three scripts together
(`exokyoto_update_pipeline.py`, `exokyoto_publish.sh`, `exokyoto_github_push.sh`).

---

## TL;DR — the one-line routine

```bash
export ADS_TOKEN=<your-ads-token>          # one-time per shell session
cd /Users/yosukeair3/unix/gaia
./exokyoto_publish.sh ExoKyotoDataF20260520_Cleaned_FullPapers_v2.xlsx \
    "Added 3 new TESS planets"
```

The `data_version` is **auto-generated from the current Japan-Standard time**
(`YYYY.MM.DD-HHMM-JST`, e.g. `2026.05.19-1850-JST`) so every push gets a
unique stamp even within the same day. Override with
`--data-version "<your-string>"` if you want a custom label
(e.g. `2026.05.20-gsfc-release`).

That single command:
1. Copies the xlsx to `ExoKyotoData/internal/latest/` (Excel-lock safe)
2. Diffs vs the previous master xlsx → list of added planets
3. For each added planet: query NASA Exoplanet Archive → fill NASA cols
4. For each added planet (whose Title is empty): query ADS → fill paper info
5. Run duplicate sanity check
6. Generate new CSV + bin (EKDBIN1, ~12 MB)
7. **Rotation** (keeps the public `data/` slim):
   - Anything currently in `ExoKyotoData/data/past/` → `internal/historical/data/`
   - Current `data/latest/ExoKyotoDataF.bin` → `data/past/ExoKyotoDataF<YYYYMMDDNN>.bin`
   - New bin → `data/latest/ExoKyotoDataF.bin`
8. Rewrite `ExoKyotoData/version.json` with the new `data_version` + notes
9. `git commit && git push` to `github.com/YosukeAlex/ExoKyoto3D-Data` via SSH

Every running ExoKyoto3D / 4D / 4Dalpha app will pick up the change on its next
startup (`update_check.cpp` polls `version.json` and shows a dialog if
`data_version` mismatches).

---

## Two-step alternative (when you want to inspect between steps)

```bash
cd /Users/yosukeair3/unix/gaia

# Step 1 — only generate artifacts (no push)
python3 exokyoto_update_pipeline.py \
    --in-xlsx ExoKyotoDataF20260520_Cleaned_FullPapers_v2.xlsx \
    --data-version "2026.05.20-preview" \
    --release-notes "Added 3 new TESS planets"

# Inspect: ExoKyotoData/data/latest/, version.json, etc.

# Step 2 — push
./exokyoto_github_push.sh
```

## Rotation policy (why two "old bin" locations)

| Where | What | When |
|---|---|---|
| `data/latest/ExoKyotoDataF.bin`            | The current canonical bin (one file) | Always exactly 1 file |
| `data/past/ExoKyotoDataF<YYYYMMDDNN>.bin`  | **The immediately previous** bin only | Always exactly 0 or 1 file |
| `internal/historical/data/ExoKyotoDataF<YYYYMMDDNN>.bin` | Everything older | Accumulates forever |

The rationale: the GitHub repo (`ExoKyotoData/data/`) ships at most ~24 MB
(latest + previous). Full history is preserved locally in `internal/historical/`
but **never pushed** (excluded by `.gitignore`).

Date-stamp format: `YYYYMMDDNN` (e.g. `2026051901`). `NN` = 01 by default,
increments to 02, 03 on multiple updates in the same day. Override with
`--archive-stamp 2026052003` if needed.

To roll back, see § Rollback below.

Once pushed, every distributed ExoKyoto3D detects the new `data_version` on next
launch and downloads `data/latest/ExoKyotoDataF.bin` automatically (see
`update_check.cpp` in the app source).

---

## File layout

```
gaia/
├── exokyoto_update_pipeline.py    ← THIS pipeline
├── UPDATE_PIPELINE.md             ← THIS doc
├── version.json                   ← generated, copy → GitHub repo root
└── ExoKyotoData/
    ├── data/                       (binary distribution)
    │   ├── latest/
    │   │   └── ExoKyotoDataF.bin
    │   └── past/
    │       └── ExoKyotoDataF<YYYYMMDDNN>.bin  ← auto-archived
    └── internal/                   (working files: xlsx, csv, reports)
        ├── latest/
        │   ├── ExoKyotoDataF.bin
        │   ├── ExoKyotoDataF.csv
        │   ├── ExoKyotoDataF<DATE>_Cleaned_FullPapers_v2.xlsx
        │   └── *_NasaTransitCoverage.xlsx, *_ChangeLog.xlsx, ...
        └── historical/             (older snapshots, manually populated)
```

### Why two `latest/` folders
- `data/latest/` ships to NASA/GSFC and to GitHub raw — **bin only**.
- `internal/latest/` is the working source-of-truth: xlsx + csv + bin + sidecar
  reports. Keeps the human-readable artifacts together with the binary.

---

## version.json schema (on GitHub)

```json
{
  "project": "ExoKyoto3D",
  "repository": "ExoKyoto3D-Data",
  "data_version":         "2026.05.19-1850-JST",
  "release_date":         "2026-05-19",
  "release_time_jst":     "18:50:21",
  "release_datetime_jst": "2026-05-19 18:50:21+09:00",
  "release_datetime_utc": "2026-05-19 09:50:21Z",
  "status": "Active",
  "data_file": "ExoKyotoDataF.bin",
  "data_path": "data/latest/ExoKyotoDataF.bin",
  "binary_url": "https://raw.githubusercontent.com/YosukeAlex/ExoKyoto3D-Data/main/data/latest/ExoKyotoDataF.bin",
  "notes": "Added KMT-2021-BLG-0424 b and TOI-7716 b"
}
```

| Field | Purpose |
|---|---|
| `data_version`         | The string compared client-side. Auto-generated as `YYYY.MM.DD-HHMM-JST` — **changes every minute**, so identity == time of release. |
| `release_date`         | Human display (date) |
| `release_time_jst`     | Human display (time, JST) |
| `release_datetime_jst` | Full JST stamp for sorting / change-log |
| `release_datetime_utc` | UTC equivalent (for global tracking) |
| `binary_url`           | Where the bin lives. Can point to GitHub raw, NASA/GSFC mirror, etc. |
| `notes`                | Shown in the in-app update dialog |
| `status`               | Free-form (`Initial`, `Active`, `Frozen`, ...) |

### Version-stamp convention (current)

Auto: **`YYYY.MM.DD-HHMM-JST`** — derived from the maintainer machine's local
clock (which is JST). Examples:
- `2026.05.19-1845-JST`
- `2026.05.19-1851-JST`
- `2026.05.20-0930-JST`

The maintainer never has to think about uniqueness — the minute resolution
guarantees no collision across same-day pushes.

Override only when you want a human-meaningful label (e.g. shipping
milestone):
```bash
./exokyoto_publish.sh new.xlsx "GSFC release" --data-version "2026.05.20-gsfc-stable"
```

Comparison is **strict string equality** on the client side — any change to
`data_version` triggers an update prompt. Direction (newer/older) doesn't
matter; the server is the source of truth.

### Client-side state: the sidecar file

When the app applies a download, it writes
`csvin/ExoKyotoDataF.bin.version` (a one-line text file) with the new
`data_version` string. Next launch reads this sidecar first; if absent, falls
back to the compile-time stamp `EXOKYOTO_DATA_VERSION`.

This is what stops the endless update loop after a download — the compile-time
stamp inside the binary is immutable, so without the sidecar every restart
would re-trigger "UPDATE AVAILABLE".

The sidecar can be deleted to force re-download on next launch (useful for
testing or recovery).

---

## Step-by-step (the pipeline internals)

### Step 1 — Diff vs previous

Auto-detects previous xlsx from `ExoKyotoData/internal/latest/`. Compares the
`name` column (col 1) to compute:

- **Added**: planets in new but not previous → drive NASA + ADS lookups
- **Removed**: planets dropped → noted for the changelog

If you didn't add any planets (just edited existing ones), Add/Remove are both
empty and steps 2-3 are no-ops.

### Step 2 — NASA Exoplanet Archive enrichment

For each added planet, query `pscomppars` (NASA TAP service, public) via:

```sql
SELECT pl_name, hostname, discoverymethod, disc_year, disc_facility,
       pl_orbper, pl_rade, pl_radj, pl_masse, pl_massj,
       pl_tranmid, pl_trandep, pl_trandur,
       pl_orbsmax, pl_orbeccen, pl_orbincl,
       st_teff, st_rad, st_mass, sy_dist, ra, dec, disc_refname
FROM pscomppars WHERE pl_name = '<planet>'
```

Hits are mapped into the NASA-zone columns (120-153) of the xlsx:
`nasa_pl_name`, `nasa_hostname`, `nasa_discoverymethod`, …

Misses are logged. The row is still kept (with EU-side data only).

**Skip with `--skip-nasa`** if you've already manually filled NASA cols.

### Step 3 — ADS paper lookup

For each added planet (whose Title col is still blank), query
`api.adsabs.harvard.edu/v1/search/query` with strategies in order:

1. `abs:"<planet>" abs:"<host>"`
2. `abs:"<planet>"`
3. `full:"<planet>"`

Earliest-year result (likely discovery paper) is taken. Fields `bibcode`,
`title`, `author`, `abstract`, `year`, `pub` are mapped into `Title`,
`Authors` (formatted as "Surname, F.M. et al."), `Journal` (`pub (year)`),
`URL` (ADS abstract link), `Abstract`.

Requires `ADS_TOKEN` env var or `--ads-token`. **Skip with `--skip-ads`** if
already filled.

### Step 4 — Duplicate check

Delegates to existing `check_exokyotodataf_duplicates.py`. Prints summary; does
not auto-merge. **Skip with `--skip-dedup`**.

### Step 5-6 — xlsx → CSV → bin

- xlsx → CSV: openpyxl streaming read, csv writer, UTF-8
- CSV → bin: `EKDBIN1` format (magic + version + lineCount + per-line length-prefixed UTF-8)

bin lands in `internal/latest/` first, then copied to `data/latest/`.

### Step 7 — Archive old bin

Before overwriting `data/latest/ExoKyotoDataF.bin`, current file is moved to
`data/past/ExoKyotoDataF<YYYYMMDDNN>.bin` (e.g. `ExoKyotoDataF2026051901.bin`).
Suffix `01` increments to `02`, `03` if multiple updates happen on the same day.

### Step 8 — version.json

Written to `gaia/version.json`. You manually copy this into the GitHub repo
clone, along with the new bin, then `git push`.

---

## Explicit logic (server + client)

### Server-side (what the maintainer does, automated by the pipeline)

```
INPUT  : new_xlsx (the edited master xlsx)
STATE  : ExoKyotoData/{data,internal,version.json}

1. prev_xlsx ← newest ExoKyotoData/internal/latest/*FullPapers*.xlsx
              (excluding *_NasaTransitCoverage*, *_ChangeLog*, *_Report* sidecars)
2. added, removed ← diff(new_xlsx, prev_xlsx) on column "name"
3. FOR each planet in added:
       hit ← NASA pscomppars[pl_name = planet]
       IF hit: write hit fields into NASA-zone cols (120-153)
       hit ← ADS search(abs:"<planet>" abs:"<host>" → abs:"<planet>" → full:"<planet>")
       IF hit: write Title / Authors / Journal / URL / Abstract
4. dedup ← check_exokyotodataf_duplicates.py(new_xlsx)
       (informational only; does not auto-merge)
5. csv ← xlsx_to_csv(new_xlsx)               → internal/latest/ExoKyotoDataF.csv
6. bin ← csv_to_bin(csv)                     → internal/latest/ExoKyotoDataF.bin
7. archive ← move data/latest/ExoKyotoDataF.bin
                 → data/past/ExoKyotoDataF<YYYYMMDDNN>.bin
   install ← copy internal/latest/ExoKyotoDataF.bin
                 → data/latest/ExoKyotoDataF.bin
8. version.json ← {
       data_version : <user-supplied stamp, e.g. "2026.05.19N-preview">,
       binary_url   : <URL where the bin will be served>,
       release_date : today (UTC),
       notes        : <release-notes or "Added: <list>" auto-generated>,
       ...
   }                                          → ExoKyotoData/version.json

OUTPUT : git working tree clean to push the two changed files:
         - ExoKyotoData/version.json
         - ExoKyotoData/data/latest/ExoKyotoDataF.bin
```

### Client-side (what each running app does)

```
ON APP STARTUP:
1. ekupdate::run_async_check()        // called from main(), top-of-function
   ├─ Sync breadcrumb: append "run_async_check() called" to
   │  ~/Library/Logs/ExoKyoto/update_check.log
   └─ Spawn detached std::thread → do_check()

DETACHED THREAD do_check():
2. Open log file (append mode) at ~/Library/Logs/ExoKyoto/update_check.log
3. Log: bundled stamp (EXOKYOTO_DATA_VERSION) and URL (EXOKYOTO_VERSION_URL)
4. response = popen("/usr/bin/curl -sL --max-time 10 --fail '<URL>'")
   IF response empty: log "no response", return
5. remote_ver = extract_json_string(response, "data_version")
   binary_url = extract_json_string(response, "binary_url")
   notes      = extract_json_string(response, "notes")
   IF remote_ver empty: log "parse fail", return
6. COMPARISON (the trigger):
       IF remote_ver == EXOKYOTO_DATA_VERSION:
           log "up to date"
           return                              ← silent, no UI
       ELSE:
           log "UPDATE AVAILABLE: <bundled> -> <remote>"
           CALL Phase 3 dialog (or Phase 4 auto-download)
7. Phase 3 (current): popen("osascript -e 'display dialog ... buttons {OK}'")
   Phase 4 (planned): see below.
```

**Comparison is strict string equality** — no semver parsing. Any change to the
`data_version` string on GitHub triggers the update path on every app that
launches afterward, regardless of which direction the version "moved". This is
by design: the server side is the source of truth for "what version users
should have".

### Phase 4 (auto-download + auto-restart — IMPLEMENTED)

```
On mismatch detected:

1. Dialog #1 — confirm download:
       "ExoKyoto data update available.
        Current : <sidecar version, or bundled if no sidecar>
        Latest  : <remote>
        <notes from version.json>
        Download and apply now?"   [Later] [Download]   ← default Download

2. If Download:
   a. /usr/bin/curl -sL --max-time 60 --fail '<binary_url>' -o /tmp/exokyoto_pending.bin
   b. Verify magic bytes "EKDBIN1\0" + sane size (1 MB – 200 MB)
   c. rename csvin/ExoKyotoDataF.bin → csvin/ExoKyotoDataF.bak.bin (rollback safety)
   d. cp /tmp/exokyoto_pending.bin → csvin/ExoKyotoDataF.bin
   e. Write csvin/ExoKyotoDataF.bin.version = <remote data_version>   ← sidecar
   f. Dialog #2 — confirm restart:
        "Update applied: <remote>
         Old data backed up as csvin/ExoKyotoDataF.bak.bin
         Restart ExoKyoto now to load the new data?"   [Later] [Restart now]   ← default Restart now
   g. If Restart now:
        /usr/bin/open -n '<.app bundle absolute path>' &     # launch fresh instance
        sleep 1
        _exit(0)                                              # hard-exit this process

3. If any step fails (download error / bad magic / install rc != 0):
   - Roll back: rename .bak.bin → live bin
   - Dialog: "Update failed. Previous data restored."
   - No sidecar write, so next launch will retry.
```

The `.app` bundle path is found via `_NSGetExecutablePath` + climb-3-levels:

```
/Users/x/Apps/ExoKyoto3D.app/Contents/MacOS/SolarClass
                              ↓ climb 3 levels
/Users/x/Apps/ExoKyoto3D.app
```

If `_NSGetExecutablePath` doesn't end in a `.app/Contents/MacOS/...` path (dev
mode), the auto-restart is disabled and the dialog reverts to a plain "please
restart" OK button.

Path note: when launched via the `.app` bundle's launcher script (see
`build_app_bundles.sh`), cwd is `Contents/Resources/`, so `./csvin/...` is
the correct in-bundle location for both the bin and its sidecar. Code-signed
apps may refuse the in-place overwrite in the future — current unsigned
distribution allows it.

---

## Client-side (in-app) update flow

The C++ app (`src/update_check.cpp` in ExoKyoto3D/4D/4Dalpha) does, in a
detached thread, ~2 seconds after launch:

1. `popen("/usr/bin/curl -sL --max-time 10 --fail '<EXOKYOTO_VERSION_URL>'")`
   → fetches `version.json` (~450 bytes)
2. Parse JSON (regex extraction of `data_version`, `binary_url`, `notes`)
3. If `data_version` ≠ `EXOKYOTO_DATA_VERSION` (compile-time stamp baked into the
   binary by the makefile's `DATA_VERSION` variable):
   - **Phase 3 (current)**: show `osascript display dialog` with the new
     version + notes + download URL
   - **Phase 4 (planned)**: auto-download the bin via curl and apply to
     `./csvin/ExoKyotoDataF.bin` (replaces the bundled file; next launch picks
     up the new data)

Build-time stamp injection:

```makefile
DATA_VERSION        ?= 2026.05.19-preview
EXOKYOTO_VERSION_URL ?= https://raw.githubusercontent.com/YosukeAlex/ExoKyoto3D-Data/main/version.json
CFLAGS += -DEXOKYOTO_DATA_VERSION='"$(DATA_VERSION)"' \
          -DEXOKYOTO_VERSION_URL='"$(EXOKYOTO_VERSION_URL)"' \
          -pthread
```

Log destination: `~/Library/Logs/ExoKyoto/update_check.log` (always appended).

---

## Manual override / rollback

### Roll back to a previous bin
```bash
ls gaia/ExoKyotoData/data/past/
cp gaia/ExoKyotoData/data/past/ExoKyotoDataF2026051901.bin \
   gaia/ExoKyotoData/data/latest/ExoKyotoDataF.bin
# then push that bin to GitHub (and don't change version.json, or revert it)
```

### Force the version dialog to fire on a deployed app
```bash
rm -f ~/Library/Logs/ExoKyoto/update_check.log
open /path/to/ExoKyoto3D.app
tail -f ~/Library/Logs/ExoKyoto/update_check.log
```

### Test pipeline without writing anything
```bash
python3 exokyoto_update_pipeline.py --in-xlsx <file> --data-version test --dry-run
```

---

## Dependencies

- Python 3 (system)
- `openpyxl` (for xlsx I/O)
- `/usr/bin/curl` (system, used by both the pipeline and the in-app check)
- ADS API token (free signup at https://ui.adsabs.harvard.edu, "Account →
  Settings → API Token") — set as `ADS_TOKEN` env var

---

## Related files

| File | Purpose |
|---|---|
| `exokyoto_update_pipeline.py` | This pipeline |
| `csv_to_ekdbin.py` | Standalone CSV→bin (used by pipeline) |
| `check_exokyotodataf_duplicates.py` | Dedup checker (invoked by pipeline) |
| `fetch_ads_papers.py` / `fetch_ads_by_planet_name.py` | Legacy ADS bulk fetchers (kept for reference) |
| `fill_paper_references_v3.py` | Legacy ADS-to-xlsx applier (replaced by pipeline) |
| `nasa_transit_coverage_report.py` | Standalone NASA transit coverage report |
| `../ExoKyoto3D/src/update_check.cpp` | Client-side version checker |
| `DATA_POLICY_AND_UPDATE_PLAN_20260519.md` | Data-source provenance rules |
| `UPDATE_DELIVERY_POLICY_20260519.md` | Distribution policy (Phase 1-4) |
| `WORKFLOW_INDEX.md` | Master index of the gaia/ workflow |
