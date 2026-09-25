# Backup: YouTube backend (2026-09-25)

Unchanged copies of the files that listed, played and downloaded online songs
through YouTube, taken just before the Online source moved to JioSaavn.
Paths mirror the project (`lib/...`). How they worked:
[docs/BACKEND_YOUTUBE.md](../../docs/BACKEND_YOUTUBE.md).

To restore, copy a file back over its counterpart in `lib/`. The folder is
excluded from `flutter analyze` (see analysis_options.yaml), so these copies
never affect the build.
