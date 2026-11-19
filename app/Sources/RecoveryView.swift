import ChannelRecoveryKit
import SwiftUI
import AVKit

private let accent = Color(red: 0.13, green: 0.56, blue: 0.88)
private let canvas = Color(red: 0.91, green: 0.94, blue: 0.95)

struct RecoveryView: View {
    @ObservedObject var model: RecoveryViewModel
    @State private var pendingDelete: RecoveryPost?
    @State private var pendingRestore: RecoveryEvent?
    @State private var resetPrompt = false
    @State private var showingProof = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                #if os(macOS)
                sidebar
                Divider()
                #endif
                VStack(spacing: 0) {
                    header
                    if model.connectionError {
                        HStack {
                            Image(systemName: "wifi.exclamationmark")
                            Text(model.l("Сервер недоступен · показано последнее состояние", "Server offline · showing the last known state"))
                            Spacer()
                            Button(model.l("Повторить", "Retry")) { Task { await model.start() } }
                        }.font(.caption).padding(10).background(Color.orange.opacity(0.12))
                    }
                    if model.snapshot == nil {
                        Spacer(); ProgressView(); Text(model.l("Подключение…", "Connecting…")).foregroundStyle(.secondary); Spacer()
                    } else {
                        switch model.page {
                        case .channel: channel
                        case .settings: settings
                        case .actions: actions
                        }
                    }
                }.frame(maxWidth: .infinity)
            }
            HStack(spacing: 8) {
                Circle().fill(model.connectionError ? .orange : .green).frame(width: 6, height: 6)
                Text(model.l("Предложение функции Telegram · локальный сервер · вымышленные публикации", "Telegram feature proposal · local reference server · fictional posts"))
                Spacer()
                Button(model.english ? "RU" : "EN") { model.english.toggle() }.buttonStyle(.plain).foregroundStyle(accent)
                Button { showingProof.toggle() } label: { Image(systemName: "info.circle") }.buttonStyle(.plain)
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.vertical, 9).background(.white)
        }
        #if os(macOS)
        .frame(minWidth: 900, idealWidth: 1020, minHeight: 720, idealHeight: 780)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
        .tint(accent)
        .alert(model.l("Удалить пост?", "Delete post?"), isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button(model.l("Отмена", "Cancel"), role: .cancel) { pendingDelete = nil }
            Button(model.l("Удалить", "Delete"), role: .destructive) {
                if let post = pendingDelete { Task { await model.delete(post) } }; pendingDelete = nil
            }
        } message: {
            Text(model.l("Пост исчезнет из канала. В течение 48 часов его можно вернуть из недавних действий.", "The post will disappear from the channel. You can restore it from Recent Actions within 48 hours."))
        }
        .alert(model.l("Восстановить пост?", "Restore post?"), isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } })) {
            Button(model.l("Отмена", "Cancel"), role: .cancel) { pendingRestore = nil }
            Button(model.l("Восстановить", "Restore")) {
                if let event = pendingRestore { Task { await model.restore(event) } }; pendingRestore = nil
            }
        } message: {
            if let post = pendingRestore?.post {
                Text(model.l("Пост вернётся на прежнее место в ленте с датой \(model.date(post.date)).", "The post will return to its original position, dated \(model.date(post.date))."))
            }
        }
        .alert(model.l("Начать показ заново?", "Reset the demo?"), isPresented: $resetPrompt) {
            Button(model.l("Отмена", "Cancel"), role: .cancel) {}
            Button(model.l("Сбросить", "Reset")) { Task { await model.reset() } }
        } message: { Text(model.l("Сбросится только локальная демонстрационная база.", "Only the local reference database will be reset.")) }
        .alert(model.l("Не удалось завершить действие", "Action could not be completed"), isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })) {
            Button("OK") { model.alertMessage = nil }
        } message: { Text(model.alertMessage ?? "") }
        .sheet(isPresented: $showingProof) { proof }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("Channel Recovery").font(.system(size: 19, weight: .semibold)); Spacer() }.padding(22)
            Text(model.l("КАНАЛЫ", "CHANNELS")).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 22).padding(.bottom, 12)
            Button { model.page = .channel } label: {
                HStack(spacing: 12) {
                    avatar(size: 44)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Studio Notes").font(.system(size: 14, weight: .semibold))
                        Text(model.l("Личный дневник студии", "A little studio journal")).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(14).background(accent.opacity(0.10)).clipShape(RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain).padding(.horizontal, 10)
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Label(model.l("Вы — администратор", "You are an administrator"), systemImage: "person.badge.shield.checkmark").font(.caption).foregroundStyle(.secondary)
                Button(model.l("Начать показ заново", "Reset demo")) { resetPrompt = true }.font(.caption).buttonStyle(.plain).foregroundStyle(accent).disabled(model.busy)
            }.padding(22)
        }.frame(width: 264).frame(maxHeight: .infinity).background(.white)
    }
    private var header: some View {
        HStack(spacing: 12) {
            if model.page != .channel {
                Button { model.page = model.page == .actions ? .settings : .channel } label: { Image(systemName: "chevron.left").font(.system(size: 18, weight: .medium)).frame(width: 26, height: 32) }.buttonStyle(.plain).foregroundStyle(accent).accessibilityLabel(model.l("Назад", "Back"))
            }
            if model.page == .channel { avatar(size: 36) }
            VStack(alignment: .leading, spacing: 3) {
                Text(model.page == .channel ? "Studio Notes" : model.page == .settings ? model.l("Управление каналом", "Manage Channel") : model.l("Недавние действия", "Recent Actions")).font(.system(size: 16, weight: .semibold))
                Text(model.page == .channel ? model.l("канал · демонстрация", "channel · demo") : "Studio Notes").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if model.busy { ProgressView().controlSize(.small) }
            Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise").frame(width: 28, height: 28) }.buttonStyle(.plain).foregroundStyle(accent).accessibilityLabel(model.l("Обновить", "Refresh"))
            #if os(iOS)
            Button { resetPrompt = true } label: { Image(systemName: "arrow.counterclockwise").frame(width: 28, height: 28) }.buttonStyle(.plain).foregroundStyle(accent).accessibilityLabel(model.l("Начать показ заново", "Reset demo"))
            #endif
            if model.page == .channel {
                Button { model.page = .settings } label: { Image(systemName: "gearshape").frame(width: 28, height: 28) }.buttonStyle(.plain).foregroundStyle(accent).accessibilityLabel(model.l("Настройки канала", "Channel settings"))
            }
        }.padding(.horizontal, 20).frame(height: 68).background(.white)
    }
    private var channel: some View {
        VStack(spacing: 0) {
            if let notice = model.notice {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(accent)
                    Text(notice).font(.system(size: 12))
                    Spacer()
                    Button { model.notice = nil } label: { Image(systemName: "xmark").font(.caption) }.buttonStyle(.plain)
                }.padding(12).background(accent.opacity(0.08))
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 18) {
                        ForEach(model.snapshot?.posts ?? []) { post in
                            VStack(spacing: 9) {
                                Text(model.date(post.date)).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.black.opacity(0.5)).padding(.horizontal, 12).padding(.vertical, 5).background(.white.opacity(0.65)).clipShape(Capsule())
                                PostCard(post: post, model: model, highlighted: model.highlightedPost == post.id, onDelete: { pendingDelete = post })
                            }.id(post.id)
                        }
                        if model.snapshot?.posts.isEmpty == true {
                            VStack(spacing: 10) { Image(systemName: "text.bubble").font(.largeTitle); Text(model.l("В канале пока нет постов", "No posts in this channel")); Button(model.l("Недавние действия", "Recent Actions")) { model.page = .actions } }.foregroundStyle(.secondary).padding(60)
                        }
                    }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
                }.background(canvas)
                .onAppear { scrollToRestored(proxy) }
                .onReceive(model.$highlightedPost) { _ in scrollToRestored(proxy) }
            }.id(model.demoResetID)
        }
    }
    private func scrollToRestored(_ proxy: ScrollViewProxy) {
        if let id = model.highlightedPost {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { proxy.scrollTo(id, anchor: .center) }
        }
    }
    private var settings: some View {
        ScrollView {
            VStack(spacing: 26) {
                avatar(size: 76).padding(.top, 30)
                VStack(spacing: 5) { Text("Studio Notes").font(.system(size: 24, weight: .semibold)); Text(model.l("Канал", "Channel")).foregroundStyle(.secondary) }
                VStack(alignment: .leading, spacing: 0) {
                    Button { model.page = .actions } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "clock.arrow.circlepath").font(.system(size: 21)).foregroundStyle(accent)
                            VStack(alignment: .leading, spacing: 5) { Text(model.l("Недавние действия", "Recent Actions")).font(.system(size: 15)); Text(model.l("Действия администраторов и удалённые посты", "Administrator actions and deleted posts")).font(.system(size: 11)).foregroundStyle(.secondary) }
                            Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }.padding(18)
                    }.buttonStyle(.plain)
                }.background(.white).clipShape(RoundedRectangle(cornerRadius: 12))
                Text(model.l("Удалённые посты можно восстановить в течение 48 часов. Они вернутся с исходной датой публикации.", "Deleted posts can be restored within 48 hours. Their original publication date is preserved.")).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(30).frame(maxWidth: 550).frame(maxWidth: .infinity)
        }.background(canvas)
    }
    private var actions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(accent)
                    Text(model.l("Удалённые посты доступны для восстановления 48 часов.", "Deleted posts are recoverable for 48 hours.")).font(.system(size: 12)).foregroundStyle(.secondary)
                }.padding(.vertical, 6)
                if model.snapshot?.events.isEmpty == true {
                    VStack(spacing: 12) {
                        Image(systemName: "clock").font(.system(size: 38, weight: .light)).foregroundStyle(accent)
                        Text(model.l("Действий пока нет", "No recent actions")).font(.headline)
                        Text(model.l("Удалите пост в канале, чтобы проверить восстановление.", "Delete a channel post to try restoring it.")).font(.caption).foregroundStyle(.secondary)
                        Button(model.l("Открыть канал", "Open channel")) { model.page = .channel }.buttonStyle(.bordered)
                    }.frame(maxWidth: .infinity).padding(.vertical, 60)
                }
                ForEach(model.snapshot?.events ?? []) { event in
                    VStack(alignment: .leading, spacing: 13) {
                        HStack {
                            Image(systemName: event.action == "delete" ? "trash" : "arrow.uturn.backward").foregroundStyle(event.action == "delete" ? Color.red.opacity(0.7) : accent)
                            Text(event.action == "delete" ? model.l("Вы удалили пост", "You deleted a post") : model.l("Вы восстановили пост", "You restored a post")).font(.system(size: 13, weight: .semibold))
                            Spacer(); Text(model.date(Int64(event.time), time: true)).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        if let post = event.post {
                            HStack(alignment: .top, spacing: 12) {
                                Rectangle().fill(accent.opacity(0.65)).frame(width: 3)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(post.kind == "photo" ? model.l("Фото", "Photo") : post.kind == "video_note" ? model.l("Видеокружок", "Video message") : model.l("Сообщение", "Message")).font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
                                    Text(post.text).font(.system(size: 13)).lineLimit(3)
                                    Text(model.date(post.date) + " · " + model.date(post.date, time: true)).font(.system(size: 11)).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.fixedSize(horizontal: false, vertical: true)
                        }
                        if event.can_restore {
                            HStack {
                                Button { pendingRestore = event } label: { Label(model.l("Восстановить", "Restore"), systemImage: "arrow.uturn.backward").font(.system(size: 13, weight: .medium)).padding(.vertical, 3) }.buttonStyle(.borderedProminent).disabled(model.busy || model.connectionError)
                                Spacer()
                                Text(remaining(event)).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        } else {
                            Text(event.status == "expired" ? model.l("Срок восстановления истёк", "Recovery period expired") : event.status == "superseded" ? model.l("Есть более новое действие", "A newer action exists") : model.l("Восстановлено", "Restored")).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }.padding(18).background(.white).clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }.background(canvas)
    }
    private func remaining(_ event: RecoveryEvent) -> String {
        let seconds = max(0, (event.expires_at ?? 0) - (model.snapshot?.server_time ?? 0))
        let hours = max(1, Int(ceil(seconds / 3600)))
        return model.l("Осталось: \(hours) ч", "\(hours)h remaining")
    }
    private var proof: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Restore Channel Post").font(.title2.weight(.semibold))
            Text(model.l("Это исполняемое предложение функции Telegram с локальным сервером и SQLite. Настоящие каналы и аккаунты Telegram не подключены.", "This is an executable Telegram feature proposal using a local server and SQLite. Live Telegram accounts and channels are not connected."))
            Text(model.l("Интерфейс отправляет запросы серверу. Восстановление возвращает тот же объект, ID и дату. Перезапуск приложения сохраняет состояние.", "The interface sends real requests to the reference server. Recovery returns the same object, ID and date. State survives app restarts."))
            Text(model.l("Для внедрения в Telegram требуется реализация операции на его сервере. Клиентский патч и контракт находятся в исходниках.", "Shipping this in Telegram requires its server-side recovery operation. The client patch and integration contract are included in the source."))
            if let snapshot = model.snapshot {
                Text("DB revision: \(snapshot.version) · Visible posts: \(snapshot.posts.count) · Events: \(snapshot.events.count)").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
            Button(model.l("Готово", "Done")) { showingProof = false }.buttonStyle(.borderedProminent)
        }.font(.system(size: 13)).lineSpacing(4).padding(30).frame(maxWidth: 510)
    }
    private func avatar(size: CGFloat) -> some View {
        ZStack { Circle().fill(LinearGradient(colors: [Color(red: 0.3, green: 0.67, blue: 0.87), Color(red: 0.22, green: 0.44, blue: 0.77)], startPoint: .topLeading, endPoint: .bottomTrailing)); Text("S").font(.system(size: size * 0.44, weight: .medium, design: .rounded)).foregroundStyle(.white) }.frame(width: size, height: size)
    }
}

private struct PostCard: View {
    let post: RecoveryPost
    @ObservedObject var model: RecoveryViewModel
    let highlighted: Bool
    let onDelete: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Studio Notes").font(.system(size: 12, weight: .semibold)).foregroundStyle(accent)
                Spacer()
                Button(action: onDelete) { Image(systemName: "trash").font(.system(size: 12)).padding(4) }.buttonStyle(.plain).foregroundStyle(.secondary).disabled(model.busy || model.connectionError).accessibilityLabel(model.l("Удалить пост от \(model.date(post.date))", "Delete post dated \(model.date(post.date))"))
            }
            if let asset = post.asset, let client = model.client {
                if post.kind == "photo" {
                    AsyncImage(url: client.assetURL(asset)) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else { Rectangle().fill(canvas).overlay(ProgressView()) }
                    }.frame(height: 190).clipped().clipShape(RoundedRectangle(cornerRadius: 9))
                } else {
                    CircleVideo(url: client.assetURL(asset)).frame(width: 182, height: 182).clipShape(Circle()).frame(maxWidth: .infinity)
                }
            }
            Text(post.text).font(.system(size: 14)).lineSpacing(4).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 13) {
                Text("🤍 \(post.reactions)").font(.system(size: 11)).padding(.horizontal, 8).padding(.vertical, 4).background(accent.opacity(0.07)).clipShape(Capsule())
                Label("\(post.comments)", systemImage: "bubble.right").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Text(model.date(post.date, time: true)).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.padding(16).background(.white).clipShape(RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).stroke(highlighted ? accent.opacity(0.8) : Color.clear, lineWidth: 2)).shadow(color: .black.opacity(0.035), radius: 3, y: 1)
    }
}
private struct CircleVideo: View {
    let url: URL
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    var body: some View {
        VideoPlayer(player: player)
            .overlay {
                Button {
                    if isPlaying { player?.pause() } else { player?.play() }
                    isPlaying.toggle()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 50, height: 50).background(.black.opacity(0.25)).clipShape(Circle())
                }.buttonStyle(.plain).accessibilityLabel(isPlaying ? "Pause video message" : "Play video message")
            }
            .onAppear { if player == nil { player = AVPlayer(url: url) } }
            .onDisappear { player?.pause(); isPlaying = false }
            .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
                if (notification.object as? AVPlayerItem) === player?.currentItem {
                    isPlaying = false
                    player?.seek(to: .zero)
                }
            }
    }
}
