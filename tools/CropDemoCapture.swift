import AVFoundation
import Foundation

/// Extracts the already-rendered compact UI from a Simulator capture.
/// No scaling, invented interface frames, or changes to the UI aspect ratio.
@main struct CropDemoCapture {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 7,
              let x = Double(args[3]), let y = Double(args[4]),
              let width = Double(args[5]), let height = Double(args[6]),
              x >= 0, y >= 0, width > 0, height > 0 else {
            fatalError("Usage: crop-demo-capture input.mov output.mp4 x y width height")
        }
        let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { fatalError("Missing video track") }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        guard transform == .identity, x + width <= size.width, y + height <= size.height else {
            fatalError("Capture must be upright and the crop must be within its pixel bounds")
        }
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: try await asset.load(.duration))
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(CGAffineTransform(translationX: -x, y: -y), at: .zero)
        instruction.layerInstructions = [layer]
        let composition = AVMutableVideoComposition()
        composition.renderSize = CGSize(width: width, height: height)
        composition.frameDuration = CMTime(value: 1, timescale: 30)
        composition.instructions = [instruction]
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { fatalError("Export unavailable") }
        export.videoComposition = composition
        let output = URL(fileURLWithPath: args[2])
        guard !FileManager.default.fileExists(atPath: output.path) else { fatalError("Output already exists") }
        export.outputURL = output
        export.outputFileType = .mp4
        await export.export()
        guard export.status == .completed else { throw export.error ?? NSError(domain: "CropDemoCapture", code: 1) }
        print("Cropped without stretching: \(Int(width)) × \(Int(height))")
    }
}
