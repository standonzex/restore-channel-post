import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct RecoveryPost: Codable, Identifiable, Equatable, Sendable {
    public let id: Int64
    public let date: Int64
    public let kind: String
    public let text: String
    public let reactions: Int
    public let comments: Int
    public let asset: String?
}
public struct RecoveryEvent: Codable, Identifiable, Equatable, Sendable {
    public let id: Int64
    public let post_id: Int64
    public let action: String
    public let time: Double
    public let status: String
    public let can_restore: Bool
    public let expires_at: Double?
    public let post: RecoveryPost?
}
public struct RecoverySnapshot: Codable, Equatable, Sendable {
    public let posts: [RecoveryPost]
    public let events: [RecoveryEvent]
    public let version: Int64
    public let server_time: Double
    public let retention_seconds: Int
}
public struct RestoreReply: Codable {
    public let deletion_event: Int64
    public let status: String
    public let post: RecoveryPost
}
public struct DeleteReply: Codable {
    public let event_id: Int64
    public let expires_at: Double
}
private struct APIFailure: Decodable { let error: String }

/// Service boundary for the local reference host, including failure-path checks.
/// This interface is not a Telegram account/session transport.
public protocol RecoveryService: Sendable {
    func state() async throws -> RecoverySnapshot
    func delete(postID: Int64) async throws -> DeleteReply
    func restore(post: RecoveryPost, eventID: Int64, requestID: String) async throws -> RestoreReply
    func reset() async throws
    func assetURL(_ name: String) -> URL
}

/// Extra commands for the standalone reference host; not part of Telegram recovery.
public protocol DemoPublishingService: RecoveryService {
    func publish(kind: String, text: String, requestID: String) async throws -> RecoveryPost
    func emptyDemo() async throws
}

public struct APIError: Error, LocalizedError {
    public let code: String
    public init(code: String) { self.code = code }
    public var errorDescription: String? { code }
}

/// Transport used by the executable reference client. It has no Telegram credentials.
/// Immutable configuration and thread-safe URLSession justify unchecked Sendable.
public final class RecoveryClient: DemoPublishingService, @unchecked Sendable {
    public let baseURL: URL
    private let token: String
    private let session: URLSession
    public init(baseURL: URL, token: String) throws {
        guard baseURL.scheme == "http", baseURL.host == "127.0.0.1", baseURL.port != nil else {
            throw APIError(code: "LOCAL_SERVER_REQUIRED")
        }
        self.baseURL = baseURL
        self.token = token
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 8
        self.session = URLSession(configuration: configuration)
    }
    public func assetURL(_ name: String) -> URL { baseURL.appendingPathComponent("assets").appendingPathComponent(name) }
    public func state() async throws -> RecoverySnapshot { try await request("api/state", method: "GET", body: nil) }
    public func delete(postID: Int64) async throws -> DeleteReply {
        try await request("api/delete", method: "POST", body: ["post_id": postID])
    }
    public func restore(post: RecoveryPost, eventID: Int64, requestID: String) async throws -> RestoreReply {
        let reply: RestoreReply = try await request("api/restore", method: "POST", body: ["post_id": post.id, "deletion_event": eventID, "request_id": requestID])
        guard reply.post == post, reply.deletion_event == eventID, ["restored", "already_restored"].contains(reply.status) else {
            throw APIError(code: "INVALID_RESTORE_RESPONSE")
        }
        return reply
    }
    public func reset() async throws {
        struct Reply: Decodable { let status: String }
        let reply: Reply = try await request("api/reset", method: "POST", body: ["confirmation": "RESET_DEMO"])
        guard reply.status == "reset" else { throw APIError(code: "INVALID_RESPONSE") }
    }
    public func publish(kind: String, text: String, requestID: String) async throws -> RecoveryPost {
        struct Reply: Decodable { let post: RecoveryPost }
        let reply: Reply = try await request("api/demo/publish", method: "POST", body: ["kind": kind, "text": text, "request_id": requestID])
        guard reply.post.kind == kind, reply.post.text == text.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw APIError(code: "INVALID_RESPONSE")
        }
        return reply.post
    }
    public func emptyDemo() async throws {
        struct Reply: Decodable { let status: String }
        let reply: Reply = try await request("api/demo/empty", method: "POST", body: ["confirmation": "EMPTY_DEMO"])
        guard reply.status == "empty" else { throw APIError(code: "INVALID_RESPONSE") }
    }
    private func request<T: Decodable>(_ path: String, method: String, body: [String: Any]?) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw APIError(code: "INVALID_RESPONSE") }
        guard response.statusCode == 200 else {
            throw APIError(code: (try? JSONDecoder().decode(APIFailure.self, from: data).error) ?? "HTTP_\(response.statusCode)")
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError(code: "INVALID_RESPONSE") }
    }
}
