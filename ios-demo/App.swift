import SwiftUI
import ChannelRecoveryKit

@main struct RecoveryPhoneDemo: App {
    @StateObject private var model = RecoveryViewModel()
    private let captureCanvas = CommandLine.arguments.contains("--capture-canvas")
    var body: some Scene {
        WindowGroup {
            Group {
            if captureCanvas {
            ZStack {
                Color(white: 0.08).ignoresSafeArea()
                VStack(spacing: 0) {
                    if captureCanvas {
                        HStack(spacing: 5) {
                            Text(Date(), style: .time).font(.system(size: 11, weight: .semibold))
                            Spacer()
                            Image(systemName: "cellularbars")
                            Image(systemName: "wifi")
                            Image(systemName: "battery.100percent")
                        }.font(.system(size: 10)).padding(.horizontal, 12).frame(height: 20)
                    }
                    TelegramRecoveryView(model: model, compactPresentation: captureCanvas)
                }.frame(width: captureCanvas ? 402 : nil, height: captureCanvas ? 612 : nil).background(.black).clipped()
            }.ignoresSafeArea().statusBarHidden(true)
            } else {
                TelegramRecoveryView(model: model)
            }
            }.preferredColorScheme(.dark)
                .task {
                    let environment = ProcessInfo.processInfo.environment
                    guard let endpoint = environment["RECOVERY_REFERENCE_URL"], let url = URL(string: endpoint), let token = environment["RECOVERY_REFERENCE_TOKEN"] else {
                        model.alertMessage = "Launch this reference build with run-ios-demo.sh so the local server is configured."
                        return
                    }
                    do {
                        let client = try RecoveryClient(baseURL: url, token: token)
                        await model.connect(client)
                        model.english = false
                        await model.poll()
                    } catch {
                        model.alertMessage = "The local reference server could not be configured."
                    }
                }
        }
    }
}
