import SwiftUI
import UIKit
import ChannelRecoveryKit

/// Runnable reference host. Channel mutations use the shared coordinator and
/// server. Existing Telegram settings/actions are context, not a replacement client.
struct TelegramRecoveryView: View {
    private enum Screen: Hashable { case profile, edit, actions }
    private struct Utility: Identifiable { let id = UUID(); let title: String; let post: RecoveryPost }
    private struct Menu {
        let post: RecoveryPost
        let event: RecoveryEvent?
        let frame: CGRect
        var confirmingDelete = false
    }
    private struct Frames: PreferenceKey {
        static let defaultValue: [String: CGRect] = [:]
        static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
    }
    @ObservedObject var model: RecoveryViewModel
    var compactPresentation = false
    @State private var path: [Screen] = []
    @State private var menu: Menu?
    @State private var frames: [String: CGRect] = [:]
    @State private var utility: Utility?
    @State private var showingControls = false
    @State private var showingChats = false
    @State private var channelMuted = true
    @State private var draft = ""
    @State private var recordingStarted: Date?
    @State private var actionQuery = ""
    @State private var searchingActions = false
    @State private var actionFilter = "all"
    @FocusState private var composerFocused: Bool
    private let accent = Color(red: 0.78, green: 0.52, blue: 0.91)
    private let bubble = Color(red: 0.15, green: 0.16, blue: 0.17)
    private let author = Color(red: 0.78, green: 0.52, blue: 0.91)

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                NavigationStack(path: $path) {
                    channel.navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button { showingChats = true } label: { Image(systemName: "chevron.left").font(.system(size: 18, weight: .medium)) }
                                    .accessibilityLabel(model.l("Чаты", "Chats"))
                            }
                            ToolbarItem(placement: .principal) {
                                Button { path.append(.profile) } label: {
                                    VStack(spacing: 1) {
                                        Text("zexeAI").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                                        Text(model.l("1 284 подписчика", "1,284 subscribers")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                                    }.padding(.horizontal, 20).padding(.vertical, 4)
                                }.accessibilityLabel(model.l("Открыть профиль канала", "Open channel profile"))
                            }
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button { path.append(.profile) } label: { RecoveryChannelAvatar(size: 32) }
                                    .accessibilityLabel(model.l("Информация о канале", "Channel information"))
                            }
                        }
                        .navigationDestination(for: Screen.self) { screen in
                            switch screen { case .profile: profile; case .edit: edit; case .actions: actions }
                        }
                }
                if !compactPresentation { referenceStrip }
            }.blur(radius: menu == nil ? 0 : 10).allowsHitTesting(menu == nil).accessibilityHidden(menu != nil)
            if let menu { contextOverlay(menu).zIndex(5).transition(.opacity) }
        }.coordinateSpace(name: "recovery-root")
            .onPreferenceChange(Frames.self) { frames = $0 }
            .tint(accent)
            .animation(.easeOut(duration: 0.18), value: menu != nil)
            .overlay(alignment: .bottom) {
                if model.busy {
                    HStack(spacing: 9) { ProgressView(); Text(model.l("Пожалуйста, подождите…", "Please wait…")) }
                        .font(.system(size: 14)).padding(12).background(.ultraThinMaterial).clipShape(Capsule()).padding(.bottom, 92)
                } else if let notice = model.notice, menu == nil {
                    Text(notice).font(.system(size: 13)).multilineTextAlignment(.center).padding(12)
                        .background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 24).padding(.bottom, 92).allowsHitTesting(false)
                }
            }
            .task(id: model.notice) {
                guard model.notice != nil else { return }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if !Task.isCancelled { model.notice = nil }
            }
            .alert(model.l("Не удалось завершить действие", "Action could not be completed"), isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })) {
                Button("OK") { model.alertMessage = nil }
            } message: { Text(model.alertMessage ?? "") }
            .sheet(item: $utility) { item in
                NavigationStack {
                    Form {
                        Section(model.l("Публикация", "Post")) { Text(item.post.text).textSelection(.enabled) }
                        Section {
                            ShareLink(item: item.post.text) { Label(model.l("Поделиться", "Share"), systemImage: "square.and.arrow.up") }
                            Button(model.l("Скопировать", "Copy")) { UIPasteboard.general.string = item.post.text }
                        }
                    }.navigationTitle(item.title)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(model.l("Готово", "Done")) { utility = nil } } }
                }
            }
            .sheet(isPresented: $showingChats) {
                NavigationStack { List { Button("zexeAI") { showingChats = false } }.navigationTitle(model.l("Чаты", "Chats")) }.presentationDetents([.medium])
            }
            .sheet(isPresented: $showingControls) {
                NavigationStack {
                    Form {
                        Section { Text(model.l("Рабочий прототип функции Telegram. Используются локальный сервер и вымышленные публикации. Для выпуска требуется серверная поддержка Telegram.", "Working Telegram feature prototype using a local server and fictional posts. Rollout requires Telegram server support.")) }
                        Button(model.l("Начать с пустого канала", "Start with an empty channel")) {
                            Task { await model.emptyDemo(); path = []; menu = nil; draft = ""; showingControls = false }
                        }.disabled(model.busy)
                        Button(model.l("Загрузить примеры старых постов", "Load old-post examples")) { Task { await model.reset(); path = []; menu = nil; showingControls = false } }
                            .disabled(model.busy)
                        Button(model.english ? "Русский интерфейс" : "English interface") { model.english.toggle() }
                    }.navigationTitle(model.l("О прототипе", "About this prototype"))
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(model.l("Готово", "Done")) { showingControls = false } } }
                }
            }
            .onReceive(model.$highlightedPost) { id in if id != nil { menu = nil; withAnimation(.easeInOut(duration: 0.25)) { path = [] } } }
    }

    private var channel: some View {
        VStack(spacing: 0) {
            if model.connectionError {
                Button { Task { await model.refresh() } } label: {
                    Label(model.l("Нет соединения · Обновить", "No connection · Refresh"), systemImage: "wifi.exclamationmark")
                        .font(.system(size: 13)).foregroundStyle(.orange).padding(8).frame(maxWidth: .infinity)
                }.background(.black.opacity(0.7))
            }
            ScrollViewReader { proxy in
                GeometryReader { viewport in
                ScrollView {
                    LazyVStack(spacing: 0) {
                    ForEach(model.snapshot?.posts ?? []) { post in
                        VStack(spacing: 7) {
                            if needsDatePill(post) { datePill(model.date(post.date)) }
                            postBubble(post)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(frameReader("post-\(post.id)"))
                                .onLongPressGesture(minimumDuration: 0.45) { openMenu(post, event: nil, key: "post-\(post.id)") }
                        }.id(post.id)
                            .padding(.vertical, 7).padding(.horizontal, 10)
                    }
                    }.frame(minHeight: viewport.size.height, alignment: .bottom)
                }.background { RecoveryWallpaper() }
                    .onChange(of: model.snapshot?.posts.last?.id) { id in
                        if let id { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) } }
                    }
                    .onAppear { revealRestored(proxy) }
                    .onReceive(model.$highlightedPost) { _ in revealRestored(proxy) }
                }
            }.id(model.demoResetID)
            HStack(alignment: .bottom, spacing: 12) {
                Button { model.notice = model.l("Для кружка удерживайте кнопку камеры", "Hold the camera button for a video message") } label: {
                    Image(systemName: "paperclip").font(.system(size: 23)).frame(height: 34)
                }.accessibilityLabel(model.l("Прикрепить", "Attach"))
                TextField(model.l("Публикация", "Broadcast"), text: $draft, axis: .vertical)
                    .font(.system(size: 17)).lineLimit(1...4).focused($composerFocused)
                    .accessibilityIdentifier("channel-composer").padding(.vertical, 7)
                if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button { channelMuted.toggle() } label: { Image(systemName: channelMuted ? "bell.slash" : "bell").font(.system(size: 20)).frame(height: 34) }
                        .accessibilityLabel(model.l("Уведомления", "Notifications"))
                    Image(systemName: "video").font(.system(size: 22)).frame(width: 34, height: 34).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if recordingStarted == nil { composerFocused = false; recordingStarted = Date(); model.notice = nil }
                            }
                            .onEnded { value in
                                guard let started = recordingStarted else { return }
                                recordingStarted = nil
                                if value.translation.width < -70 { return }
                                guard Date().timeIntervalSince(started) >= 0.5 else {
                                    model.notice = model.l("Удерживайте для записи · влево для отмены", "Hold to record · slide left to cancel")
                                    return
                                }
                                Task { _ = await model.publish(kind: "video_note", text: "") }
                            })
                        .accessibilityLabel(model.l("Удерживать для записи видеосообщения", "Hold to record video message"))
                        .accessibilityIdentifier("record-circle")
                } else {
                    Button {
                        let text = draft
                        Task { if await model.publish(kind: "text", text: text) { draft = ""; composerFocused = false } }
                    } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 30)).foregroundStyle(accent).frame(height: 34) }
                        .accessibilityLabel(model.l("Отправить", "Send")).accessibilityIdentifier("send-text")
                }
            }.foregroundStyle(.secondary).padding(.horizontal, 14).padding(.vertical, 5).background(Color(white: 0.10))
                .disabled(model.busy || model.connectionError)
        }.overlay {
            if let started = recordingStarted, let client = model.client {
                ZStack {
                    Color.black.opacity(0.68)
                    RecoveryRecordingPreview(url: client.assetURL("demo-circle.mov"))
                        .frame(width: 310, height: 310).clipShape(Circle())
                        .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 1))
                    VStack {
                        Spacer()
                        HStack(spacing: 10) {
                            Circle().fill(.red).frame(width: 8, height: 8)
                            TimelineView(.periodic(from: started, by: 0.1)) { context in
                                let elapsed = max(0, Int(context.date.timeIntervalSince(started) * 10))
                                Text(String(format: "%d:%02d,%d", elapsed / 600, elapsed / 10 % 60, elapsed % 10))
                                    .monospacedDigit().font(.system(size: 15))
                            }
                            Spacer()
                            Text(model.l("‹  Влево — отмена", "‹  Slide to cancel")).font(.system(size: 14)).foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "video.fill").font(.system(size: 24)).foregroundStyle(.white)
                                .frame(width: 48, height: 48).background(accent).clipShape(Circle())
                        }.padding(.horizontal, 14).frame(height: 54).background(Color(white: 0.10))
                    }
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder private func postBubble(_ post: RecoveryPost, showComments: Bool = true, displayDate: Int64? = nil) -> some View {
        if post.kind == "video_note" {
            videoNoteBubble(post, showComments: showComments, displayDate: displayDate)
        } else {
        VStack(alignment: .leading, spacing: 8) {
            Text("zexeAI").font(.system(size: 13, weight: .semibold)).foregroundStyle(author)
            postMedia(post, photoHeight: 228, videoSize: 174)
            richPostText(post.text).font(.system(size: 16)).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            HStack {
                if post.reactions > 0 { Text("🤍 \(post.reactions)").font(.system(size: 12)).padding(.horizontal, 8).padding(.vertical, 4).background(.white.opacity(0.055)).clipShape(Capsule()) }
                Spacer()
                Text(model.date(displayDate ?? post.date, time: true)).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if showComments {
            Divider().overlay(.white.opacity(0.04))
            HStack {
                Image(systemName: "bubble.left").font(.system(size: 12))
                Text(commentCount(post.comments)).font(.system(size: 12))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
            }.foregroundStyle(accent)
            }
        }.padding(11).frame(maxWidth: 340, alignment: .leading).background(bubble)
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(model.highlightedPost == post.id ? accent : .clear, lineWidth: 2))
            .accessibilityIdentifier("channel-post-\(post.id)")
        }
    }

    private func videoNoteBubble(_ post: RecoveryPost, showComments: Bool = true, displayDate: Int64? = nil) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .bottom, spacing: 7) {
                if let asset = post.asset, let client = model.client {
                    PhoneRecoveryVideo(url: client.assetURL(asset), english: model.english)
                        .frame(width: 224, height: 224).clipShape(Circle())
                        .overlay(Circle().stroke(model.highlightedPost == post.id ? accent : Color.white.opacity(0.12), lineWidth: model.highlightedPost == post.id ? 2 : 0.5))
                        .overlay(alignment: .bottomLeading) {
                            RecoveryVideoDuration(url: client.assetURL(asset)).font(.system(size: 11, weight: .medium)).padding(.horizontal, 7).padding(.vertical, 3)
                                .background(.black.opacity(0.65)).clipShape(Capsule()).offset(x: 9, y: -2)
                        }
                }
                Text(model.date(displayDate ?? post.date, time: true)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                    .padding(.horizontal, 7).padding(.vertical, 4).background(Color(white: 0.10)).clipShape(Capsule()).padding(.bottom, 6)
            }
            if !post.text.isEmpty { richPostText(post.text).font(.system(size: 16)).fixedSize(horizontal: false, vertical: true) }
            if showComments { HStack(spacing: 6) {
                Image(systemName: "bubble.left.fill").font(.system(size: 12))
                if post.comments > 0 { Text("\(post.comments)").font(.system(size: 12)) }
            }.foregroundStyle(.white.opacity(0.85)).padding(.horizontal, 9).padding(.vertical, 6)
                .background(Color(white: 0.12)).clipShape(Capsule()) }
        }.frame(maxWidth: 340, alignment: .leading).contentShape(Rectangle())
            .accessibilityIdentifier("channel-post-\(post.id)")
    }

    @ViewBuilder private func postMedia(_ post: RecoveryPost, photoHeight: CGFloat, videoSize: CGFloat) -> some View {
        if let asset = post.asset, let client = model.client {
            if post.kind == "photo" {
                AsyncImage(url: client.assetURL(asset)) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { Rectangle().fill(.white.opacity(0.05)) }
                }.frame(height: photoHeight).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                PhoneRecoveryVideo(url: client.assetURL(asset), english: model.english)
                    .frame(width: videoSize, height: videoSize).clipShape(Circle()).frame(maxWidth: .infinity)
            }
        }
    }

    private var profile: some View {
        List {
            VStack(spacing: 10) {
                RecoveryChannelAvatar(size: 124).padding(.top, 8)
                Text("zexeAI").font(.system(size: 25, weight: .semibold))
                Text(model.l("1 284 подписчика", "1,284 subscribers")).font(.system(size: 13)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button { channelMuted.toggle() } label: { profileTile(model.l("звук", "sound"), channelMuted ? "bell.slash.fill" : "bell.fill") }.buttonStyle(.plain)
                    profileTile(model.l("поиск", "search"), "magnifyingglass")
                    Button { showingControls = true } label: { profileTile(model.l("ещё", "more"), "ellipsis") }.buttonStyle(.plain)
                }.padding(.top, 7)
            }.frame(maxWidth: .infinity).listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 16, trailing: 0)).listRowBackground(Color.clear)
            Section {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.l("ссылка", "link")).font(.system(size: 12)).foregroundStyle(.secondary)
                    Text("t.me/zexeai_demo").font(.system(size: 16)).foregroundStyle(accent)
                }.padding(.vertical, 3)
            }
            Section {
                settingsRow(model.l("Администраторы", "Administrators"), "checkmark.shield.fill", .green, "1")
                settingsRow(model.l("Подписчики", "Subscribers"), "person.2.fill", .blue, "1")
                Button { path.append(.edit) } label: { settingsRow(model.l("Настройки канала", "Channel Settings"), "slider.horizontal.3", .orange) }.buttonStyle(.plain)
            }
        }.listStyle(.insetGrouped).scrollContentBackground(.hidden).background(.black)
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button(model.l("Изм.", "Edit")) { path.append(.edit) } } }
    }

    private var edit: some View {
        ScrollViewReader { proxy in
        List {
            VStack(spacing: 8) {
                RecoveryChannelAvatar(size: 70)
                Text(model.l("Изменить фотографию", "Set Photo")).font(.system(size: 14)).foregroundStyle(accent)
            }.frame(maxWidth: .infinity).listRowBackground(Color.clear)
            Section { Text("zexeAI"); Text(model.l("фотографии, мысли и немного ночи.", "photos, thoughts and a little night.")).foregroundStyle(.secondary).font(.system(size: 14)) }
            Section {
                settingsRow(model.l("Тип канала", "Channel Type"), "megaphone.fill", .blue, model.l("Публичный", "Public"))
                settingsRow(model.l("Обсуждение", "Discussion"), "bubble.left.and.bubble.right.fill", .green, model.l("Добавить", "Add"))
                settingsRow(model.l("Реакции", "Reactions"), "heart.fill", .pink, model.l("Все реакции", "All Reactions"))
                settingsRow(model.l("Приветствие", "Greeting"), "hand.wave.fill", .indigo, model.l("Выкл.", "Off"))
                settingsRow(model.l("Оформление", "Appearance"), "paintbrush.fill", .orange)
                settingsRow(model.l("Автоперевод сообщений", "Auto-Translate"), "character.bubble.fill", .purple, "🔒")
                settingsRow(model.l("Сообщения каналу", "Channel Messages"), "bubble.left.fill", .indigo, model.l("Выкл.", "Off"))
            }
            Section {
                settingsRow(model.l("Администраторы", "Administrators"), "checkmark.shield.fill", .green, "1")
                settingsRow(model.l("Подписчики", "Subscribers"), "person.2.fill", .blue, "1")
                settingsRow(model.l("Чёрный список", "Removed Users"), "minus.circle.fill", .red)
                Button { path.append(.actions) } label: { settingsRow(model.l("Недавние действия", "Recent Actions"), "clock.arrow.circlepath", .orange) }.buttonStyle(.plain)
                    .accessibilityIdentifier("open-recent-actions")
                    .id("recent-actions-row")
            }
        }.listStyle(.insetGrouped).scrollContentBackground(.hidden).background(.black)
            .accessibilityAction(named: Text(model.l("Прокрутить к недавним действиям", "Scroll to Recent Actions"))) {
                withAnimation(.easeInOut(duration: 1.35)) {
                    proxy.scrollTo("recent-actions-row", anchor: .bottom)
                }
            }
            .navigationTitle(model.l("Изменить", "Edit")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button { path.removeLast() } label: { Image(systemName: "checkmark").font(.system(size: 19, weight: .semibold)) }.accessibilityLabel(model.l("Готово", "Done")) } }
        }
    }

    private var actions: some View {
        VStack(spacing: 0) {
            if searchingActions {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(model.l("Поиск", "Search"), text: $actionQuery).font(.system(size: 16))
                        .accessibilityIdentifier("admin-log-search")
                    Button(model.l("Отмена", "Cancel")) { actionQuery = ""; searchingActions = false }.font(.system(size: 14))
                }.padding(10).background(Color(white: 0.10)).clipShape(Capsule()).padding(.horizontal, 10).padding(.bottom, 6)
            }
            actionFeed
            HStack {
                Color.clear.frame(width: 36, height: 36)
                Spacer()
                SwiftUI.Menu {
                    Button(model.l("Все действия", "All Actions")) { actionFilter = "all" }
                    Button(model.l("Удалённые сообщения", "Deleted Messages")) { actionFilter = "delete" }
                    Button(model.l("Восстановленные сообщения", "Restored Messages")) { actionFilter = "restore" }
                } label: {
                    Text(model.l("Настройки", "Settings")).font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white).padding(.horizontal, 18).padding(.vertical, 9)
                        .background(.ultraThinMaterial).clipShape(Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 0.7))
                }.accessibilityIdentifier("admin-log-settings")
                Spacer()
                Button { model.notice = model.l("Здесь показаны действия администраторов за последние 48 часов.", "Administrator actions from the last 48 hours are shown here.") } label: {
                    Image(systemName: "questionmark.circle").font(.system(size: 23)).foregroundStyle(.white.opacity(0.90))
                        .frame(width: 36, height: 36).background(.ultraThinMaterial).clipShape(Circle())
                }.accessibilityLabel(model.l("О недавних действиях", "About recent actions"))
            }.padding(.horizontal, 10).padding(.vertical, 5)
        }.background { RecoveryWallpaper() }.navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { path.removeLast() } label: { Image(systemName: "chevron.left").font(.system(size: 18, weight: .medium)).foregroundStyle(.white) }
                        .accessibilityLabel(model.l("Назад", "Back"))
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("zexeAI").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        Text(model.l(actionFilter == "all" ? "Все действия" : "Выбранные действия", actionFilter == "all" ? "All Actions" : "Selected Actions"))
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.58))
                    }.padding(.horizontal, 25).frame(height: 43).background(.ultraThinMaterial).clipShape(Capsule())
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { searchingActions.toggle(); if !searchingActions { actionQuery = "" } } label: {
                        Image(systemName: "magnifyingglass").font(.system(size: 20)).foregroundStyle(.white)
                    }.accessibilityLabel(model.l("Поиск по действиям", "Search actions"))
                }
            }
    }

    private var actionFeed: some View {
        ScrollViewReader { proxy in
            GeometryReader { viewport in
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(actionEvents) { event in actionEventRow(event).id(event.id) }
                        if actionEvents.isEmpty {
                            Text(model.l("Недавних действий пока нет", "No recent actions yet"))
                                .font(.system(size: 14)).foregroundStyle(.secondary).padding(24)
                        }
                    }.padding(.horizontal, 10).padding(.vertical, 10)
                        .frame(minHeight: viewport.size.height, alignment: .bottom)
                }.onAppear { scrollToLatestAction(proxy) }
                    .onChange(of: actionEvents.last?.id) { _ in scrollToLatestAction(proxy) }
            }
        }
    }
    private func actionEventRow(_ event: RecoveryEvent) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if needsActionDatePill(event) {
                datePill(model.date(Int64(event.time))).frame(maxWidth: .infinity)
            }
            Text(actionCaption(event)).font(.system(size: 13)).foregroundStyle(.white.opacity(0.90))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.white.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 7))
                .frame(maxWidth: .infinity)
            if event.action == "change_photo" {
                RecoveryChannelAvatar(size: 72).frame(maxWidth: .infinity).padding(.vertical, 2)
            } else if event.action == "create_channel" {
                EmptyView()
            } else if let post = event.post {
                postBubble(post, showComments: false, displayDate: Int64(event.time))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(frameReader("event-\(event.id)"))
                    .onLongPressGesture(minimumDuration: 0.45) { openMenu(post, event: event, key: "event-\(event.id)") }
                    .accessibilityIdentifier("deleted-post-event-\(event.id)")
            } else {
                expiredAction
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var expiredAction: some View {
        Text(model.l("Срок хранения удалённой публикации истёк", "Deleted post retention has expired"))
            .font(.system(size: 13)).foregroundStyle(.secondary).padding(11)
            .background(bubble).clipShape(RoundedRectangle(cornerRadius: 13))
    }
    private var actionEvents: [RecoveryEvent] {
        (model.snapshot?.events ?? []).reversed().filter { event in
            guard actionFilter == "all" || event.action == actionFilter else { return false }
            let query = actionQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            return ((event.post?.text ?? "") + " " + actionCaption(event))
                .localizedCaseInsensitiveContains(query)
        }
    }
    private func actionCaption(_ event: RecoveryEvent) -> String {
        if event.action == "create_channel" { return "😁 " + model.l("создал(а) канал «zexeAI»", "created the channel “zexeAI”") }
        if event.action == "change_photo" { return "😁 " + model.l("изменил(а) фотографию канала:", "changed the channel photo:") }
        if event.action == "delete" { return "😁 " + model.l("удалил(а) сообщение:", "deleted a message:") }
        return "😁 " + model.l("восстановил(а) сообщение:", "restored a message:")
    }
    private func needsActionDatePill(_ event: RecoveryEvent) -> Bool {
        let events = actionEvents
        guard let index = events.firstIndex(where: { $0.id == event.id }), index > 0 else { return true }
        return model.date(Int64(events[index - 1].time)) != model.date(Int64(event.time))
    }
    private func scrollToLatestAction(_ proxy: ScrollViewProxy) {
        guard let id = actionEvents.last?.id else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { proxy.scrollTo(id, anchor: .bottom) }
    }

    private func contextOverlay(_ selection: Menu) -> some View {
        GeometryReader { geometry in
            let circle = selection.post.kind == "video_note"
            // Keep the selected media anchored when Delete changes to its
            // confirmation. A video note remains a circle, never a post card.
            let placementRows = selection.event == nil ? 9 : (selection.event?.can_restore == true ? 2 : 1)
            let menuHeight = CGFloat(placementRows) * (compactPresentation ? 34 : 44) + 8
            let previewHeight: CGFloat = circle
                ? min(224, min(geometry.size.width - 32, max(112, geometry.size.height - menuHeight - 40)))
                : (compactPresentation ? 148 : (selection.post.kind != "text" ? 268 : 122))
            let top = max(16, min(selection.frame.minY, geometry.size.height - previewHeight - menuHeight - 28))
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.30).ignoresSafeArea().onTapGesture { menu = nil }.accessibilityLabel(model.l("Закрыть меню", "Dismiss menu"))
                VStack(alignment: .leading, spacing: 8) {
                    if circle {
                        if let asset = selection.post.asset, let client = model.client {
                            PhoneRecoveryVideo(url: client.assetURL(asset), english: model.english)
                                .frame(width: previewHeight, height: previewHeight).clipShape(Circle())
                                .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 0.5))
                                .shadow(color: .black.opacity(0.20), radius: 12, y: 5)
                        }
                    } else {
                        menuPreview(selection).frame(width: min(340, geometry.size.width - 32), height: previewHeight, alignment: .topLeading).clipped().background(bubble).clipShape(RoundedRectangle(cornerRadius: 13))
                    }
                    VStack(spacing: 0) { menuCommands(selection) }
                        .padding(.vertical, 4).frame(width: selection.confirmingDelete ? 236 : 246)
                        .background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 22))
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.10), lineWidth: 0.7))
                }.padding(.leading, 16).padding(.top, top)
            }
        }
    }

    private func menuPreview(_ selection: Menu) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("zexeAI").font(.system(size: 13, weight: .semibold)).foregroundStyle(author)
            postMedia(selection.post, photoHeight: compactPresentation ? 72 : 112, videoSize: compactPresentation ? 72 : 112)
            richPostText(selection.post.text).font(.system(size: 16)).lineSpacing(2).lineLimit(4)
            Spacer(minLength: 0)
            Text(model.date(selection.post.date) + " · " + model.date(selection.post.date, time: true)).font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(12)
    }

    @ViewBuilder private func menuCommands(_ selection: Menu) -> some View {
        if selection.confirmingDelete {
            menuRow(model.l("Удалить у всех", "Delete for Everyone"), "trash", destructive: true) {
                menu = nil
                Task { await model.delete(selection.post) }
            }
        } else if let event = selection.event {
            menuRow(model.l("Скопировать", "Copy"), "doc.on.doc") { copy(selection.post) }
            if event.can_restore {
                Divider().padding(.horizontal, 12)
                menuRow(model.l("Восстановить", "Restore"), "arrow.uturn.backward") {
                    menu = nil
                    Task { await model.restore(event) }
                }.disabled(model.busy || model.connectionError)
            }
        } else {
            menuRow(model.l("Ответить", "Reply"), "arrowshape.turn.up.left") { previewUtility(model.l("Ответить", "Reply"), selection.post) }
            menuRow(model.l("Скопировать", "Copy"), "doc.on.doc") { copy(selection.post) }
            menuRow(model.l("Перевести", "Translate"), "character.bubble") { previewUtility(model.l("Перевести", "Translate"), selection.post) }
            menuRow(model.l("Изменить", "Edit"), "pencil") { previewUtility(model.l("Изменить", "Edit"), selection.post) }
            menuRow(model.l("Закрепить", "Pin"), "pin") { previewUtility(model.l("Закрепить", "Pin"), selection.post) }
            menuRow(model.l("Копировать ссылку", "Copy Link"), "link") {
                UIPasteboard.general.string = "https://t.me/zexeai_demo/\(selection.post.id)"; menu = nil
                model.notice = model.l("Ссылка скопирована", "Link copied")
            }
            menuRow(model.l("Переслать", "Forward"), "arrowshape.turn.up.right") { previewUtility(model.l("Переслать", "Forward"), selection.post) }
            menuRow(model.l("Удалить", "Delete"), "trash", destructive: true) { menu?.confirmingDelete = true }
                .disabled(model.busy || model.connectionError)
            Divider().padding(.horizontal, 12)
            menuRow(model.l("Выбрать", "Select"), "checkmark.circle") { previewUtility(model.l("Выбрать", "Select"), selection.post) }
        }
    }

    private func menuRow(_ title: String, _ symbol: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: symbol).font(.system(size: 16)).frame(width: 22)
                Text(title).font(.system(size: 16))
                Spacer(minLength: 0)
            }.foregroundStyle(destructive ? Color(red: 0.96, green: 0.36, blue: 0.28) : .white)
                .padding(.horizontal, 17).frame(height: compactPresentation ? 34 : 44).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func openMenu(_ post: RecoveryPost, event: RecoveryEvent?, key: String) {
        guard !model.busy else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        menu = Menu(post: post, event: event, frame: frames[key] ?? CGRect(x: 10, y: 100, width: 340, height: 148))
    }
    private func copy(_ post: RecoveryPost) { UIPasteboard.general.string = post.text; menu = nil; model.notice = model.l("Текст скопирован", "Text copied") }
    private func previewUtility(_ title: String, _ post: RecoveryPost) { menu = nil; utility = Utility(title: title, post: post) }
    private func frameReader(_ key: String) -> some View { GeometryReader { geometry in Color.clear.preference(key: Frames.self, value: [key: geometry.frame(in: .named("recovery-root"))]) } }
    private func richPostText(_ value: String) -> Text {
        if let attributed = try? AttributedString(markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(value)
    }
    private func needsDatePill(_ post: RecoveryPost) -> Bool {
        guard let posts = model.snapshot?.posts, let index = posts.firstIndex(where: { $0.id == post.id }), index > 0 else { return true }
        return model.date(posts[index - 1].date) != model.date(post.date)
    }
    private func datePill(_ text: String) -> some View { Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.85)).padding(.horizontal, 10).padding(.vertical, 4).background(.black.opacity(0.28)).clipShape(Capsule()) }
    private func commentCount(_ value: Int) -> String {
        if value == 0 { return model.l("Прокомментировать", "Leave a comment") }
        if model.english { return "\(value) comments" }
        let last = value % 10, lastTwo = value % 100
        let ending = (11...14).contains(lastTwo) ? "комментариев" : (last == 1 ? "комментарий" : ((2...4).contains(last) ? "комментария" : "комментариев"))
        return "\(value) \(ending)"
    }
    private func revealRestored(_ proxy: ScrollViewProxy) {
        guard let id = model.highlightedPost else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) } }
    }
    private func settingsRow(_ title: String, _ symbol: String, _ color: Color, _ value: String = "") -> some View { RecoverySettingsRow(title: title, symbol: symbol, color: color, value: value) }
    private func profileTile(_ title: String, _ symbol: String) -> some View {
        VStack(spacing: 6) { Image(systemName: symbol).font(.system(size: 20)); Text(title).font(.system(size: 11)) }
            .foregroundStyle(.white.opacity(0.9)).frame(maxWidth: .infinity).frame(height: 57).background(.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 11))
    }
    private var referenceStrip: some View {
        HStack {
            Text(model.l("Рабочий прототип · локальный сервер", "Working prototype · local server"))
            Spacer()
            Button { showingControls = true } label: { Image(systemName: "info.circle").font(.system(size: 13)) }.accessibilityLabel(model.l("О прототипе", "About this prototype"))
        }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 12).frame(height: 28).background(.black)
    }
}
