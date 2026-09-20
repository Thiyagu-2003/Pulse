# Pulse

Pulse is a zero-cost, cross-platform music and podcast player built with Flutter. It seamlessly integrates local device music, online YouTube music streams, and podcasts into a single unified interface. 

## Features

- **Unified Library**: Access local audio files, YouTube music, and podcasts in one place.
- **Background Playback**: Continues playing music and audio even when the screen is off or the app is in the background.
- **Zero Cost**: Built entirely using free, open APIs (NewPipe Extractor for YouTube audio streams) and local media pipelines.
- **Offline Downloads**: Download tracks for offline listening without premium subscriptions.
- **Cross-Platform**: Designed for Android and iOS using Flutter.

## Tech Stack

- **Framework**: Flutter
- **Audio Pipeline**: `audio_service`, `just_audio`
- **YouTube Extraction**: `newpipeextractor_dart` (Native Android Extractor), `youtube_explode_dart` (Metadata)
- **Local Media**: `on_audio_query`

## Getting Started

1. Clone the repository
2. Run `flutter pub get`
3. Connect your Android 13+ device.
4. Run `flutter run`

*Note: For the native YouTube extraction to work correctly, this project requires Android SDK 22+ and Java core library desugaring.*
