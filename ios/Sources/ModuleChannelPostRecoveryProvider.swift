import Foundation
import ChannelRecoveryKit
import SwiftSignalKit
import TelegramCore

/// Connects the existing Telegram Recent Actions UI to the same coordinator used
/// by the runnable demo. The host supplies its supported, authenticated transport.
/// Never attach ReferenceRecoveryTransport to messages from a live Telegram account.
public final class ModuleChannelPostRecoveryProvider: ChannelPostRecoveryProvider {
    public let maximumRecoveryAge: Int32
    public let strings: ChannelPostRecoveryStrings
    private let coordinator: RecoveryCoordinator
    private let eligibility: (EngineMessage.Id, Int64) -> Bool

    public init(transport: any RecoveryTransport, maximumRecoveryAge: Int32, strings: ChannelPostRecoveryStrings, eligibility: @escaping (EngineMessage.Id, Int64) -> Bool) {
        self.coordinator = RecoveryCoordinator(transport: transport)
        self.maximumRecoveryAge = maximumRecoveryAge
        self.strings = strings
        self.eligibility = eligibility
    }

    public func canOfferRecovery(messageId: EngineMessage.Id, deletionEventId: Int64) -> Bool {
        self.eligibility(messageId, deletionEventId)
    }

    public func restorePost(messageId: EngineMessage.Id, deletionEventId: Int64, originalTimestamp: Int32, requestId: String) -> Signal<ChannelPostRecoveryResult, ChannelPostRecoveryError> {
        let coordinator = self.coordinator
        let reference = PostReference(channelID: messageId.peerId.id._internalGetInt64Value(), messageID: Int64(messageId.id), originalTimestamp: Int64(originalTimestamp))
        return Signal { subscriber in
            let task = Task {
                do {
                    _ = try await coordinator.restore(reference, deletionEventID: deletionEventId, requestID: requestId)
                    guard !Task.isCancelled else { return }
                    subscriber.putNext(ChannelPostRecoveryResult(messageId: messageId, originalTimestamp: originalTimestamp))
                    subscriber.putCompletion()
                } catch {
                    guard !Task.isCancelled else { return }
                    let mapped: ChannelPostRecoveryError
                    switch error as? RecoveryFailure {
                    case .permissionDenied: mapped = .permissionDenied
                    case .expired: mapped = .expired
                    case .deletionChanged: mapped = .deletionChanged
                    case .invalidRequest, .invalidResponse: mapped = .invalidResponse
                    case .unavailable: mapped = .unavailable
                    case .network, .none: mapped = .network
                    }
                    subscriber.putError(mapped)
                }
            }
            return ActionDisposable { task.cancel() }
        }
    }
}
