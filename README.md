# LiveSubs

LiveSubs is a private, fully offline macOS subtitle overlay for browser video. It captures audio from one selected application with ScreenCaptureKit, transcribes or translates it locally with [whisper.cpp](https://github.com/ggml-org/whisper.cpp), and displays English subtitles in a movable panel over full-screen video.

Audio, transcripts, and inference stay on your Mac. The only network access needed is the one-time download of whisper.cpp and a Whisper model during setup.

## Features

- Captures only the application you select, with browsers sorted first.
- Converts captured audio to mono 16 kHz PCM in memory.
- Translates Tamil, Hindi, Bengali, Telugu, Malayalam, Japanese, Korean, Spanish, or auto-detected speech into English.
- Uses a rolling context window and subtitle stabilization to reduce repeated rewrites.
- Shows an input meter and a draggable subtitle overlay across Spaces and full-screen apps.
- Can save an optional 20-second WAV sample locally for model comparisons.

## Requirements

- macOS 15 or later.
- Xcode 16 or later, or matching Xcode Command Line Tools.
- Git and CMake (`brew install cmake` if CMake is not installed).
- An Apple Silicon Mac is recommended for practical inference speed.
- About 2 GB of free space for the default model, dependencies, and build output.

## Setup

Clone the repository, then run the setup script from its root:

```sh
git clone <repository-url>
cd LiveSubs
./scripts/setup-whisper.sh
```

The script clones whisper.cpp into the ignored `work/` directory, builds its local HTTP server with Metal support, and downloads the quantized `large-v3` model. This model is roughly 1 GB, so setup can take a while.

To use the smaller and faster Whisper model instead:

```sh
WHISPER_MODEL=small ./scripts/setup-whisper.sh
```

## Run from source

Keep the working directory at the repository root so LiveSubs can find the local server and model:

```sh
swift run
```

Running this way associates Screen Recording permission with your terminal. For normal use, building the app bundle is recommended.

## Build the macOS app

After setup, create a self-contained, ad-hoc-signed app bundle:

```sh
./scripts/build-app.sh
open outputs/LiveSubs.app
```

The build script bundles whichever supported model is installed. Set `WHISPER_MODEL=small` if both models exist and you want the smaller one:

```sh
WHISPER_MODEL=small ./scripts/build-app.sh
```

The resulting app is intended for local builds. Distributing a binary to other Macs requires your own Apple Developer signing and notarization.

## First launch and usage

1. Open LiveSubs and approve **Screen & System Audio Recording** when macOS asks.
2. If permission was just granted, quit and reopen LiveSubs.
3. Start a video in your browser, select that browser in LiveSubs, and choose the spoken language or auto-detect.
4. Select **Show Subtitle Overlay**, then **Start Listening**.
5. Drag anywhere on the subtitle panel to position it over the video.

If the browser is missing, make sure it is running and select **Refresh Browsers**.

## Development

Build and run all tests with:

```sh
swift test
```

The Swift package contains no third-party Swift dependencies. Runtime inference is supplied by the separately downloaded whisper.cpp server and model.

## Local files and privacy

Generated files are excluded from Git:

- `.build/` contains Swift build output.
- `work/` contains whisper.cpp, models, and optional benchmark audio.
- `outputs/` contains the generated app bundle.

LiveSubs does not upload captured audio or subtitle text. The **Capture 20s A/B Sample** button is the only feature that writes captured audio. App builds save it under `~/Library/Application Support/LiveSubs/benchmarks/`; `swift run` saves it under `work/benchmarks/`.

## Troubleshooting

- **“Offline model is not installed yet”** — rerun `./scripts/setup-whisper.sh` from the repository root.
- **No browsers appear** — enable LiveSubs (or your terminal when using `swift run`) in System Settings → Privacy & Security → Screen & System Audio Recording, then restart it.
- **Subtitles are slow** — use `WHISPER_MODEL=small` during setup and when building the app.
- **The app bundle stops working after changes** — rerun `./scripts/build-app.sh`; it rebuilds and signs the bundle.

## License

LiveSubs is available under the [MIT License](LICENSE). whisper.cpp and downloaded model files retain their own licenses.
