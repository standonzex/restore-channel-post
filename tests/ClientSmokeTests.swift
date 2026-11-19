import ChannelRecoveryKit
import Foundation

@main struct ClientSmokeTests {
    static func main() async throws {
        let env = ProcessInfo.processInfo.environment
        let baseURL = URL(string: env["RECOVERY_TEST_URL"]!)!
        let token = env["RECOVERY_TEST_TOKEN"]!
        let client = try RecoveryClient(baseURL: baseURL, token: token)
        let initial = try await client.state()
        precondition(initial.posts.count == 4)
        let original = initial.posts[0]
        _ = try await client.delete(postID: original.id)
        let removed = try await client.state()
        precondition(!removed.posts.contains(original))
        let event = removed.events.first!
        precondition(event.can_restore && event.post == original)
        let coordinator = RecoveryCoordinator(transport: ReferenceRecoveryTransport(client: client))
        let reference = PostReference(channelID: 100, messageID: original.id, originalTimestamp: original.date)
        let result = try await coordinator.restore(reference, deletionEventID: event.id, requestID: "native-smoke-test")
        precondition(result.status == .restored && result.post == reference)
        let duplicate = try await client.restore(post: original, eventID: event.id, requestID: "native-smoke-test")
        precondition(duplicate.status == "restored")
        let after = try await client.state()
        precondition(after.posts == initial.posts)
        precondition(after.events.count == 2)
        // Exercise the same native transport for photo and circular-video posts.
        for mediaPost in initial.posts.filter({ $0.kind != "text" }) {
            let deletion = try await client.delete(postID: mediaPost.id)
            let state = try await client.state()
            precondition(!state.posts.contains(mediaPost))
            precondition(state.events.contains { $0.id == deletion.event_id && $0.post == mediaPost && $0.can_restore })
            let mediaReference = PostReference(channelID: 100, messageID: mediaPost.id, originalTimestamp: mediaPost.date)
            _ = try await coordinator.restore(mediaReference, deletionEventID: deletion.event_id)
            let restored = try await client.state()
            precondition(restored.posts == initial.posts)
        }
        // A second deletion of the same original has a new generation.
        let secondDeletion = try await client.delete(postID: original.id)
        precondition(secondDeletion.event_id != event.id)
        do {
            _ = try await coordinator.restore(reference, deletionEventID: event.id, requestID: "native-smoke-test")
            fatalError("An old generation restored a new deletion")
        } catch let error as RecoveryFailure { precondition(error == .deletionChanged) }
        _ = try await coordinator.restore(reference, deletionEventID: secondDeletion.event_id)
        let finalState = try await client.state()
        precondition(finalState.posts == initial.posts)
        let unauthenticated = try RecoveryClient(baseURL: baseURL, token: "wrong")
        do { _ = try await unauthenticated.state(); fatalError("Unauthorized client succeeded") }
        catch let error as APIError { precondition(error.code == "UNAUTHORIZED") }
        try await client.emptyDemo()
        let empty = try await client.state()
        precondition(empty.posts.isEmpty && empty.events.isEmpty)
        let typed = try await client.publish(kind: "text", text: "первая запись 🤍", requestID: "compose-text")
        let circle = try await client.publish(kind: "video_note", text: "", requestID: "compose-circle")
        let repeatedCircle = try await client.publish(kind: "video_note", text: "", requestID: "compose-circle")
        precondition(repeatedCircle == circle)
        let sent = try await client.state()
        precondition(sent.posts == [typed, circle])
        let circleDeletion = try await client.delete(postID: circle.id)
        let publishedCoordinator = RecoveryCoordinator(transport: ReferenceRecoveryTransport(client: client))
        _ = try await publishedCoordinator.restore(PostReference(channelID: 100, messageID: circle.id, originalTimestamp: circle.date), deletionEventID: circleDeletion.event_id)
        let afterCreatedRestore = try await client.state()
        precondition(afterCreatedRestore.posts == sent.posts)
        try await client.reset()
        let reset = try await client.state()
        precondition(reset.posts == initial.posts && reset.events.isEmpty)
        print("Swift URLSession → HTTP → SQLite: text/photo/video, canonical order and repeated-deletion recovery passed")
    }
}
