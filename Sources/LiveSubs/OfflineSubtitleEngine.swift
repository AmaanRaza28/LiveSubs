import Foundation

final class OfflineSubtitleEngine: @unchecked Sendable {
    static let shared = OfflineSubtitleEngine()

    var onSubtitle: (@Sendable (String) -> Void)?
    var onStatus: (@Sendable (String) -> Void)?
    var onBenchmarkCaptured: (@Sendable (String) -> Void)?

    private let lock = NSLock()
    private var samples: [Float] = []
    private var samplesSinceInference = 0
    private var isInferring = false
    private var sourceLanguage = "auto"
    private var benchmarkSamples: [Float] = []
    private var benchmarkTargetCount = 0
    private var stabilizer = SubtitleStabilizer()
    private var process: Process?
    private let port = 8178

    private var projectRoot: URL {
        if Bundle.main.bundleURL.pathExtension == "app" {
            return Bundle.main.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    private var serverURL: URL {
        if let resources = Bundle.main.resourceURL {
            let bundled = resources.appending(path: "whisper/bin/whisper-server")
            if FileManager.default.fileExists(atPath: bundled.path) {
                return bundled
            }
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "work/whisper.cpp/build/bin/whisper-server")
    }

    private var benchmarkDirectory: URL {
        if Bundle.main.bundleURL.pathExtension == "app",
           let applicationSupport = FileManager.default.urls(
               for: .applicationSupportDirectory,
               in: .userDomainMask
           ).first {
            return applicationSupport
                .appending(path: "LiveSubs")
                .appending(path: "benchmarks")
        }
        return projectRoot.appending(path: "work/benchmarks")
    }

    private var modelURL: URL {
        let modelNames = ["ggml-large-v3-q5_0.bin", "ggml-small.bin"]
        for name in modelNames {
            let developmentModel = projectRoot
                .appending(path: "work/whisper.cpp/models")
                .appending(path: name)
            if FileManager.default.fileExists(atPath: developmentModel.path) {
                return developmentModel
            }
        }
        if let resources = Bundle.main.resourceURL {
            for name in modelNames {
                let bundledModel = resources
                    .appending(path: "models")
                    .appending(path: name)
                if FileManager.default.fileExists(atPath: bundledModel.path) {
                    return bundledModel
                }
            }
        }
        return projectRoot
            .appending(path: "work/whisper.cpp/models/ggml-large-v3-q5_0.bin")
    }

    func start() {
        if process?.isRunning == true { return }
        guard FileManager.default.isExecutableFile(atPath: serverURL.path),
              FileManager.default.fileExists(atPath: modelURL.path) else {
            onStatus?("Offline model is not installed yet")
            return
        }

        let process = Process()
        process.executableURL = serverURL
        var arguments = [
            "--model", modelURL.path,
            "--host", "127.0.0.1",
            "--port", String(port),
            "--language", "auto",
            "--threads", "8"
        ]
        arguments.append("--translate")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            self.process = process
            onStatus?("Loading Whisper locally…")
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                self?.onStatus?("Listening and translating locally")
            }
        } catch {
            onStatus?("Could not start offline model: \(error.localizedDescription)")
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        lock.withLock {
            samples.removeAll(keepingCapacity: false)
            samplesSinceInference = 0
            isInferring = false
            stabilizer.reset()
        }
    }

    func setSourceLanguage(_ displayName: String) {
        let codes = [
            "Tamil": "ta", "Hindi": "hi", "Bengali": "bn", "Telugu": "te",
            "Malayalam": "ml", "Japanese": "ja", "Korean": "ko",
            "Spanish": "es"
        ]
        lock.withLock {
            sourceLanguage = codes[displayName] ?? "auto"
            stabilizer.reset()
        }
    }

    func beginBenchmarkCapture(seconds: Int = 20) {
        lock.withLock {
            benchmarkSamples.removeAll(keepingCapacity: true)
            benchmarkTargetCount = max(1, seconds) * 16_000
        }
        onStatus?("Capturing \(seconds)s local A/B sample…")
    }

    func append(samples newSamples: [Float], sampleRate: Double) {
        guard sampleRate == 16_000, process?.isRunning == true else { return }

        lock.lock()
        var completedBenchmark: [Float]?
        if benchmarkTargetCount > 0 {
            benchmarkSamples.append(contentsOf: newSamples)
            if benchmarkSamples.count >= benchmarkTargetCount {
                completedBenchmark = Array(
                    benchmarkSamples.prefix(benchmarkTargetCount)
                )
                benchmarkSamples.removeAll(keepingCapacity: false)
                benchmarkTargetCount = 0
            }
        }
        samples.append(contentsOf: newSamples)
        samplesSinceInference += newSamples.count

        // Keep eight seconds of context, but refresh about once per second.
        // This avoids cutting sentences at arbitrary 2.5-second boundaries.
        let maximumContext = 128_000
        if samples.count > maximumContext {
            samples.removeFirst(samples.count - maximumContext)
        }
        guard samples.count >= 32_000,
              samplesSinceInference >= 16_000,
              !isInferring else {
            lock.unlock()
            if let completedBenchmark {
                saveBenchmark(completedBenchmark)
            }
            return
        }
        let chunk = samples
        let language = sourceLanguage
        samplesSinceInference = 0
        isInferring = true
        lock.unlock()
        if let completedBenchmark {
            saveBenchmark(completedBenchmark)
        }

        Task { [weak self] in
            await self?.infer(chunk, language: language)
            self?.lock.withLock {
                self?.isInferring = false
            }
        }
    }

    private func saveBenchmark(_ samples: [Float]) {
        let file = benchmarkDirectory.appending(path: "tamil-ab-sample.wav")
        do {
            try FileManager.default.createDirectory(
                at: benchmarkDirectory,
                withIntermediateDirectories: true
            )
            try Self.wavData(samples: samples, sampleRate: 16_000)
                .write(to: file, options: .atomic)
            onStatus?("A/B sample captured locally")
            onBenchmarkCaptured?(file.path)
        } catch {
            onStatus?("Could not save A/B sample")
        }
    }

    private func infer(_ samples: [Float], language: String) async {
        do {
            let boundary = "LiveSubs-\(UUID().uuidString)"
            var body = Data()
            body.appendUTF8("--\(boundary)\r\n")
            body.appendUTF8("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
            body.appendUTF8("verbose_json\r\n")
            body.appendUTF8("--\(boundary)\r\n")
            body.appendUTF8("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
            body.appendUTF8("\(language)\r\n")
            body.appendUTF8("--\(boundary)\r\n")
            body.appendUTF8("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
            body.appendUTF8("Content-Type: audio/wav\r\n\r\n")
            body.append(Self.wavData(samples: samples, sampleRate: 16_000))
            body.appendUTF8("\r\n--\(boundary)--\r\n")

            var request = URLRequest(
                url: URL(string: "http://127.0.0.1:\(port)/inference")!
            )
            request.httpMethod = "POST"
            request.setValue(
                "multipart/form-data; boundary=\(boundary)",
                forHTTPHeaderField: "Content-Type"
            )
            request.httpBody = body
            request.timeoutInterval = 20

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                onStatus?("Offline model is warming up…")
                return
            }
            let result = try JSONDecoder().decode(InferenceResponse.self, from: data)
            let recentCutoff = max(0, result.duration - 4)
            let recentSegments = result.segments?.filter {
                $0.end >= recentCutoff && ($0.noSpeechProbability ?? 0) < 0.65
            } ?? []
            let candidate = recentSegments.isEmpty
                ? result.text
                : recentSegments.map(\.text).joined(separator: " ")
            let text = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty, text != "[BLANK_AUDIO]" {
                let stableText = lock.withLock {
                    stabilizer.ingest(text)
                }
                if let stableText {
                    onSubtitle?(stableText)
                }
            }
            onStatus?("Whisper translating locally")
        } catch {
            onStatus?("Offline model is warming up…")
        }
    }

    private static func wavData(samples: [Float], sampleRate: UInt32) -> Data {
        let pcm = samples.map {
            Int16(max(-1, min(1, $0)) * Float(Int16.max))
        }
        let dataByteCount = UInt32(pcm.count * MemoryLayout<Int16>.size)
        var data = Data()
        data.appendUTF8("RIFF")
        data.appendLE(UInt32(36) + dataByteCount)
        data.appendUTF8("WAVEfmt ")
        data.appendLE(UInt32(16))
        data.appendLE(UInt16(1))
        data.appendLE(UInt16(1))
        data.appendLE(sampleRate)
        data.appendLE(sampleRate * 2)
        data.appendLE(UInt16(2))
        data.appendLE(UInt16(16))
        data.appendUTF8("data")
        data.appendLE(dataByteCount)
        pcm.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }

    private struct InferenceResponse: Decodable {
        let text: String
        let duration: Double
        let language: String?
        let segments: [Segment]?
    }

    private struct Segment: Decodable {
        let text: String
        let end: Double
        let noSpeechProbability: Double?

        enum CodingKeys: String, CodingKey {
            case text, end
            case noSpeechProbability = "no_speech_prob"
        }
    }
}

private extension Data {
    mutating func appendUTF8(_ string: String) {
        append(string.data(using: .utf8)!)
    }

    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) {
            append(contentsOf: $0)
        }
    }
}
