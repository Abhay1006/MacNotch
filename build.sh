#!/bin/bash
# Build MacNotch into a .app bundle.
#
#   ./build.sh              build for this machine's architecture
#   ./build.sh --run        build, then launch
#   ./build.sh --universal  build a universal (arm64 + x86_64) binary
#
set -euo pipefail

APP_NAME="MacNotch"
APP_BUNDLE="${APP_NAME}.app"
BUNDLE_ID="com.abhay.${APP_NAME}"
DEPLOYMENT_TARGET="14.0"

# Keep build artefacts out of the repo.
CACHE_DIR="${HOME}/Library/Caches/${APP_NAME}"
BUILD_DIR="${CACHE_DIR}/build"
MODULE_CACHE="${CACHE_DIR}/ModuleCache"

RUN_AFTER_BUILD=false
UNIVERSAL=false
for arg in "$@"; do
    case "$arg" in
        --run) RUN_AFTER_BUILD=true ;;
        --universal) UNIVERSAL=true ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

echo "🔨 Building ${APP_NAME}..."

echo "🛑 Stopping any running instances..."
pkill -9 -f "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}" 2>/dev/null || true

# Discover sources rather than listing them by hand — a manually maintained list
# silently drops any file you forget to add.
# (Read in a loop rather than `mapfile`, which needs bash 4; macOS ships bash 3.2.)
SOURCES=()
while IFS= read -r source_file; do
    SOURCES+=("$source_file")
done < <(find Sources -name '*.swift' | sort)
if [ ${#SOURCES[@]} -eq 0 ]; then
    echo "❌ No Swift sources found under Sources/" >&2
    exit 1
fi
echo "⚙️  Compiling ${#SOURCES[@]} Swift files..."

mkdir -p "${BUILD_DIR}" "${MODULE_CACHE}"
SDK_PATH="$(xcrun --show-sdk-path --sdk macosx)"

compile_slice() {
    local arch="$1"
    local output="$2"
    swiftc -sdk "${SDK_PATH}" \
           -target "${arch}-apple-macosx${DEPLOYMENT_TARGET}" \
           -module-cache-path "${MODULE_CACHE}" \
           -O \
           -o "${output}" \
           "${SOURCES[@]}"
}

if [ "$UNIVERSAL" = true ]; then
    echo "   → arm64"
    compile_slice arm64 "${BUILD_DIR}/${APP_NAME}-arm64"
    echo "   → x86_64"
    compile_slice x86_64 "${BUILD_DIR}/${APP_NAME}-x86_64"
    lipo -create -output "${BUILD_DIR}/${APP_NAME}" \
         "${BUILD_DIR}/${APP_NAME}-arm64" "${BUILD_DIR}/${APP_NAME}-x86_64"
else
    compile_slice "$(uname -m)" "${BUILD_DIR}/${APP_NAME}"
fi

echo "📂 Assembling ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"
cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp Sources/Core/Info.plist "${APP_BUNDLE}/Contents/Info.plist"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Ad-hoc sign with a *stable* identifier.
#
# TCC (Automation, Calendar, Accessibility) keys its grants to the code signature. An
# unsigned binary gets a fresh identity on every build, so macOS re-prompts for every
# permission each time you rebuild. Signing — even ad-hoc — keeps those grants.
#
# Distributing to another Mac still needs a Developer ID identity and notarization;
# set SIGN_IDENTITY to use one.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
echo "🔏 Signing (identity: ${SIGN_IDENTITY})..."
codesign --force --sign "${SIGN_IDENTITY}" \
         --identifier "${BUNDLE_ID}" \
         --timestamp=none \
         "${APP_BUNDLE}" >/dev/null 2>&1 || {
    echo "⚠️  Code signing failed — permissions will be re-requested on each build."
}

echo "✅ Build successful: ${APP_BUNDLE}"

if [ "$RUN_AFTER_BUILD" = true ]; then
    echo "🚀 Launching..."
    open "${APP_BUNDLE}"
fi
