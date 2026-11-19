import Foundation

/// Canonical identity selected from a server-provided deletion event.
public struct PostReference: Hashable, Sendable {
    public let channelID: Int64
    public let messageID: Int64
    public let originalTimestamp: Int64
    public init(channelID: Int64, messageID: Int64, originalTimestamp: Int64) {
        self.channelID = channelID
        self.messageID = messageID
        self.originalTimestamp = originalTimestamp
    }
}

public struct RecoveryRequest: Sendable {
    public let post: PostReference
    public let deletionEventID: Int64
    public let requestID: String
    public init(post: PostReference, deletionEventID: Int64, requestID: String) {
        self.post = post
        self.deletionEventID = deletionEventID
        self.requestID = requestID
    }
}

public struct RecoveryReceipt: Equatable, Sendable {
    public enum Status: String, Sendable { case restored; case alreadyRestored = "already_restored" }
    public let post: PostReference
    public let deletionEventID: Int64
    public let status: Status
    public init(post: PostReference, deletionEventID: Int64, status: Status) {
        self.post = post
        self.deletionEventID = deletionEventID
        self.status = status
    }
}

public enum RecoveryFailure: Error, Equatable, Sendable {
    case invalidRequest, invalidResponse, unavailable, permissionDenied, expired, deletionChanged, network
    public var code: String {
        switch self {
        case .invalidRequest: return "INVALID_REQUEST"
        case .invalidResponse: return "INVALID_RESTORE_RESPONSE"
        case .unavailable: return "POST_NOT_AVAILABLE"
        case .permissionDenied: return "ADMIN_REQUIRED"
        case .expired: return "RECOVERY_EXPIRED"
        case .deletionChanged: return "DELETION_CHANGED"
        case .network: return "NETWORK_ERROR"
        }
    }
}

/// Production hosts implement this using their authenticated service and standard
/// state synchronization. The reference transport uses only the local demo server.
public protocol RecoveryTransport: Sendable {
    func restore(_ request: RecoveryRequest) async throws -> RecoveryReceipt
}

/// Framework-independent recovery coordinator, shared by the running demo and
/// the Telegram integration adapter. Never generates a new message or a timestamp.
public actor RecoveryCoordinator {
    private struct Key: Hashable { let post: PostReference; let event: Int64 }
    private struct Operation { let id: UUID; let task: Task<RecoveryReceipt, Error> }
    private let transport: any RecoveryTransport
    private let timeoutNanoseconds: UInt64
    private var requests: [Key: String] = [:]
    private var pending: [Key: Operation] = [:]

    public init(transport: any RecoveryTransport, timeoutNanoseconds: UInt64 = 15_000_000_000) {
        precondition(timeoutNanoseconds > 0)
        self.transport = transport
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    /// Reuses a UUID for retries of one deletion generation, and shares concurrent
    /// in-flight work. Completed successes are not cached: later calls must check
    /// current permissions and deletion generation on the server again.
    public func restore(_ post: PostReference, deletionEventID: Int64, requestID: String? = nil) async throws -> RecoveryReceipt {
        guard post.channelID != 0, post.messageID > 0, post.originalTimestamp > 0, deletionEventID > 0 else {
            throw RecoveryFailure.invalidRequest
        }
        let key = Key(post: post, event: deletionEventID)
        let id = requestID ?? requests[key] ?? UUID().uuidString
        guard !id.isEmpty, id.utf8.count <= 128, requests[key] == nil || requests[key] == id else {
            throw RecoveryFailure.invalidRequest
        }
        requests[key] = id
        let operation: Operation
        if let existing = pending[key] {
            operation = existing
        } else {
            let transport = self.transport
            let timeout = self.timeoutNanoseconds
            let request = RecoveryRequest(post: post, deletionEventID: deletionEventID, requestID: id)
            operation = Operation(id: UUID(), task: Task {
                let receipt = try await Self.perform(request, transport: transport, timeout: timeout)
                guard receipt.post == post, receipt.deletionEventID == deletionEventID else {
                    throw RecoveryFailure.invalidResponse
                }
                return receipt
            })
            pending[key] = operation
        }
        defer {
            if pending[key]?.id == operation.id { pending[key] = nil }
        }
        // Cancelling a waiter cannot roll back a server transaction or cancel a
        // shared request needed by another waiter. Hosts must refresh to reconcile.
        return try await operation.task.value
    }

    /// A task group would wait forever for a transport that ignores cancellation.
    /// This stream races the response against a deadline without waiting for that
    /// transport to stop. A timeout is uncertain, never a rollback: retry the UUID.
    private static func perform(_ request: RecoveryRequest, transport: any RecoveryTransport, timeout: UInt64) async throws -> RecoveryReceipt {
        let responses = AsyncThrowingStream<RecoveryReceipt, Error> { continuation in
            let work = Task {
                do {
                    continuation.yield(try await transport.restore(request))
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            let deadline = Task {
                do {
                    try await Task.sleep(nanoseconds: timeout)
                    continuation.finish(throwing: RecoveryFailure.network)
                } catch { /* The response won; the deadline is no longer needed. */ }
            }
            continuation.onTermination = { @Sendable _ in
                work.cancel()
                deadline.cancel()
            }
        }
        for try await receipt in responses { return receipt }
        throw RecoveryFailure.invalidResponse
    }
}
