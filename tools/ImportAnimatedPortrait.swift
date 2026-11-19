// Converts the actual frames of an approved animated image to the reference
// host's video-message fixture. No face animation or UI is fabricated here.
import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO

@main struct ImportAnimatedPortrait {
    static func main() async throws {
        guard (3...4).contains(CommandLine.arguments.count) else { fatalError("Usage: ImportAnimatedPortrait input.gif output.mov [loops]") }
        let loops = CommandLine.arguments.count == 4 ? Int(CommandLine.arguments[3]) ?? 1 : 1
        guard (1...10).contains(loops) else { fatalError("loops must be 1...10") }
        let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let destination = URL(fileURLWithPath: CommandLine.arguments[2])
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              CGImageSourceGetCount(source) > 1,
              let first = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("An animated image with multiple frames is required") }
        let width = first.width, height = first.height
        guard width % 2 == 0, height % 2 == 0 else { fatalError("Even video dimensions required") }
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        let writer = try AVAssetWriter(outputURL: destination, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height, AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 2_000_000]])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height, kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error! }
        writer.startSession(atSourceTime: .zero)
        var time = 0.0
        for outputIndex in 0..<(CGImageSourceGetCount(source) * loops) {
            let index = outputIndex % CGImageSourceGetCount(source)
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil),
                  let pool = adaptor.pixelBufferPool else { fatalError("Unreadable animation frame") }
            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let pixelBuffer = buffer else { fatalError("Pixel buffer allocation failed") }
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer), width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { fatalError("Bitmap context failed") }
            context.setFillColor(CGColor(gray: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            guard adaptor.append(pixelBuffer, withPresentationTime: CMTime(seconds: time, preferredTimescale: 600)) else { throw writer.error! }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
            let delay = gif?[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double ?? gif?[kCGImagePropertyGIFDelayTime as String] as? Double ?? 0.12
            time += max(0.02, delay)
        }
        writer.endSession(atSourceTime: CMTime(seconds: time, preferredTimescale: 600))
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error! }
        print("Imported \(CGImageSourceGetCount(source)) actual source frames × \(loops) loops, \(width)×\(height), \(String(format: "%.3f", time)) seconds: \(destination.path)")
    }
}
