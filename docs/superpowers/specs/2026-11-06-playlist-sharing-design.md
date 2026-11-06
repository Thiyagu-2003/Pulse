# Playlist Sharing & Import Enhancement Design

## Intent & Why
Pulse users want an effortless, reliable way to share their playlists with friends. While basic JSON export exists, receiving and importing a playlist has high friction: the recipient must save the file manually, open Pulse, navigate to the Playlists tab, tap an import icon, and browse system storage. Furthermore, recipients cannot preview the songs before importing, and duplicate names cause silent overwrites or confusion.

This design makes playlist sharing seamless, flexible, and interactive:
1. One-tap file open via Android file association (`.pulse` and `.json`).
2. Compact text/code sharing (copy/paste code without needing file attachments).
3. Rich Import Preview Sheet with song list preview and conflict handling (Replace, Keep Both, Merge).
4. Multiple sharing options (Share File, Copy Code, Share Text).

---

## Goals & Non-Goals

### Goals
- **Zero-friction receiving**: Tapping a shared `.pulse` (or `.json`) file in WhatsApp, Telegram, or a file manager immediately opens Pulse and displays the Import Preview sheet.
- **Multiple sharing modes**:
  - **Share File (`.pulse`)**: Native file share sheet for standard file sharing.
  - **Copy Code / Share Text**: Compact Gzip+Base64 text string with `pulse://playlist?d=...` or `PULSE:...` prefix for simple messaging without file attachments.
- **Import Preview Sheet**:
  - Displays playlist name, song count, estimated duration, and preview of tracks.
  - Detects duplicate playlist names and provides explicit resolution options: "Keep both" (auto-renames to `Name (1)`), "Replace existing", or "Merge songs".
  - Allows editing the playlist title before importing.
- **Backwards compatibility**: Retains support for reading older `.json` exported files.
- **Adherence to repo constraints**: Zero new external dependencies (`no share_plus / url_launcher`). Uses built-in `dart:convert`, `dart:io`, and native `MainActivity.kt` / `PlatformBridge`.
- **Comprehensive test coverage**: Unit tests for serialization, compression/decompression, code parsing, and conflict handling.

### Non-Goals
- Cloud database syncing or real-time collaborative playlists (Pulse remains a private, local-first player).
- Streaming proprietary audio files (offline device-only tracks remain excluded with clear user notification, matching current behavior).

### Anti-Goals
- Bloating pubspec with heavyweight sharing or QR dependencies when built-in platform channels and standard library compression serve the purpose cleanly.
- Forcing users into multi-step dialogs when simple one-tap actions suffice.

---

## Architecture & Implementation

### 1. File Format & Intent Filter
- **Extension**: `.pulse` (MIME type `application/octet-stream` or `*/*` with `.pulse` extension).
  - Internally remains JSON: `{"app": "pulse", "type": "playlist", "version": 2, "name": "...", "items": [...]}`.
- **Android Manifest (`AndroidManifest.xml`)**:
  - Add `intent-filter`s under `MainActivity`:
    - `ACTION_VIEW` and `ACTION_SEND` with `scheme="content"`, `scheme="file"`.
    - Mime types: `application/json`, `application/octet-stream`, `*/*` with file extensions `.pulse` and `.json`.
    - Custom deep link scheme: `<data android:scheme="pulse" android:host="playlist" />`.
- **Native Android Bridge (`MainActivity.kt` & `PlatformBridge.dart`)**:
  - Native Kotlin handles incoming `content://` streams from `ACTION_VIEW` and `ACTION_SEND` by copying them to `cacheDir/shared/incoming_playlist.pulse` so Flutter can read them with standard `File.readAsString()` without `FileSystemException`.
  - For `ACTION_SEND` with `EXTRA_TEXT`, native Kotlin extracts the text string.
  - Exposes `PlatformBridge.getInitialSharedData()` and a stream/callback for runtime arrivals.

### 2. Compact Text / Share Code Format
- For chats where sending files is inconvenient:
  - Serialize streamable tracks with full metadata needed for preview (id, title, artist, album, artUri, streamUrl, durationMs, sourceType).
  - Compress UTF-8 JSON with Gzip and encode with URL-safe Base64:
    `pulse://playlist?d=<base64>` or `PULSE:<base64>`.
  - Can be shared as friendly formatted text:
    > "Check out my playlist 'Summer Vibes' (24 songs) on Pulse!
    > pulse://playlist?d=..."
- **Import from Code**:
  - In Playlists tab: "Import Playlist" modal offers "Pick File" or "Paste Code / Link".
  - If clipboard contains a valid `PULSE:...` or `pulse://...` code, automatically pre-fill or suggest it.

### 3. Share Options Modal
When the user taps "Share" on a playlist:
- Bottom sheet with options:
  - **Share File (`.pulse`)**: Writes to `cache/shared/` and opens native Android share sheet.
  - **Copy Share Code / Link**: Copies `pulse://playlist?d=...` string to clipboard with instant snackbar confirmation.
  - **Share as Message**: Opens share sheet with pre-filled friendly text containing the title, song count, and import link.

### 4. Import Preview & Conflict Resolution
When a file is opened or code is entered:
- Shows a bottom sheet / dialog:
  - **Header**: Playlist Title (editable text field), song count, and duration.
  - **Song Preview**: Scrollable list of tracks (with artwork, title, and artist).
  - **Duplicate Check**:
    - If a playlist with this name already exists in Hive:
      - Prompt options:
        - "Keep both" (saves as `Name (1)`)
        - "Replace" (replaces existing playlist tracks; clears folder if it was downloaded)
        - "Merge" (appends tracks not already present by id or matching title+artist)
  - **Actions**: "Import" (accent button) and "Cancel".

---

## Builder Decisions (Settled)
- **Metadata Retention in Compact Code**: `durationMs` and `artUri` are preserved in the compressed JSON so the preview sheet can calculate total duration and show album art instantly without network fetches.
- **Deep Links & Scheme**: Registered in `AndroidManifest.xml` under scheme `pulse` and host `playlist`.
- **Content URIs**: `MainActivity.kt` safely buffers `content://` streams into an app-private cache file before passing the path to Flutter.
- **Conflict Handling**: "Replace" replaces the track items without deleting physical downloaded files; "Merge" deduplicates tracks by `id` or normalized title + artist.
- **Compact Code Size**: Playlists up to 100 songs can be shared via code/text. Playlists with >100 songs prompt file sharing to avoid chat truncation.
