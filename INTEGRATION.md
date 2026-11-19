# Integration notes

## Runnable implementation

`TelegramRecoveryView` (iPhone) / `RecoveryView` (Mac) → `RecoveryViewModel` → `ChannelRecoveryKit.RecoveryCoordinator` → `ReferenceRecoveryTransport` → `RecoveryClient` → loopback HTTP API → `RecoveryStore` → SQLite.

The UI renders only state obtained from the server. Delete writes the deletion generation and expiry; restore clears the deletion marker on the same canonical row. Audit and change intent commit in the same transaction. A successful response includes the original post; the native client compares it to the selected original, then refreshes the authoritative channel state before navigating to it.

The 48-hour policy starts at deletion. Media fixtures remain at stable paths and are served with HTTP byte-range support for AVPlayer. The local backend's actor is derived from the token-bound demo session, not accepted in request JSON. It is a single-channel reference environment, not a general multi-tenant Telegram backend.

## Existing Telegram iOS screen

`ios/channel-post-recovery.patch` changes the actual `ChatRecentActionsController` module at the pinned upstream revision. It adds Restore after the existing Copy action for eligible deleted channel messages, checks local permission and age, prevents parallel duplicate actions, validates the canonical result, and navigates to the original message. Selecting Restore starts recovery directly, matching the iPhone host and concept video.

The patch includes `ModuleChannelPostRecoveryProvider`, a concrete adapter from the Telegram UI protocol to the shared, compiled `ChannelRecoveryKit.RecoveryCoordinator`. The coordinator requires a `RecoveryTransport` supplied by the host and enforces a 15-second deadline, including for transports that ignore cancellation. A timeout preserves the retry UUID because the server may still commit. No production server implementation is silently substituted for it. Without a provider, the existing Telegram UI behaves as before. To integrate it:

1. Implement the server operation and eligibility response described in `API-CONTRACT.md`.
2. Implement `RecoveryTransport` using Telegram's authenticated network/session layer. Map server errors to `RecoveryFailure`, and use a finite timeout. Apply authoritative updates through Telegram's state manager and verify canonical retrieval before returning success. The supplied `ModuleChannelPostRecoveryProvider` converts this coordinator's receipt to the existing native UI result. The patch includes the core module's Bazel target and the UI dependency.
3. Provide localized strings. At the app composition root, call `ChannelPostRecoveryIntegration.install(providerFactory:)` with a factory that derives the authenticated service from the supplied current `AccountContext` and channel `EnginePeer`. Return nil for unsupported channels/accounts. Normal `ChatRecentActionsController` construction resolves this factory automatically; the optional explicit `postRecovery:` argument remains available. Do not reuse one account's provider for another account. Registration is lock-protected; resolution runs on the UI thread outside the lock. The package does not register a production factory because no supported server operation is available.
4. Check actual iOS compilation, release exports and localization in the official build environment.
5. Test on simulator/device, including multiple clients, offline catch-up, history holes, shared-media/search indexes, media references, albums, notification suppression and independently changed discussion state. Record and inspect simulator frames as required by the upstream repository instructions.

The standalone iPhone host uses the shared Swift package. Its route is long-press post → Delete → Delete for Everyone → channel profile → Edit → Recent Actions → long-press deleted post → Restore. Build it with `build-ios-demo.sh` and launch against the separate synthetic dataset with `run-ios-demo.sh`. These steps do not change an installed Telegram app. Recovery and deletion use real local requests; unrelated Reply/Edit/Pin/Select commands only preview the selected post, and informational profile controls are not a full Telegram implementation.

The current environment has Xcode 26.6 and `simctl`. The standalone iPhone simulator app compiles with the iOS 26.5 SDK; the standalone reference UI passed text restore, restart persistence and video restore/playback checks on iPhone 17 / iOS 26.5. The pinned upstream Telegram client specifies Xcode 27.1. Its integration patch has only syntax and patch-application checks and must not be described as a fully built or live integrated Telegram iOS implementation.

## Backend responsibilities

The Python outbox illustrates atomic change intent. Telegram's actual PTS/update delivery, push-notification policy, indexing, moderation constraints and media/discussion lifecycle must be implemented in Telegram infrastructure. No third-party client can supply that infrastructure or choose an old Telegram message ID.

## Local storage and lifecycle

The native Mac host starts a loopback-only server on an ephemeral port with a new random bearer token. It stops that child when the last window closes. The server also watches the parent's PID. Database storage is outside the app bundle in the user's Application Support directory, so restarting or rebuilding does not clear data. Reset affects only the synthetic demo database. Expired records are removed by the server's periodic retention worker; no claim of forensic secure erasure is made.

## Reproduce patch checks

`python3 tools/verify_native_patch.py /path/to/Telegram-iOS` extracts the eight affected paths from the pinned base into a temporary directory, applies the patch, compares the six resulting Swift files against the complete supplied sources/shared coordinator, parses their syntax and checks reverse application. It never changes the checkout or its index. `RECOVERY_TELEGRAM_CHECKOUT=/path/to/Telegram-iOS ./verify.sh` includes this check in the suite. It is not a full type-check or a Telegram target build.
