import Foundation
import CoreGraphics
import ImageIO
import AVFoundation

let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
func draw(_ context: CGContext, width: Int, height: Int, phase: CGFloat) {
    let w = CGFloat(width), h = CGFloat(height)
    let space = CGColorSpaceCreateDeviceRGB()
    let colors = [CGColor(red: 0.36, green: 0.65, blue: 0.78, alpha: 1), CGColor(red: 0.97, green: 0.82, blue: 0.66, alpha: 1)] as CFArray
    let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: .zero, options: [])
    context.setFillColor(CGColor(red: 1, green: 0.92, blue: 0.73, alpha: 1))
    context.fillEllipse(in: CGRect(x: w * (0.61 + phase * 0.035), y: h * (0.53 + phase * 0.025), width: w * 0.15, height: w * 0.15))
    for (level, color) in [(CGFloat(0.38), CGColor(red: 0.30, green: 0.50, blue: 0.56, alpha: 1)), (CGFloat(0.23), CGColor(red: 0.18, green: 0.37, blue: 0.43, alpha: 1))] {
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 0, y: h * level))
        path.addCurve(to: CGPoint(x: w, y: h * (level + 0.03)), control1: CGPoint(x: w * 0.3, y: h * (level + 0.23)), control2: CGPoint(x: w * 0.6, y: h * (level - 0.2)))
        path.addLine(to: CGPoint(x: w, y: 0)); path.closeSubpath()
        context.setFillColor(color); context.addPath(path); context.fillPath()
    }
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.25)); context.setLineWidth(1)
    for line in 0..<9 {
        let y = h * 0.04 + CGFloat(line) * h * 0.012
        context.move(to: CGPoint(x: w * (0.1 + phase * 0.02), y: y))
        context.addLine(to: CGPoint(x: w * 0.9, y: y)); context.strokePath()
    }
}
let space = CGColorSpaceCreateDeviceRGB()
let photo = CGContext(data: nil, width: 1000, height: 600, bitsPerComponent: 8, bytesPerRow: 4000, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
draw(photo, width: 1000, height: 600, phase: 0)
let destination = CGImageDestinationCreateWithURL(folder.appendingPathComponent("demo-photo.png") as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, photo.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination))
let movie = folder.appendingPathComponent("demo-circle.mov")
try? FileManager.default.removeItem(at: movie)
let writer = try AVAssetWriter(outputURL: movie, fileType: .mov)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 512, AVVideoHeightKey: 512])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 512, kCVPixelBufferHeightKey as String: 512, kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
writer.add(input)
precondition(writer.startWriting())
writer.startSession(atSourceTime: .zero)
for frame in 0..<120 {
    let deadline = Date().addingTimeInterval(10)
    while !input.isReadyForMoreMediaData {
        precondition(Date() < deadline && writer.status != .failed, "Video writer stalled")
        Thread.sleep(forTimeInterval: 0.001)
    }
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
    let pixel = buffer!
    CVPixelBufferLockBaseAddress(pixel, [])
    let context = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: 512, height: 512, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixel), space: space, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
    draw(context, width: 512, height: 512, phase: CGFloat(frame) / 119)
    CVPixelBufferUnlockBaseAddress(pixel, [])
    precondition(adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
precondition(done.wait(timeout: .now() + 30) == .success)
precondition(writer.status == .completed, String(describing: writer.error))
print("Generated original synthetic PNG and 4-second video fixtures")
