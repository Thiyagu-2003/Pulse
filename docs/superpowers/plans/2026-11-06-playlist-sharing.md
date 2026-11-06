# Playlist Sharing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement zero-friction playlist sharing and importing for Pulse, supporting `.pulse` files, compact share links/codes, an interactive import preview modal with conflict resolution, and Android file associations.

**Architecture:** Pure Dart serialization and Gzip+Base64 encoding in a dedicated `PlaylistCodec` utility; conflict-aware import methods in `MusicPlayerProvider`; Android `intent-filter` and `content://` streaming in `MainActivity.kt` exposed via `PlatformBridge`; and custom `SharePlaylistSheet` and `ImportPlaylistSheet` widgets matching the Pulse design system.

**Tech Stack:** Flutter / Dart, Android Kotlin (FileProvider, IntentFilters, MethodChannel), Hive (storage), JUnit / Flutter Test.

**Spec:** `docs/superpowers/specs/2026-11-06-playlist-sharing-design.md`

## Global Constraints
- Zero new external pub dependencies (`no share_plus / url_launcher / package_info dependencies`).
- All platform interactions route through `PlatformBridge` and `MainActivity.kt`.
- Maintain backwards compatibility with existing `.json` exported files.
- Safe handling of `content://` URIs without `FileSystemException`.
- Tests must pass cleanly on Windows host without network access (`flutter test`).

## Review Focus
- Attempting to import corrupt or truncated Gzip/Base64 code (graceful error banner, no crash).
- Malformed JSON missing required fields or containing non-audio items (throws `FormatException` caught cleanly).
- Playlists containing duplicate track names or special characters in folder names.
- Conflict resolution when replacing a previously downloaded playlist (preserve folder safety).
- Large playlists (>100 songs) producing oversized share strings (warn user and default to file sharing).

---

### Task 1: Playlist Codec & Unit Tests

**Files:**
- Create: `lib/util/playlist_codec.dart`
- Test: `test/playlist_codec_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class PlaylistCodec {
    static ({Map<String, dynamic> json, int skipped}) exportToJson(Playlist playlist);
    static String exportToCode(Playlist playlist);
    static Map<String, dynamic> parseCodeOrText(String text);
    static ({String name, List<AppMediaItem> items}) validatePlaylistJson(Map<String, dynamic> json);
  }
  ```

- [ ] **Step 1: Write the failing unit tests in `test/playlist_codec_test.dart`**
  Cover:
  - `exportToJson` creates valid Pulse format with version 2 and filters non-streamable tracks.
  - `exportToCode` produces a URL-safe string prefixed with `pulse://playlist?d=`.
  - `parseCodeOrText` extracts JSON from raw codes, URLs, or full chat messages containing the link.
  - Corrupt or invalid codes throw a readable `FormatException`.

- [ ] **Step 2: Run test to verify it fails**
  Run: `flutter test test/playlist_codec_test.dart`
  Expected: FAIL (file or class not found)

- [ ] **Step 3: Implement `PlaylistCodec` in `lib/util/playlist_codec.dart`**
  Use `dart:convert` (json, utf8, base64Url) and `dart:io` (`gzip.encode`, `gzip.decode`).

- [ ] **Step 4: Run test to verify it passes**
  Run: `flutter test test/playlist_codec_test.dart`
  Expected: PASS

- [ ] **Step 5: Commit**
  ```bash
  git add lib/util/playlist_codec.dart test/playlist_codec_test.dart
  git commit -m "feat: add PlaylistCodec for playlist file and link serialization"
  ```

---

### Task 2: Provider Conflict Resolution & Import Logic

**Files:**
- Modify: `lib/providers/music_player_provider.dart`
- Test: `test/playlist_conflict_test.dart`

**Interfaces:**
- Consumes: `PlaylistCodec` from Task 1.
- Produces:
  ```dart
  enum PlaylistConflictResolution { keepBoth, replace, merge }

  extension PlaylistImport on MusicPlayerProvider {
    bool hasPlaylistNamed(String name);
    Future<Playlist> importPlaylistWithResolution({
      required String name,
      required List<AppMediaItem> items,
      PlaylistConflictResolution resolution = PlaylistConflictResolution.keepBoth,
    });
  }
  ```

- [ ] **Step 1: Write the failing tests in `test/playlist_conflict_test.dart`**
  Cover:
  - `hasPlaylistNamed` detects existing playlists case-insensitively.
  - `keepBoth` generates `Name (1)`, `Name (2)`.
  - `replace` overwrites items and resets `folder`.
  - `merge` appends tracks deduplicating by ID and normalized title+artist.

- [ ] **Step 2: Run test to verify it fails**
  Run: `flutter test test/playlist_conflict_test.dart`
  Expected: FAIL

- [ ] **Step 3: Implement conflict resolution in `MusicPlayerProvider`**
  Wire into storage service, ensuring state notifications and persistence.

- [ ] **Step 4: Run test to verify it passes**
  Run: `flutter test test/playlist_conflict_test.dart`
  Expected: PASS

- [ ] **Step 5: Commit**
  ```bash
  git add lib/providers/music_player_provider.dart test/playlist_conflict_test.dart
  git commit -m "feat: add conflict-aware playlist import methods to provider"
  ```

---

### Task 3: Android Intent Filters & Native Bridge for Shared Files/Links

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/src/main/kotlin/com/pulse/music/MainActivity.kt`
- Modify: `lib/services/platform_bridge.dart`

**Interfaces:**
- Produces:
  ```dart
  class PlatformBridge {
    static Future<String?> getInitialSharedData();
    static Stream<String> get sharedDataStream;
  }
  ```

- [ ] **Step 1: Update `AndroidManifest.xml` with intent filters**
  Add `<intent-filter>` for:
  - `ACTION_VIEW` for file extension `.pulse` and `.json`.
  - `ACTION_VIEW` for scheme `pulse` with host `playlist`.
  - `ACTION_SEND` for MIME types `application/octet-stream`, `application/json`, and `text/plain`.

- [ ] **Step 2: Implement intent caching and stream resolving in `MainActivity.kt`**
  - Read incoming `content://` streams and copy to `cacheDir/shared/incoming_shared.pulse`.
  - Extract incoming `pulse://` URI string or `EXTRA_TEXT` text string.
  - Support `getInitialSharedData` method call and method channel / event channel dispatch on `onNewIntent`.

- [ ] **Step 3: Expose shared data in `PlatformBridge.dart`**
  Provide safe cross-platform fallbacks (returns null on non-Android).

- [ ] **Step 4: Commit**
  ```bash
  git add android/app/src/main/AndroidManifest.xml android/app/src/main/kotlin/com/pulse/music/MainActivity.kt lib/services/platform_bridge.dart
  git commit -m "feat: register Android intent filters and bridge for shared playlists"
  ```

---

### Task 4: Share & Import Sheets and UI Integration

**Files:**
- Create: `lib/ui/widgets/share_playlist_sheet.dart`
- Create: `lib/ui/widgets/import_playlist_sheet.dart`
- Modify: `lib/ui/screens/playlists_screen.dart`
- Modify: `lib/ui/screens/main_navigation_screen.dart`
- Test: `test/playlist_ui_test.dart`

**Interfaces:**
- Consumes: `PlaylistCodec`, `MusicPlayerProvider`, `PlatformBridge`.

- [ ] **Step 1: Implement `SharePlaylistSheet`**
  - Options: Share File (`.pulse`), Copy Share Link (`pulse://...`), Share Text Message.
  - Show warning / disable code share if playlist exceeds 100 tracks.

- [ ] **Step 2: Implement `ImportPlaylistSheet`**
  - Header: Editable playlist name, track count, total duration.
  - Track preview list.
  - Conflict resolution toggle if a playlist with that name exists (`Keep both`, `Replace`, `Merge`).
  - Action buttons: "Import" and "Cancel".

- [ ] **Step 3: Connect to `PlaylistsScreen` and `MainNavigationScreen`**
  - Replace direct share with `showSharePlaylistSheet(context, playlist)`.
  - Update AppBar import button to allow choosing file or pasting text code, opening `showImportPlaylistSheet`.
  - Listen to `PlatformBridge.sharedDataStream` and `getInitialSharedData()` in `MainNavigationScreen` to present `ImportPlaylistSheet` immediately when opened from an external app.

- [ ] **Step 4: Write widget test in `test/playlist_ui_test.dart`**
  Verify opening and interaction of the import preview sheet.

- [ ] **Step 5: Run tests**
  Run: `flutter test test/playlist_ui_test.dart`
  Expected: PASS

- [ ] **Step 6: Commit**
  ```bash
  git add lib/ui/widgets/share_playlist_sheet.dart lib/ui/widgets/import_playlist_sheet.dart lib/ui/screens/playlists_screen.dart lib/ui/screens/main_navigation_screen.dart test/playlist_ui_test.dart
  git commit -m "feat: integrate SharePlaylistSheet and ImportPlaylistSheet UI"
  ```

---

### Task 5: End-to-End Verification & Analyzer Check

- [ ] **Step 1: Run full test suite**
  Run: `flutter test`
  Expected: All tests pass.

- [ ] **Step 2: Run Flutter Analyzer**
  Run: `flutter analyze`
  Expected: Zero warnings / issues.

- [ ] **Step 3: Final Commit & Summary**
  ```bash
  git commit -m "chore: verify and finalize playlist sharing system"
  ```

