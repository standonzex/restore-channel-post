# Reviewer quick start — 1.8

Extract RestoreChannelPost-Source-1.8.zip and open a terminal in its RestoreChannelPost directory. No Telegram login, bot token, cloud API or paid dependency is needed. All channel data is synthetic and uses a local authenticated server.

## iPhone reference

A Mac, full Xcode and an installed iOS Simulator runtime are required. The host deployment target is iOS 16; the verified environment is Xcode 26.6 / iOS 26.5 on Apple Silicon.

```sh
./build-ios-demo.sh
./run-ios-demo.sh
```

Open one booted iPhone simulator before launch. For several devices, use `./run-ios-demo.sh <simulator-udid>`. Keep the server terminal open; Ctrl+C stops it. The script installs only the standalone reference bundle, not Telegram. Physical-iPhone deployment is not supplied.

A fresh iPhone database starts empty; an existing dataset persists. Use the bottom info button → Start with an empty channel to reset only the synthetic demo. Enter any text and send it. Hold the video camera control for about four seconds and release: this publishes the included prepared clip. A short tap sends nothing; dragging left cancels. The preview simulates recording, without accessing a camera or microphone.

Long-press the circle's edge → Delete → Delete for Everyone. Channel title → Edit → scroll to Recent Actions → long-press the deleted card → Restore. The same post returns and can be played. The user interface starts in Russian; info → English interface switches the language.

To verify an old original date, choose info → Load old-post examples. Restore the 3 April 2022 / 17:30 post; it returns before the later posts with its original ID and metadata.

## Mac reference

```sh
./build.sh
open 'dist/Restore Channel Post.app'
```

The Mac host starts and stops its loopback server automatically. EN switches to English. Reset the synthetic examples, delete the 2022 post, open Channel Settings → Recent Actions → Restore. Text, photo and playable video fixtures are included. The separate prebuilt Mac archive is optional and ad-hoc signed, not notarized.

## Verification

```sh
./verify.sh
./build-ios-demo.sh
```

These run 64 server/module/policy/model checks, native Swift–HTTP–SQLite integration, Swift syntax checks, and both standalone host builds/signatures. Optional pinned upstream patch checks:

```sh
RECOVERY_TELEGRAM_CHECKOUT=/path/to/Telegram-iOS ./verify.sh
```

That command reads base commit 24638bc69bd083981b178dd1e7f921eebbf7fc46 and verifies clean application, complete source consistency, reverse application and syntax. It does not modify the checkout or build the complete Telegram client.

## Files to review

- `server/recovery.py`: transaction, authorization, retention, generation and retry semantics.
- `module/Sources/ChannelRecoveryKit/RecoveryCoordinator.swift`: shared recovery coordinator and canonical validation.
- `module/Sources/ChannelRecoveryKit/ReferenceClient.swift`: local URLSession client.
- `ios/channel-post-recovery.patch`: existing Telegram Recent Actions integration.
- `ios/Sources/ModuleChannelPostRecoveryProvider.swift`: bridge to the shared coordinator.
- `API-CONTRACT.md`, `INTEGRATION.md`, `CODE-STATUS.md`: production handoff and exact limits.

The iPhone/Mac hosts are runnable. The Telegram-iOS patch is conditional on a supported production provider and has not been fully type-checked, built or run. This package does not restore posts in live Telegram channels. Demo Reply/Edit/Pin/Select actions are limited scaffolding. Source media includes one small MOV fixture needed for video-note playback; the competition presentation video is not in this package.
