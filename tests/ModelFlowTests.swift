import ChannelRecoveryKit
import Foundation

// Tests view-model transitions and failed refreshes. Storage correctness is
// verified separately by real HTTP/SQLite tests, not by this scripted service.
private actor ScriptedService: RecoveryService {
    enum State { case original, deleted, restored }
    private var current: State = .original
    private var failNextState = false
    private var failOnDelete = false
    private var failOnRestore = false
    private var failOnReset = false
    private var requestIDs: [String] = []
    private var delay: UInt64 = 0

    func configure(delete: Bool = false, restore: Bool = false, reset: Bool = false, delay: UInt64 = 0) {
        failOnDelete = delete; failOnRestore = restore; failOnReset = reset
        self.delay = delay
    }
    func recorded() -> [String] { requestIDs }
    func state() async throws -> RecoverySnapshot {
        if failNextState { failNextState = false; throw APIError(code: "NETWORK_ERROR") }
        return try Self.snapshot(current)
    }
    func delete(postID: Int64) async throws -> DeleteReply {
        current = .deleted
        failNextState = failOnDelete
        return try JSONDecoder().decode(DeleteReply.self, from: Data(#"{"event_id":1,"expires_at":1795300000}"#.utf8))
    }
    func restore(post: RecoveryPost, eventID: Int64, requestID: String) async throws -> RestoreReply {
        requestIDs.append(requestID)
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        let alreadyRestored = current == .restored
        current = .restored
        failNextState = failOnRestore
        let data = try JSONSerialization.data(withJSONObject: ["deletion_event":1, "status":alreadyRestored ? "already_restored" : "restored", "post":Self.oldPost])
        return try JSONDecoder().decode(RestoreReply.self, from: data)
    }
    func reset() async throws { current = .original; failNextState = failOnReset }
    nonisolated func assetURL(_ name: String) -> URL { URL(string: "http://127.0.0.1:1/assets/\(name)")! }

    private static let oldPost: [String: Any] = ["id":101,"date":1648981800,"kind":"text","text":"Original post","reactions":128,"comments":24]
    private static let nextPost: [String: Any] = ["id":102,"date":1794897000,"kind":"photo","text":"Next post","reactions":86,"comments":12,"asset":"demo-photo.png"]
    private static func snapshot(_ state: State) throws -> RecoverySnapshot {
        let events: [[String:Any]] = state == .original ? [] : [["id":1,"post_id":101,"action":"delete","time":1795100000,"status":state == .deleted ? "deleted" : "restored","can_restore":state == .deleted,"post":oldPost]]
        let data = try JSONSerialization.data(withJSONObject: ["posts":state == .deleted ? [nextPost] : [oldPost,nextPost],"events":events,"version":state == .original ? 0 : 1,"server_time":1795100000,"retention_seconds":172800])
        return try JSONDecoder().decode(RecoverySnapshot.self, from: data)
    }
}

private struct ModelCheckFailure: Error { let message: String }
@MainActor private func check(_ condition: Bool, _ message: String) throws {
    if !condition { throw ModelCheckFailure(message: message) }
}

@main struct ModelFlowTests {
    @MainActor static func main() async throws {
        var count = 0
        do {
            let service = ScriptedService()
            let model = RecoveryViewModel()
            await model.connect(service)
            let before = model.snapshot!.posts
            await model.delete(before[0])
            try check(model.snapshot!.posts.count == 1, "Deleted post remained visible")
            let event = model.snapshot!.events[0]
            model.page = .actions
            await model.restore(event)
            try check(model.snapshot!.posts == before, "Original content/date/order changed")
            try check(model.highlightedPost == 101 && model.page == .channel && !model.busy, "Did not return to original post")
            try check(model.alertMessage == nil, "Successful path raised an error")
            count += 1
            await model.delete(before[0])
            try check(model.highlightedPost == nil, "Repeated deletion kept an obsolete highlight")
            count += 1
        }
        do {
            let service = ScriptedService()
            let model = RecoveryViewModel()
            await model.connect(service)
            await model.delete(model.snapshot!.posts[0])
            let event = model.snapshot!.events[0]
            model.page = .actions
            await service.configure(restore: true)
            await model.restore(event)
            try check(model.connectionError && model.alertMessage != nil, "Failed refresh reported success")
            try check(model.highlightedPost == nil && model.page == .actions && model.notice == nil && !model.busy, "Unverified result navigated or remained busy")
            count += 1
            await service.configure()
            await model.restore(event)
            let ids = await service.recorded()
            try check(ids.count == 2 && ids[0] == ids[1], "Retry after uncertain state changed request UUID")
            try check(model.snapshot!.posts.count == 2 && model.highlightedPost == 101 && model.alertMessage == nil, "Reconciliation failed")
            count += 1
        }
        do {
            let service = ScriptedService()
            let model = RecoveryViewModel()
            await model.connect(service)
            await service.configure(delete: true)
            await model.delete(model.snapshot!.posts[0])
            try check(model.connectionError && model.alertMessage != nil && model.notice == nil && !model.busy, "Delete refresh failure was hidden")
            count += 1
        }
        do {
            let service = ScriptedService()
            let model = RecoveryViewModel()
            await model.connect(service)
            await model.delete(model.snapshot!.posts[0])
            let event = model.snapshot!.events[0]
            await service.configure(delay: 50_000_000)
            async let first: Void = model.restore(event)
            async let second: Void = model.restore(event)
            _ = await (first, second)
            let requests = await service.recorded()
            try check(requests.count == 1 && !model.busy, "Double tap duplicated the mutation")
            count += 1
        }
        do {
            let service = ScriptedService()
            let model = RecoveryViewModel()
            await model.connect(service)
            await model.delete(model.snapshot!.posts[0])
            let resetID = model.demoResetID
            await service.configure(reset: true)
            await model.reset()
            try check(model.connectionError && model.alertMessage != nil && model.demoResetID == resetID && !model.busy, "Failed reset refresh was presented as a fresh dataset")
            count += 1
        }
        print("Recovery view model: \(count) state/failure-path checks passed")
    }
}
