import ChannelRecoveryKit
import Foundation
import SwiftUI

enum RecoveryPage { case channel, settings, actions }

@MainActor final class RecoveryViewModel: ObservableObject {
    @Published var snapshot: RecoverySnapshot?
    @Published var page: RecoveryPage = .channel
    @Published var busy = false
    @Published var connectionError = false
    @Published var alertMessage: String?
    @Published var highlightedPost: Int64?
    @Published var demoResetID = UUID()
    @Published var notice: String?
    @Published var english = false
    private(set) var client: (any RecoveryService)?
    private var coordinator: RecoveryCoordinator?
    private var refreshSequence = 0
    private var starting = false
    private var pendingPublication: (kind: String, text: String, requestID: String)?
    #if os(macOS)
    let host = DemoHost()
    #endif

    func start() async {
        guard !starting else { return }
        starting = true
        defer { starting = false }
        if let existing = client {
            do {
                snapshot = try await existing.state()
                connectionError = false
                return
            } catch {
                #if os(macOS)
                host.stop()
                client = nil
                #else
                connectionError = true
                return
                #endif
            }
        }
        if client == nil {
            do {
                #if os(macOS)
                client = try await host.start()
                #else
                throw APIError(code: "CONFIGURE_REFERENCE_ENDPOINT")
                #endif
            } catch {
                connectionError = true
                alertMessage = l("Не удалось запустить локальный сервер. Проверьте установку Python 3.", "Could not start the local server. Check that Python 3 is installed.")
                return
            }
        }
        if let client { coordinator = RecoveryCoordinator(transport: ReferenceRecoveryTransport(client: client)) }
        await refresh()
    }
    func connect(_ client: any RecoveryService) async {
        self.client = client
        coordinator = RecoveryCoordinator(transport: ReferenceRecoveryTransport(client: client))
        await refresh()
    }
    @discardableResult func refresh() async -> Bool {
        guard let client else { return false }
        refreshSequence += 1
        let sequence = refreshSequence
        do {
            let next = try await client.state()
            guard sequence == refreshSequence else { return false }
            snapshot = next
            connectionError = false
            return true
        } catch {
            if sequence == refreshSequence { connectionError = true }
            return false
        }
    }
    func poll() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled { break }
            if !busy { await refresh() }
        }
    }
    func delete(_ post: RecoveryPost) async {
        guard let client, !busy else { return }
        busy = true
        notice = nil
        alertMessage = nil
        defer { busy = false }
        do {
            _ = try await client.delete(postID: post.id)
            if highlightedPost == post.id { highlightedPost = nil }
            guard await refresh() else {
                alertMessage = l("Удаление подтверждено сервером, но лента не обновилась. Обновите канал перед следующим действием.", "Deletion was confirmed, but the channel could not refresh. Refresh it before the next action.")
                return
            }
            notice = l("Пост удалён. Его можно вернуть в недавних действиях.", "Post deleted. You can restore it in Recent Actions.")
        } catch {
            await refresh()
            alertMessage = errorText(error)
        }
    }
    func restore(_ event: RecoveryEvent) async {
        guard let coordinator, let post = event.post, !busy, event.action == "delete", event.can_restore else { return }
        busy = true
        notice = nil
        alertMessage = nil
        defer { busy = false }
        do {
            _ = try await coordinator.restore(PostReference(channelID: 100, messageID: post.id, originalTimestamp: post.date), deletionEventID: event.id)
            let refreshed = await refresh()
            guard refreshed, snapshot?.posts.contains(post) == true else {
                alertMessage = l("Сервер подтвердил операцию. Обновите ленту, чтобы проверить результат.", "The server confirmed the operation. Refresh the channel to verify the result.")
                return
            }
            page = .channel
            highlightedPost = post.id
            notice = l("Пост восстановлен с исходной датой.", "Post restored with its original date.")
        } catch {
            await refresh()
            alertMessage = errorText(error)
        }
    }
    func reset() async {
        guard let client, !busy else { return }
        busy = true
        notice = nil
        alertMessage = nil
        defer { busy = false }
        do {
            try await client.reset()
            pendingPublication = nil
            coordinator = RecoveryCoordinator(transport: ReferenceRecoveryTransport(client: client))
            highlightedPost = nil; notice = nil; page = .channel
            guard await refresh() else {
                alertMessage = l("Сброс подтверждён сервером, но данные не обновились. Повторите обновление канала.", "Reset was confirmed, but the data could not refresh. Refresh the channel again.")
                return
            }
            demoResetID = UUID()
        } catch { alertMessage = errorText(error) }
    }
    /// Publishing is only a reference-host presentation feature. Restore uses the
    /// unchanged shared coordinator and the canonical server record.
    @discardableResult func publish(kind: String, text: String) async -> Bool {
        guard let publisher = client as? any DemoPublishingService, !busy else { return false }
        busy = true; notice = nil; alertMessage = nil
        defer { busy = false }
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if pendingPublication?.kind != kind || pendingPublication?.text != cleanText {
            pendingPublication = (kind, cleanText, UUID().uuidString)
        }
        guard let pending = pendingPublication else { return false }
        do {
            let post = try await publisher.publish(kind: kind, text: cleanText, requestID: pending.requestID)
            guard await refresh(), snapshot?.posts.contains(post) == true else {
                alertMessage = l("Отправка подтверждена, но канал не обновился. Повторите обновление.", "Publication confirmed, but history could not refresh. Refresh it again.")
                return false
            }
            pendingPublication = nil
            highlightedPost = nil
            return true
        } catch { alertMessage = errorText(error); return false }
    }
    func emptyDemo() async {
        guard let publisher = client as? any DemoPublishingService, !busy else { return }
        busy = true; notice = nil; alertMessage = nil
        defer { busy = false }
        do {
            try await publisher.emptyDemo()
            guard await refresh(), snapshot?.posts.isEmpty == true, snapshot?.events.isEmpty == true else {
                alertMessage = l("Очистка подтверждена, но данные не обновились.", "Clear confirmed, but history could not refresh.")
                return
            }
            pendingPublication = nil
            coordinator = RecoveryCoordinator(transport: ReferenceRecoveryTransport(client: publisher))
            highlightedPost = nil; page = .channel; demoResetID = UUID()
        } catch { alertMessage = errorText(error) }
    }
    func l(_ ru: String, _ en: String) -> String { english ? en : ru }
    func date(_ timestamp: Int64, time: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: english ? "en_GB" : "ru_RU")
        formatter.timeZone = TimeZone(secondsFromGMT: 7 * 3600)
        formatter.dateFormat = time ? "HH:mm" : "d MMMM yyyy"
        return formatter.string(from: Date(timeIntervalSince1970: Double(timestamp)))
    }
    private func errorText(_ error: Error) -> String {
        switch (error as? APIError)?.code ?? (error as? RecoveryFailure)?.code {
        case "ADMIN_REQUIRED": return l("Прав для восстановления больше нет. Обратитесь к владельцу канала.", "You no longer have permission to restore posts. Contact the channel owner.")
        case "RECOVERY_EXPIRED": return l("Срок восстановления истёк.", "The recovery period has expired.")
        case "DELETION_CHANGED": return l("Этот пост был удалён повторно. Откройте новое событие в журнале.", "This post was deleted again. Open its latest deletion event.")
        case "POST_NOT_AVAILABLE": return l("Публикация больше недоступна для этой операции.", "This post is no longer available for this operation.")
        case "INVALID_RESTORE_RESPONSE": return l("Ответ сервера не совпал с исходной публикацией. Восстановление не подтверждено.", "The response did not match the original post. Restoration was not verified.")
        default: return l("Нет подтверждения от сервера. Обновите журнал перед повторной попыткой.", "No confirmation from the server. Refresh Recent Actions before retrying.")
        }
    }
}
