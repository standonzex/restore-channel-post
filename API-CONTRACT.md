# Proposed server contract — not an existing Telegram API

The native UI deliberately depends on a provider, not on an invented public Telegram method. Telegram must assign an API method and implement it on its server before the provider can be connected.

Inputs, after authentication with the normal Telegram session:

- Channel and canonical original message ID.
- Deletion event ID (the generation to be undone).
- Request UUID, stable across retries.

The request must not contain a new body, publication date or message ID to assign. Server-side canonical data is the sole source for restoration. Actor identity comes from the authenticated session, never from a body field.

Requirements:

1. Recheck current admin permissions, channel access, existence and eligibility of that deletion generation, retention expiry and moderation restrictions.
2. Lock / compare-and-swap the canonical post. Restore the existing object, not a clone. Persist the recovery audit event and synchronization event in the same transaction.
3. Return the original ID, original timestamp and the validated deletion event ID only after that transaction commits. Returning success must also ensure the restored object can be fetched by its canonical ID. The native provider must feed appropriate authoritative updates to the existing state manager; it must not manufacture local history.
4. Publish ordered channel updates with a valid PTS strategy to all authorized clients, including offline clients. Refetches, shared media, search indexes, message links and tombstones must converge. Do not generate a new-post notification or move the dialog to the top solely for this restoration.
5. A request for an already restored generation may return its canonical original. A stale request for an earlier deletion must never undo a newer deletion. Use UUID and generation together, not just message ID.
6. Give the client eligibility information for each recoverable event. Do not expose original deleted content to ordinary members while it is deleted.

Error mapping to the native provider:

| Reference error | Native error |
|---|---|
| ADMIN_REQUIRED | permissionDenied |
| RECOVERY_EXPIRED | expired |
| DELETION_CHANGED | deletionChanged |
| POST_NOT_AVAILABLE / unsupported | unavailable |
| transport timeout / connection failure | network |
| wrong canonical ID/date or malformed reply | invalidResponse |

The SQLite outbox demonstrates atomic publication of change intent. It is not Telegram's PTS implementation, its media storage or its live discussion/reaction database. Those integrations require Telegram's own implementation and tests.


The reference HTTP restore response now includes `deletion_event`. `RecoveryClient` validates it, and `RecoveryCoordinator` validates the identity, date and deletion generation again at the integration boundary.

## Standalone host presentation helpers (1.5)

These are local-only demo commands, not proposed public Telegram methods. POST `/api/demo/empty` requires `{"confirmation":"EMPTY_DEMO"}` and current bound admin rights. POST `/api/demo/publish` takes only `kind` (`text` or `video_note`), `text` and `request_id`; canonical ID/time/media are assigned by the server. A retained request fingerprint binds retries to the same content and never restores a deleted publication. Message IDs remain monotonic across explicit emptying. The iPhone runner's `--start-empty` option initializes only a fresh database; existing state is untouched.
