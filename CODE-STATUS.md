# Implementation status — 1.8 / 19 November 2026

This is an executable reference implementation of a proposed Telegram feature. The standalone iPhone and Mac hosts use their own authenticated loopback Python/SQLite service. They do not connect to live Telegram channels. Source, build scripts, tests, synthetic media and a separate native Telegram-iOS patch are supplied.

## Implemented behavior

- Long-press a channel post → Delete → Delete for Everyone.
- Channel profile → Edit → Recent Actions → long-press the eligible deleted post → Copy / Restore.
- Restore starts directly and returns the existing canonical record with the same ID, timestamp and relative position. It does not call send/forward or invent an old display date.
- Current permissions, deletion generation and a 48-hour window from deletion are checked server-side. Old publications can return to their original dates.
- Retry identity, concurrent recovery, stale deletion requests, expiry, restart persistence and authoritative-refresh failure are handled. A timeout does not imply server rollback.
- Text, photo and playable video-message fixtures use the same recovery path. Stored fixture counters are retained; live Telegram reactions/discussions are not tested.

## Standalone hosts

The shared Swift module is compiled into both hosts. The iPhone host has an input composer, synthetic-channel reset and simulated hold/release video preview using a prepared clip. It does not capture a physical camera or microphone. Unrelated Reply/Edit/Pin/Select controls are limited scaffolding, not a replacement Telegram client. The optional capture-canvas flag changes only presentation layout.

## Native Telegram-iOS patch

The patch changes the existing ChatRecentActionsController screen at pinned commit 24638bc69bd083981b178dd1e7f921eebbf7fc46. It adds Restore after Copy, eligibility checks, in-flight protection, identity validation and navigation to the original. ModuleChannelPostRecoveryProvider adapts the shared coordinator. Normal navigation resolves an account/channel-aware provider factory through ChannelPostRecoveryIntegration.

Clean patch application, complete-source consistency, reverse application and six Swift syntax checks are verified. The complete upstream client has **not** been fully type-checked, built or run. The pinned checkout requires Xcode 27.1 / macOS 27; the verified local environment is Xcode 26.6 / macOS 26.5.2. No production provider factory is registered.

## Telegram responsibilities for rollout

Telegram needs a supported canonical server-side restore operation, authenticated account transport and normal update synchronization. Its PTS, multi-client convergence, search/shared-media indexes, notification policy, media retention and discussion/reaction storage must be implemented and tested in its infrastructure. No third-party client can choose an old Telegram message ID or alter its server history by itself.

The supplied SQLite transaction/outbox is a reference for the operation, not Telegram's closed backend. API-CONTRACT.md and INTEGRATION.md describe the boundary. The current public method list and admin-log documentation do not provide this canonical restoration operation: https://core.telegram.org/methods and https://core.telegram.org/api/recent-actions .

## Delivery

1.8 consolidates the current code-and-documentation handoff. The latest admin-log presentation/search/filter refinements are retained. Channel setup audit events are classified as informational, with an additional regression check. The duration label is read from actual media metadata instead of a hard-coded value. The canonical restore transaction, shared coordinator and media fixtures remain unchanged. The competition presentation video is intentionally delivered separately. New smooth character animation is not required to test restoration and is not substituted into the code in this release. Acceptance and production rollout remain Telegram's decision.
