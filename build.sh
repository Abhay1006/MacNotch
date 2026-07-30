#!/bin/bash
# Exit on error
set -e

APP_NAME="MacNotch"
APP_BUNDLE="${APP_NAME}.app"

echo "🔨 Building ${APP_NAME}..."

# Kill previous instances of the app
echo "🛑 Stopping any running instances of ${APP_NAME}..."
pkill -9 -f "${APP_NAME}" 2>/dev/null || killall -9 "${APP_NAME}" 2>/dev/null || true

# Compile Swift files
echo "⚙️ Compiling Swift files..."
mkdir -p ./scratch/ModuleCache
swiftc -sdk $(xcrun --show-sdk-path --sdk macosx) \
       -target arm64-apple-macosx14.0 \
       -module-cache-path ./scratch/ModuleCache \
       -O \
       -o "${APP_NAME}_binary" \
       Sources/Core/main.swift \
       Sources/Core/AppDelegate.swift \
       Sources/Views/NotchIslandView.swift \
       Sources/Managers/ClipboardManager.swift \
       Sources/Managers/MusicManager.swift \
       Sources/Managers/SystemManager.swift \
       Sources/Managers/CalendarManager.swift \
       Sources/Managers/ObsidianTaskManager.swift \
       Sources/Managers/SportsManager.swift \
       Sources/Managers/QuotesManager.swift

# Create the bundle structure
echo "📂 Creating .app bundle structure..."
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Move the compiled binary and Info.plist
mv "${APP_NAME}_binary" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp Sources/Core/Info.plist "${APP_BUNDLE}/Contents/Info.plist"

# Set executable permissions
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

echo "✅ Build Successful! Created ${APP_BUNDLE}."

if [ "$1" == "--run" ]; then
    echo "🚀 Launching ${APP_BUNDLE}..."
    open "${APP_BUNDLE}"
fi
