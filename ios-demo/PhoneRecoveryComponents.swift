import SwiftUI
import UIKit
import AVKit

struct RecoveryWallpaper: View {
    var body: some View { Color.black }
}

/// An original abstract silver avatar, separate from the video character.
struct RecoveryChannelAvatar: View {
    var size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.055))
            Circle().stroke(LinearGradient(colors: [.white.opacity(0.7), .gray.opacity(0.2), .white.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: max(0.5, size * 0.008))
            Image(systemName: "moon.fill")
                .font(.system(size: size * 0.49, weight: .light))
                .foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.30), Color(white: 0.86)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .rotationEffect(.degrees(-20))
        }.frame(width: size, height: size).clipShape(Circle())
    }
}

struct RecoverySettingsRow: View {
    let title: String
    let symbol: String
    let color: Color
    var value = ""
    var chevron = true
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 28, height: 28).background(color).clipShape(RoundedRectangle(cornerRadius: 7))
            Text(title).font(.system(size: 16)).foregroundStyle(.white)
            Spacer(minLength: 4)
            Text(value).font(.system(size: 15)).foregroundStyle(.secondary)
            if chevron { Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tertiary) }
        }.padding(.vertical, 2)
    }
}

private final class RecoveryPlayerSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
private struct RecoveryPlayerLayer: UIViewRepresentable {
    let player: AVPlayer?
    func makeUIView(context: Context) -> RecoveryPlayerSurface {
        let view = RecoveryPlayerSurface()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ view: RecoveryPlayerSurface, context: Context) { view.playerLayer.player = player }
}

struct PhoneRecoveryVideo: View {
    let url: URL
    let english: Bool
    @State private var player: AVPlayer?
    @State private var playing = false
    var body: some View {
        ZStack {
            RecoveryPlayerLayer(player: player)
            Button {
                guard let player else { return }
                if playing { player.pause() }
                else {
                    if let item = player.currentItem, item.duration.isNumeric, player.currentTime() >= item.duration { player.seek(to: .zero) }
                    player.play()
                }
                playing.toggle()
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .semibold)).foregroundStyle(.white.opacity(playing ? 0 : 1))
                    .frame(width: 54, height: 54).background(.black.opacity(playing ? 0 : 0.30)).clipShape(Circle())
            }.buttonStyle(.plain)
                .accessibilityLabel(english ? (playing ? "Pause video message" : "Play video message") : (playing ? "Приостановить видеокружок" : "Воспроизвести видеокружок"))
        }.onAppear { if player == nil { player = AVPlayer(url: url) } }
            .onDisappear { player?.pause(); playing = false }
            .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { notification in
                if let item = notification.object as? AVPlayerItem, item === player?.currentItem { playing = false }
            }
    }
}

/// Read the actual media duration, so replacing a fixture does not leave a stale
/// hard-coded duration in the channel or admin log.
struct RecoveryVideoDuration: View {
    let url: URL
    @State private var label: String?
    var body: some View {
        Text(label ?? "–:––")
            .task(id: url) {
                label = nil
                do {
                    let duration = try await AVURLAsset(url: url).load(.duration)
                    let seconds = CMTimeGetSeconds(duration)
                    guard !Task.isCancelled, seconds.isFinite, seconds >= 0, seconds < 86_400 else { return }
                    let rounded = Int(seconds.rounded())
                    label = String(format: "%d:%02d", rounded / 60, rounded % 60)
                } catch { /* Keep an unknown duration when media is unavailable. */ }
            }
    }
}

/// Simulator camera stand-in: loops the approved fictional character clip.
/// This host demonstrates the recording gesture; it never accesses a real camera.
struct RecoveryRecordingPreview: View {
    let url: URL
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    var body: some View {
        RecoveryPlayerLayer(player: player)
            .onAppear {
                let queue = AVQueuePlayer()
                queue.isMuted = true
                looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
                player = queue
                queue.play()
            }
            .onDisappear { player?.pause(); looper = nil; player = nil }
    }
}
