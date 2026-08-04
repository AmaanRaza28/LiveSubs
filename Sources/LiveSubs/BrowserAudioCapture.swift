import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

final class BrowserAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    var onPCM: (@Sendable ([Float], Double) -> Void)?
    var onLevel: (@Sendable (Double) -> Void)?
    var onError: (@Sendable (String) -> Void)?

    private let queue = DispatchQueue(label: "LiveSubs.audio", qos: .userInteractive)
    private var stream: SCStream?

    @MainActor
    func start(application: SCRunningApplication) async throws {
        await stop()

        let filter = SCContentFilter(
            display: try await primaryDisplay(),
            including: [application],
            exceptingWindows: []
        )
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 16_000
        configuration.channelCount = 1
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let stream = SCStream(
            filter: filter,
            configuration: configuration,
            delegate: self
        )
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    @MainActor
    func stop() async {
        guard let stream else { return }
        try? await stream.stopCapture()
        self.stream = nil
    }

    private func primaryDisplay() async throws -> SCDisplay {
        let content = try await SCShareableContent.excludingDesktopWindows(
            true,
            onScreenWindowsOnly: false
        )
        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }
        return display
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio,
              sampleBuffer.isValid,
              let format = sampleBuffer.formatDescription?.audioStreamBasicDescription,
              format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32 else { return }

        let samples: [Float]
        do {
            samples = try sampleBuffer.withAudioBufferList { buffers, _ in
                buffers.flatMap { buffer -> [Float] in
                    guard let data = buffer.mData else { return [] }
                    let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                    return Array(
                        UnsafeBufferPointer(
                            start: data.assumingMemoryBound(to: Float.self),
                            count: count
                        )
                    )
                }
            }
        } catch {
            return
        }

        guard !samples.isEmpty else { return }
        let meanSquare = samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(samples.count)
        let rms = sqrt(meanSquare)
        let normalizedLevel = min(1, max(0, (20 * log10(max(rms, 0.000_01)) + 60) / 60))
        onLevel?(normalizedLevel)
        onPCM?(samples, format.mSampleRate)
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        onLevel?(0)
        onError?(error.localizedDescription)
    }

    enum CaptureError: LocalizedError {
        case noDisplay

        var errorDescription: String? {
            "No active display was found"
        }
    }
}
