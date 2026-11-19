import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext

/// Installed by the app composition root once its authenticated server transport
/// is available. Normal Recent Actions navigation resolves the current account
/// and channel through this factory; no controller call-site changes are needed.
/// Return nil for an account/channel without advertised server capability.
public enum ChannelPostRecoveryIntegration {
    public typealias ProviderFactory = (AccountContext, EnginePeer) -> ChannelPostRecoveryProvider?

    // Lock protects registration. Factories are invoked only on the UI thread,
    // outside the lock, and receive the current account instead of cached peers.
    private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        var factory: ProviderFactory?
    }
    private static let storage = Storage()

    public static func install(providerFactory: ProviderFactory?) {
        storage.lock.lock()
        storage.factory = providerFactory
        storage.lock.unlock()
    }

    static func provider(context: AccountContext, peer: EnginePeer) -> ChannelPostRecoveryProvider? {
        precondition(Thread.isMainThread)
        storage.lock.lock()
        let factory = storage.factory
        storage.lock.unlock()
        return factory?(context, peer)
    }
}

/// Integration boundary for a proposed server-supported recovery operation.
/// The current public Telegram API has no channel-post restore operation.
/// A host must provide this only after its server advertises this capability.
public protocol ChannelPostRecoveryProvider: AnyObject {
    var maximumRecoveryAge: Int32 { get }
    var strings: ChannelPostRecoveryStrings { get }

    /// True only for an event the server reports as recoverable. A cached
    /// capability is only a presentation hint; restorePost must check again.
    func canOfferRecovery(messageId: EngineMessage.Id, deletionEventId: Int64) -> Bool

    /// Revalidate authorization, the deletion event and retention on the server.
    /// Return only after canonical storage and client synchronization have committed.
    /// Never implement using sendMessage, forwardMessages or local Postbox insertion.
    /// Use a finite request timeout and return errors on the signal, never silent completion.
    func restorePost(messageId: EngineMessage.Id, deletionEventId: Int64, originalTimestamp: Int32, requestId: String) -> Signal<ChannelPostRecoveryResult, ChannelPostRecoveryError>
}

public struct ChannelPostRecoveryResult {
    public let messageId: EngineMessage.Id
    public let originalTimestamp: Int32

    public init(messageId: EngineMessage.Id, originalTimestamp: Int32) {
        self.messageId = messageId
        self.originalTimestamp = originalTimestamp
    }
}

public enum ChannelPostRecoveryError: Error {
    case unavailable
    case permissionDenied
    case expired
    case deletionChanged
    case network
    case invalidResponse
}

/// Supplied by the host's localization layer; no hard-coded language in the node.
public struct ChannelPostRecoveryStrings {
    public let restore: String
    public let confirmation: String
    public let restored: String
    public let permissionDenied: String
    public let expired: String
    public let deletionChanged: String
    public let unavailable: String
    public let network: String

    public init(restore: String, confirmation: String, restored: String, permissionDenied: String, expired: String, deletionChanged: String, unavailable: String, network: String) {
        self.restore = restore
        self.confirmation = confirmation
        self.restored = restored
        self.permissionDenied = permissionDenied
        self.expired = expired
        self.deletionChanged = deletionChanged
        self.unavailable = unavailable
        self.network = network
    }
}
