# Verification report — 1.8 / 19 November 2026

| Check | Scope |
|---|---|
| Python server and HTTP | 37 checks |
| Shared ChannelRecoveryKit | 14 compiled behavior checks |
| Recovery-window policy | 6 boundary checks |
| View-model state/failure behavior | 7 checks |
| Native URLSession integration | Real Swift–HTTP–SQLite, text/photo/video, retries and repeated deletion |
| Mac host | Release build with warnings as errors; ad-hoc signature |
| iPhone host | Simulator build with warnings as errors; ad-hoc signature |
| Native patch | Clean pinned-base application, complete-source consistency, reverse application and six Swift syntax checks |

64 behavior checks are separate from integration, builds and patch checks. The final code-only release is validated from a fresh extraction; its actual command output is in the delivered VALIDATION.log. Optional GitHub Actions configuration is included; no remote CI run is claimed.

## Covered behavior

Canonical identity/date/order/metadata, recent deletion of an old publication, concurrency, stable retry UUID, current rights, changed deletion generations, exact expiry, restart, rollback, cleanup, request/host/origin validation, byte-range video serving, coordinator timeout/late response and authoritative-refresh failure. Publishing helpers cover an empty channel, idempotent text/video sends, content-bound request identity and monotonically allocated IDs. Replaying a send does not resurrect a deleted post.

## Manual evidence already obtained

On iPhone 17 / iOS 26.5, text, photo and playable video messages were deleted and restored through the channel profile/Edit/Recent Actions path. Old examples retained 3 April 2022 / 17:30 and original neighbor order. Deletion persisted after a complete server/app restart. The empty-channel flow sent text and a circle, deleted the circle, restored the same canonical object and played it again. Short camera taps sent nothing; slide-left cancelled; hold/release published the prepared fixture. The normal full-screen and compact presentation paths were checked. 1.8 retains the canonical restore transaction/coordinator and fixtures, includes the current admin-log layout/search/filter refinements and adds accurate media-duration display. A regression check verifies channel setup events are informational and do not act like deleted posts. The latest iPhone path is checked again for this handoff.

## Exact limits

The hosts use synthetic data and a private authenticated loopback backend. No live Telegram account/channel is connected. Stored counters do not verify real Telegram engagement. Camera recording is simulated with a prepared clip; unrelated client controls are limited scaffolding. The source includes a small internal video fixture, but not a competition presentation video.

The optional native Telegram-iOS patch is not fully type-checked, built or run. Pinned upstream commit: 24638bc69bd083981b178dd1e7f921eebbf7fc46. Its required Xcode 27.1/macOS 27 differs from the verified Xcode 26.6/macOS 26.5.2 host. Production provider registration, authenticated Telegram transport, canonical server operation, updates/indexes and discussion/media lifecycle remain Telegram integration work. Syntax/application checks do not replace full target validation.

Databases, live credentials, Again bot files, personal screenshots and presentation renders are excluded by the source allowlist. No publication to GitHub or submission to reviewers has been performed.
