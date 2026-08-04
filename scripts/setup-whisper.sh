#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(dirname "$SCRIPT_DIR")
WHISPER_DIR="$PROJECT_ROOT/work/whisper.cpp"
MODEL_NAME=${WHISPER_MODEL:-large-v3-q5_0}

case "$MODEL_NAME" in
    large-v3-q5_0|small) ;;
    *)
        echo "Unsupported WHISPER_MODEL: $MODEL_NAME" >&2
        echo "Choose large-v3-q5_0 or small." >&2
        exit 1
        ;;
esac

if ! command -v cmake >/dev/null 2>&1; then
    echo "CMake is required. Install it with: brew install cmake" >&2
    exit 1
fi

if [ ! -d "$WHISPER_DIR/.git" ]; then
    mkdir -p "$(dirname "$WHISPER_DIR")"
    git clone --depth 1 https://github.com/ggml-org/whisper.cpp.git "$WHISPER_DIR"
fi

cmake \
    -S "$WHISPER_DIR" \
    -B "$WHISPER_DIR/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DWHISPER_BUILD_SERVER=ON \
    -DGGML_METAL=ON
cmake --build "$WHISPER_DIR/build" --config Release --target whisper-server -j

"$WHISPER_DIR/models/download-ggml-model.sh" "$MODEL_NAME"

echo
echo "LiveSubs inference setup is ready."
echo "Model: $WHISPER_DIR/models/ggml-$MODEL_NAME.bin"
echo "Run from the repository root with: swift run"
