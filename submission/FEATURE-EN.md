# Restore Channel Post

Channel administrators can undo an accidental deletion from Recent Actions. The original publication returns to its original date and position, instead of appearing as a new post.

## User flow

1. Long-press a channel post → Delete → Delete for Everyone.
2. Open the channel profile → Edit → Recent Actions.
3. Long-press the deleted publication → Restore.
4. Return to the original publication with its previous ID, timestamp and media.

Recovery is offered for the current eligible deletion event within 48 hours **of deletion**. A post published years ago can still return to its old place when its deletion is recent. One action restores it directly; there is no extra confirmation dialog after Restore.

## Behavior implemented in the reference

- Original canonical row, message ID, timestamp, media reference and stored metadata are retained.
- Current administrator rights and deletion generation are checked transactionally on the server.
- A stale confirmation cannot undo a newer deletion. Repeat and concurrent requests cannot create a new post.
- Expired originals cannot be restored; periodic cleanup removes them.
- A network timeout is uncertain. Retry retains the operation UUID; the client confirms success only after identity validation and a fresh server snapshot.
- Text, photographs and playable circular videos use the same recovery flow. The included 2022 example demonstrates restoration to an old date.

The proposed production behavior should suppress new-post notifications and keep Telegram's indexes and clients consistent. This package does not implement Telegram's actual PTS, media, reaction or discussion infrastructure. Preserved fixture counters are fields of the local record, not evidence of live engagement recovery.

## Implementation delivered

A shared dependency-free Swift module; runnable iPhone/Mac hosts; authenticated loopback HTTP service; persistent SQLite transaction/outbox reference; automated checks; a pinned patch to the existing Telegram iOS Recent Actions screen. The native adapter uses the same recovery coordinator as the reference hosts.

Rollout requires Telegram to implement and expose its own canonical server restore operation and account-aware transport/state synchronization. The full upstream client build and device integration remain unverified. See CODE-STATUS.md and INTEGRATION.md.
