#if os(macOS)
import Foundation
import ChannelRecoveryKit

final class DemoHost {
    private var process: Process?
    struct Configuration: Decodable { let url: String; let token: String }
    func start() async throws -> RecoveryClient {
        let resources = Bundle.main.resourceURL!
        let server = resources.appendingPathComponent("server/http_api.py")
        guard FileManager.default.fileExists(atPath: server.path) else { throw APIError(code: "SERVER_FILES_MISSING") }
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("ChannelRecoveryReference", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [server.path, "--db", support.appendingPathComponent("demo.sqlite3").path, "--assets", resources.appendingPathComponent("media").path, "--parent-pid", String(ProcessInfo.processInfo.processIdentifier)]
        var environment = ProcessInfo.processInfo.environment
        environment["RECOVERY_DEMO_TOKEN"] = UUID().uuidString + UUID().uuidString
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        self.process = process
        let configuration: Configuration = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    try process.run()
                    var data = Data()
                    while data.count < 4096 {
                        let byte = output.fileHandleForReading.readData(ofLength: 1)
                        guard !byte.isEmpty else { throw APIError(code: "SERVER_START_FAILED") }
                        if byte == Data([10]) { break }
                        data.append(byte)
                    }
                    continuation.resume(returning: try JSONDecoder().decode(Configuration.self, from: data))
                } catch { continuation.resume(throwing: error) }
            }
        }
        guard let url = URL(string: configuration.url) else { throw APIError(code: "SERVER_START_FAILED") }
        return try RecoveryClient(baseURL: url, token: configuration.token)
    }
    func stop() { if process?.isRunning == true { process?.terminate() }; process = nil }
    deinit { stop() }
}
#endif
