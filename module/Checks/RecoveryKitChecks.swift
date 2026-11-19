import ChannelRecoveryKit
import Foundation

private actor TestTransport: RecoveryTransport {
    enum Behavior { case normal, wrongID, wrongTimestamp, wrongEvent, failOnce, denied }
    private var behavior: Behavior
    private var requests: [RecoveryRequest] = []
    private let delay: UInt64
    init(_ behavior: Behavior = .normal, delay: UInt64 = 0) { self.behavior = behavior; self.delay = delay }
    func set(_ behavior: Behavior) { self.behavior = behavior }
    func recorded() -> [RecoveryRequest] { requests }
    func restore(_ request: RecoveryRequest) async throws -> RecoveryReceipt {
        requests.append(request)
        let count = requests.count
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        switch behavior {
        case .failOnce where count == 1: throw RecoveryFailure.network
        case .denied: throw RecoveryFailure.permissionDenied
        default: break
        }
        let original = request.post
        let post = PostReference(channelID: original.channelID,
            messageID: behavior == .wrongID ? original.messageID + 1 : original.messageID,
            originalTimestamp: behavior == .wrongTimestamp ? original.originalTimestamp + 1 : original.originalTimestamp)
        return RecoveryReceipt(post: post, deletionEventID: behavior == .wrongEvent ? request.deletionEventID + 1 : request.deletionEventID, status: .restored)
    }
}

private struct CheckFailure: Error { let message: String }
private actor DelayedTransport: RecoveryTransport {
    private var requests: [RecoveryRequest] = []
    func recorded() -> [RecoveryRequest] { requests }
    func restore(_ request: RecoveryRequest) async throws -> RecoveryReceipt {
        requests.append(request)
        if requests.count == 1 {
            // Represents an RPC that commits later and ignores local cancellation.
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
                    continuation.resume()
                }
            }
        }
        return RecoveryReceipt(post: request.post, deletionEventID: request.deletionEventID, status: .alreadyRestored)
    }
}
private func expect(_ value: Bool, _ message: String) throws {
    if !value { throw CheckFailure(message: message) }
}
private func expectFailure(_ expected: RecoveryFailure, _ action: () async throws -> RecoveryReceipt) async throws {
    do {
        _ = try await action()
        throw CheckFailure(message: "Expected \(expected)")
    } catch let error as RecoveryFailure {
        try expect(error == expected, "Expected \(expected), got \(error)")
    }
}

@main struct RecoveryKitChecks {
    static func main() async throws {
        let original = PostReference(channelID: 100, messageID: 101, originalTimestamp: 1648981800)
        var count = 0
        do {
            let coordinator = RecoveryCoordinator(transport: TestTransport())
            let receipt = try await coordinator.restore(original, deletionEventID: 1)
            try expect(receipt.post == original, "Canonical identity changed")
            count += 1
        }
        do {
            let transport = DelayedTransport()
            let coordinator = RecoveryCoordinator(transport: transport, timeoutNanoseconds: 20_000_000)
            let started = Date()
            try await expectFailure(.network) { try await coordinator.restore(original, deletionEventID: 1) }
            try expect(Date().timeIntervalSince(started) < 0.2, "Deadline waited for a non-cooperative RPC")
            count += 1
            let retry = try await coordinator.restore(original, deletionEventID: 1)
            let requests = await transport.recorded()
            try expect(retry.post == original && requests.count == 2, "Timed-out operation blocked retry")
            try expect(requests[0].requestID == requests[1].requestID, "Uncertain outcome changed retry UUID")
            count += 1
            try await Task.sleep(nanoseconds: 300_000_000)
            _ = try await coordinator.restore(original, deletionEventID: 1)
            let final = await transport.recorded()
            try expect(final.count == 3 && final.allSatisfy { $0.requestID == requests[0].requestID }, "Late reply changed subsequent recovery identity")
            count += 1
        }
        do {
            let transport = TestTransport(delay: 100_000_000)
            let coordinator = RecoveryCoordinator(transport: transport)
            try await withThrowingTaskGroup(of: RecoveryReceipt.self) { group in
                for _ in 0..<8 { group.addTask { try await coordinator.restore(original, deletionEventID: 1) } }
                for try await receipt in group { try expect(receipt.post == original, "Concurrent response changed") }
            }
            let requests = await transport.recorded()
            try expect(requests.count == 1, "Concurrent requests were not shared")
            count += 1
        }
        do {
            let transport = TestTransport(.failOnce)
            let coordinator = RecoveryCoordinator(transport: transport)
            try await expectFailure(.network) { try await coordinator.restore(original, deletionEventID: 1) }
            let first = await transport.recorded()
            try expect(first.count == 1, "Unexpected automatic retry")
            count += 1
            _ = try await coordinator.restore(original, deletionEventID: 1)
            let requests = await transport.recorded()
            try expect(requests.count == 2 && requests[0].requestID == requests[1].requestID, "Retry UUID changed")
            count += 1
        }
        do {
            let transport = TestTransport()
            let coordinator = RecoveryCoordinator(transport: transport)
            _ = try await coordinator.restore(original, deletionEventID: 1)
            _ = try await coordinator.restore(original, deletionEventID: 2)
            let requests = await transport.recorded()
            try expect(requests[0].requestID != requests[1].requestID, "New deletion reused the previous UUID")
            count += 1
        }
        do {
            let transport = TestTransport()
            let coordinator = RecoveryCoordinator(transport: transport)
            _ = try await coordinator.restore(original, deletionEventID: 1)
            await transport.set(.denied)
            try await expectFailure(.permissionDenied) { try await coordinator.restore(original, deletionEventID: 1) }
            count += 1
        }
        for behavior in [TestTransport.Behavior.wrongID, .wrongTimestamp, .wrongEvent] {
            let coordinator = RecoveryCoordinator(transport: TestTransport(behavior))
            try await expectFailure(.invalidResponse) { try await coordinator.restore(original, deletionEventID: 1) }
            count += 1
        }
        do {
            let transport = TestTransport()
            let coordinator = RecoveryCoordinator(transport: transport)
            try await expectFailure(.invalidRequest) {
                try await coordinator.restore(PostReference(channelID: 0, messageID: 1, originalTimestamp: 1), deletionEventID: 1)
            }
            let requests = await transport.recorded()
            try expect(requests.isEmpty, "Invalid identity reached the transport")
            count += 1
        }
        do {
            let coordinator = RecoveryCoordinator(transport: TestTransport())
            _ = try await coordinator.restore(original, deletionEventID: 1, requestID: "one")
            try await expectFailure(.invalidRequest) { try await coordinator.restore(original, deletionEventID: 1, requestID: "two") }
            count += 1
        }
        print("ChannelRecoveryKit: \(count) compiled behavior checks passed")
    }
}
