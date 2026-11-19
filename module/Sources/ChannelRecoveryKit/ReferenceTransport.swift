import Foundation

/// Uses the runnable reference API. It must not be installed as a transport for
/// live Telegram messages: its channel and media belong to a synthetic dataset.
public struct ReferenceRecoveryTransport: RecoveryTransport {
    private let client: any RecoveryService
    private let channelID: Int64
    public init(client: any RecoveryService, channelID: Int64 = 100) {
        self.client = client
        self.channelID = channelID
    }
    public func restore(_ request: RecoveryRequest) async throws -> RecoveryReceipt {
        guard request.post.channelID == channelID else { throw RecoveryFailure.unavailable }
        do {
            let snapshot = try await client.state()
            guard let event = snapshot.events.first(where: { $0.id == request.deletionEventID && $0.post_id == request.post.messageID }) else { throw RecoveryFailure.unavailable }
            if event.status == "expired" { throw RecoveryFailure.expired }
            if event.status == "superseded" { throw RecoveryFailure.deletionChanged }
            guard let original = event.post else { throw RecoveryFailure.unavailable }
            guard original.date == request.post.originalTimestamp else { throw RecoveryFailure.invalidResponse }
            let reply = try await client.restore(post: original, eventID: request.deletionEventID, requestID: request.requestID)
            guard let status = RecoveryReceipt.Status(rawValue: reply.status) else { throw RecoveryFailure.invalidResponse }
            return RecoveryReceipt(post: PostReference(channelID: channelID, messageID: reply.post.id, originalTimestamp: reply.post.date), deletionEventID: reply.deletion_event, status: status)
        } catch let failure as RecoveryFailure { throw failure }
        catch let failure as APIError {
            switch failure.code {
            case "ADMIN_REQUIRED": throw RecoveryFailure.permissionDenied
            case "RECOVERY_EXPIRED": throw RecoveryFailure.expired
            case "DELETION_CHANGED": throw RecoveryFailure.deletionChanged
            case "POST_NOT_AVAILABLE": throw RecoveryFailure.unavailable
            case "INVALID_REQUEST", "REQUEST_ID_REUSED": throw RecoveryFailure.invalidRequest
            case "INVALID_RESTORE_RESPONSE", "INVALID_RESPONSE": throw RecoveryFailure.invalidResponse
            default: throw RecoveryFailure.network
            }
        } catch { throw RecoveryFailure.network }
    }
}
