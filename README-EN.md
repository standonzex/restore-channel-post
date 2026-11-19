# Restore Channel Post — 1.8

Recover an accidentally deleted channel post from Recent Actions within 48 hours of deletion. Keep its original message ID, publication time and chronological position. This package contains a runnable reference implementation and a separate patch to Telegram iOS's existing Recent Actions screen.

## iPhone quick start

On a Mac with Xcode and an installed, booted iPhone Simulator:

```sh
./build-ios-demo.sh
./run-ios-demo.sh
```

Keep the server terminal open. A fresh synthetic channel starts empty; existing state persists. Use the bottom info control to empty it or load old-post examples. The UI starts in Russian; info can switch it to English. Publish text or the prepared circular-video fixture, delete it, then use profile → Edit → Recent Actions → long-press → Restore. The 3 April 2022 / 17:30 example verifies recovery to an old date.

Full instructions: submission/REVIEWER-EN.md and IOS-SETUP.md. No Telegram account, bot token, cloud API or paid dependency is required. Physical iPhone deployment is not supplied.

## Mac quick start

```sh
./build.sh
open 'dist/Restore Channel Post.app'
```

The Mac app launches and stops its local server automatically. EN switches to English. Reset the fixtures and restore the 2022 post from Channel Settings → Recent Actions. Start Demo.command is another entry point.

## Verify

```sh
./verify.sh
./build-ios-demo.sh
```

64 server/module/policy/model checks, native Swift–HTTP–SQLite integration, patch syntax and both standalone host builds/signatures are covered. For clean pinned-base application/source consistency checks, set RECOVERY_TELEGRAM_CHECKOUT=/path/to/Telegram-iOS when running verify.sh. That does not modify the checkout or build the entire Telegram client. See QA-REPORT.md.

## Structure

- module/: dependency-free Swift recovery types, coordinator, transport boundary and URLSession reference client.
- server/: SQLite transaction, retention, current rights, deletion generations, retry deduplication and local HTTP API.
- app/ and ios-demo/: Mac and iPhone reference hosts sharing the coordinator.
- ios/: complete native modified files and the pinned Recent Actions patch.
- tests/: canonical identity/order, concurrency, error, HTTP and view-model coverage.
- submission/: copy-ready English message, Russian translation, feature description, reviewer instructions and sending requirements.

## Integration boundary

The runnable hosts use the included authenticated loopback server and synthetic data. Deployment to live channels requires Telegram's canonical restore operation, authenticated transport and synchronization. The upstream Telegram-iOS patch is not fully built/run; its production provider is intentionally unregistered. The local composer simulates recording with a prepared clip. Fixture counters do not demonstrate live reactions/discussions. See CODE-STATUS.md, API-CONTRACT.md and INTEGRATION.md.

Source archives exclude databases, session secrets, .env, Again bot files, personal screenshots and presentation renders. A small internal MOV fixture is included for actual video-note playback/recovery. The presentation video is supplied separately. License and upstream attribution: LICENSE.md and NOTICE.md.
