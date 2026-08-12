#!/bin/bash
# Run the logic tests.
#
# Compiles every app source except `main.swift` (the app's entry point) together with
# the test file, which supplies its own top-level code.
set -euo pipefail

CACHE_DIR="${HOME}/Library/Caches/MacNotch"
BUILD_DIR="${CACHE_DIR}/tests"
MODULE_CACHE="${CACHE_DIR}/ModuleCache"
mkdir -p "${BUILD_DIR}" "${MODULE_CACHE}"

SOURCES=()
while IFS= read -r source_file; do
    SOURCES+=("$source_file")
done < <(find Sources -name '*.swift' ! -name 'main.swift' | sort)

echo "🧪 Compiling ${#SOURCES[@]} sources + tests..."
swiftc -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
       -target "$(uname -m)-apple-macosx14.0" \
       -module-cache-path "${MODULE_CACHE}" \
       -o "${BUILD_DIR}/LogicTests" \
       "${SOURCES[@]}" Tests/LogicTests.swift Tests/main.swift

"${BUILD_DIR}/LogicTests"
