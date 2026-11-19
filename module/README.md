# ChannelRecoveryKit

Framework-independent Swift package for a server-supported channel-post recovery operation. The runnable reference app uses this module; the Telegram Recent Actions adapter uses the same coordinator.

- `PostReference`: channel, canonical message ID and original publication timestamp.
- `RecoveryCoordinator`: validates identity, shares concurrent in-flight work, retains one UUID for retries of a deletion generation, and validates the receipt. A 15-second default deadline returns an uncertain network result even if the transport ignores cancellation; retries retain the UUID. It does not cache completed successes or bypass current server authorization.
- `RecoveryTransport`: host integration boundary. A production host must authenticate, recheck rights/retention/generation, commit canonical storage and standard synchronization, then return the canonical receipt.
- `ReferenceRecoveryTransport`: loopback-only transport for the fictional reference dataset. It must not be attached to live Telegram accounts.

## Build and verify

```sh
swift build --package-path module -c release --product ChannelRecoveryKit
swift run --package-path module RecoveryKitChecks
```

The check executable needs only Swift Command Line Tools, not XCTest or a paid developer account. It executes 14 behavior checks, including concurrency, retries, invalid receipts and revoked rights. iOS compilation still requires an iOS SDK from Xcode.

## Add to a Swift package

```swift
.package(path: "path/to/module")
// In the consuming target's dependencies:
.product(name: "ChannelRecoveryKit", package: "ChannelRecoveryKit")
```

Then `import ChannelRecoveryKit` and create a `RecoveryCoordinator(transport: yourAuthenticatedTransport)`. The coordinator never sends a replacement message or assigns a new timestamp.

For Telegram-iOS/Bazel, the integration patch contains `submodules/ChannelRecoveryKit` with the production coordinator and its Bazel target. The reference HTTP transport remains outside the production integration target.

The reference host also uses the injectable RecoveryService boundary to verify UI state after mutations. A successful RPC alone does not navigate to an old cached post: a fresh authoritative channel snapshot is required.
