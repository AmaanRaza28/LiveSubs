import Foundation
import CoreGraphics
import ScreenCaptureKit

@MainActor
@Observable
final class AppModel {
    struct Source: Identifiable, Hashable {
        let id: pid_t
        let name: String
        let application: SCRunningApplication

        static func == (lhs: Source, rhs: Source) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    enum Status: Equatable {
        case idle
        case loading
        case capturing
        case failed(String)

        var label: String {
            switch self {
            case .idle: "Ready"
            case .loading: "Requesting access…"
            case .capturing: "Listening locally"
            case .failed(let message): message
            }
        }
    }

    var sources: [Source] = []
    var selectedSourceID: pid_t?
    var status: Status = .idle
    var audioLevel: Double = 0
    var provisionalSubtitle = ""
    var stableSubtitle = ""
    var isOverlayVisible = false
    var modelStatus = "Loading offline speech model…"
    var benchmarkStatus = "Capture 20s A/B Sample"
    var sourceLanguage = "Auto-detect"
    var targetLanguage = "English"

    private let capture = BrowserAudioCapture()
    private let subtitleEngine = OfflineSubtitleEngine.shared
    private var overlayController: SubtitlePanelController?

    init() {
        capture.onLevel = { [weak self] level in
            Task { @MainActor in self?.audioLevel = level }
        }
        capture.onPCM = { [weak self] samples, sampleRate in
            self?.subtitleEngine.append(samples: samples, sampleRate: sampleRate)
        }
        capture.onError = { [weak self] message in
            Task { @MainActor in
                self?.audioLevel = 0
                self?.status = .failed("Audio capture stopped: \(message)")
            }
        }
        subtitleEngine.onSubtitle = { [weak self] text in
            Task { @MainActor in
                self?.stableSubtitle = text
                self?.provisionalSubtitle = ""
            }
        }
        subtitleEngine.onStatus = { [weak self] status in
            Task { @MainActor in self?.modelStatus = status }
        }
        subtitleEngine.onBenchmarkCaptured = { [weak self] _ in
            Task { @MainActor in self?.benchmarkStatus = "A/B Sample Ready" }
        }
        subtitleEngine.start()
    }

    func refreshSources() async {
        status = .loading
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            status = .failed("Allow Screen & System Audio Recording, then restart LiveSubs")
            return
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                true,
                onScreenWindowsOnly: false
            )
            sources = content.applications
                .filter {
                    $0.processID != ProcessInfo.processInfo.processIdentifier &&
                    !$0.applicationName.isEmpty
                }
                .map { Source(id: $0.processID, name: $0.applicationName, application: $0) }
                .sorted {
                    let lhs = ApplicationDiscovery.priority(for: $0.name)
                    let rhs = ApplicationDiscovery.priority(for: $1.name)
                    return lhs == rhs
                        ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                        : lhs < rhs
                }
            if selectedSourceID == nil { selectedSourceID = sources.first?.id }
            status = .idle
        } catch {
            status = .failed("Screen Recording permission is required")
        }
    }

    func toggleCapture() async {
        if status == .capturing {
            await capture.stop()
            status = .idle
            audioLevel = 0
            return
        }
        guard let source = sources.first(where: { $0.id == selectedSourceID }) else {
            status = .failed("Choose a running browser")
            return
        }
        status = .loading
        do {
            subtitleEngine.setSourceLanguage(sourceLanguage)
            try await capture.start(application: source.application)
            status = .capturing
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func toggleSubtitleOverlay() {
        if overlayController == nil {
            overlayController = SubtitlePanelController(model: self)
        }
        guard let overlayController else { return }
        if isOverlayVisible {
            overlayController.hide()
            isOverlayVisible = false
        } else {
            overlayController.show()
            isOverlayVisible = true
        }
    }

    func captureBenchmarkSample() {
        benchmarkStatus = "Capturing 20 seconds…"
        subtitleEngine.beginBenchmarkCapture()
    }
}

enum ApplicationDiscovery {
    private static let browserHints = [
        "Helium", "Safari", "Google Chrome", "Chromium", "Firefox",
        "Arc", "Brave Browser", "Microsoft Edge", "Orion"
    ]

    static func priority(for applicationName: String) -> Int {
        browserHints.contains {
            applicationName.localizedCaseInsensitiveContains($0)
        } ? 0 : 1
    }
}
