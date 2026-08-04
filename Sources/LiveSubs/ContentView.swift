import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text("LiveSubs")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Private, on-device subtitles for browser video")
                    .foregroundStyle(.secondary)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Browser", selection: $model.selectedSourceID) {
                        Text("Choose a running browser").tag(nil as pid_t?)
                        ForEach(model.sources) { source in
                            Text(source.name).tag(source.id as pid_t?)
                        }
                    }

                    HStack {
                        Picker("Spoken", selection: $model.sourceLanguage) {
                            Text("Auto-detect").tag("Auto-detect")
                            Text("Tamil").tag("Tamil")
                            Text("Hindi").tag("Hindi")
                            Text("Bengali").tag("Bengali")
                            Text("Telugu").tag("Telugu")
                            Text("Malayalam").tag("Malayalam")
                            Text("Japanese").tag("Japanese")
                            Text("Korean").tag("Korean")
                            Text("Spanish").tag("Spanish")
                        }
                        Picker("Subtitles", selection: $model.targetLanguage) {
                            Text("English").tag("English")
                        }
                    }
                }
                .padding(6)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle()
                        .fill(model.status == .capturing ? .green : .secondary)
                        .frame(width: 8, height: 8)
                    Text(model.status.label)
                        .font(.callout.weight(.medium))
                    Spacer()
                    Text("Audio stays on this Mac")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: model.audioLevel)
                    .tint(.green)
                Text(
                    model.status == .capturing
                        ? model.modelStatus
                        : "Offline multilingual speech-to-English translation"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack {
                Button("Refresh Browsers") {
                    Task { await model.refreshSources() }
                }
                Button(model.benchmarkStatus) {
                    model.captureBenchmarkSample()
                }
                .disabled(
                    model.status != .capturing ||
                    model.benchmarkStatus == "Capturing 20 seconds…"
                )
                Spacer()
                Button(model.isOverlayVisible ? "Hide Subtitle Overlay" : "Show Subtitle Overlay") {
                    model.toggleSubtitleOverlay()
                }
                Button(model.status == .capturing ? "Stop Listening" : "Start Listening") {
                    Task { await model.toggleCapture() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(26)
        .task { await model.refreshSources() }
    }
}

struct SubtitleOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Spacer()
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.42))
                    .help("Drag anywhere on the subtitle panel to move it")
            }
            Text(model.stableSubtitle.isEmpty ? "Subtitles will appear here" : model.stableSubtitle)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(model.stableSubtitle.isEmpty ? Color.secondary : Color.white)
            if !model.provisionalSubtitle.isEmpty {
                Text(model.provisionalSubtitle)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 26)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
    }
}
