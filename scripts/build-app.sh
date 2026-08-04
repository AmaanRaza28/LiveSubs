#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(dirname "$SCRIPT_DIR")
WHISPER_DIR="$PROJECT_ROOT/work/whisper.cpp"
MODEL_NAME=${WHISPER_MODEL:-large-v3-q5_0}
MODEL_PATH="$WHISPER_DIR/models/ggml-$MODEL_NAME.bin"
SERVER_PATH="$WHISPER_DIR/build/bin/whisper-server"
APP_PATH=${LIVE_SUBS_APP_PATH:-"$PROJECT_ROOT/outputs/LiveSubs.app"}
CONTENTS_PATH="$APP_PATH/Contents"
RESOURCES_PATH="$CONTENTS_PATH/Resources"

case "$MODEL_NAME" in
    large-v3-q5_0|small) ;;
    *)
        echo "Unsupported WHISPER_MODEL: $MODEL_NAME" >&2
        echo "Choose large-v3-q5_0 or small." >&2
        exit 1
        ;;
esac

if [ ! -x "$SERVER_PATH" ] || [ ! -f "$MODEL_PATH" ]; then
    echo "The whisper server or selected model is missing." >&2
    echo "Run WHISPER_MODEL=$MODEL_NAME ./scripts/setup-whisper.sh first." >&2
    exit 1
fi

cd "$PROJECT_ROOT"
swift build -c release

rm -rf "$APP_PATH"
mkdir -p "$CONTENTS_PATH/MacOS" "$RESOURCES_PATH/models" "$RESOURCES_PATH/whisper/bin"
cp "$PROJECT_ROOT/.build/release/LiveSubs" "$CONTENTS_PATH/MacOS/LiveSubs"
cp "$PROJECT_ROOT/Resources/Info.plist" "$CONTENTS_PATH/Info.plist"
cp "$MODEL_PATH" "$RESOURCES_PATH/models/"
cp -R "$WHISPER_DIR/build/bin/." "$RESOURCES_PATH/whisper/bin/"

codesign --force --deep --sign - "$APP_PATH"

echo "Built $APP_PATH"
echo "Open it with: open outputs/LiveSubs.app"
