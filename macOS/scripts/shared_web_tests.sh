#!/bin/bash

set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-$(realpath "$(dirname "$0")"/../..)}"
SHARED_WEB_TESTS_DIR="${PROJECT_ROOT}/tmp/shared-web-tests"
DERIVED_DATA_PATH="${PROJECT_ROOT}/DerivedData"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-Release}"
MACOS_APP_NAME="${MACOS_APP_NAME:-DuckDuckGo}"
MACOS_EXECUTABLE_NAME="${MACOS_EXECUTABLE_NAME:-DuckDuckGo}"
MACOS_APP_BUNDLE_ID="${MACOS_APP_BUNDLE_ID:-com.duckduckgo.macos.browser}"
DDG_PLATFORM=macos

export PROJECT_ROOT
export DERIVED_DATA_PATH
export BUILD_CONFIGURATION
export MACOS_APP_NAME
export MACOS_EXECUTABLE_NAME
export MACOS_APP_BUNDLE_ID
export DDG_PLATFORM

check_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "‼️ Error: $1 is not installed."
        exit 1
    fi
}

check_command cargo
check_command npm
check_command python3
check_command xcodebuild
check_command xcbeautify

if [ "${1:-}" = "--clean" ]; then
    echo "Clearing tmp and DerivedData directories"
    rm -rf "${PROJECT_ROOT}/tmp" "${DERIVED_DATA_PATH}"
fi

mkdir -p "${PROJECT_ROOT}/tmp"

if [ ! -d "${SHARED_WEB_TESTS_DIR}" ]; then
    if [ -d "${PROJECT_ROOT}/../shared-web-tests" ]; then
        ln -s "${PROJECT_ROOT}/../shared-web-tests" "${SHARED_WEB_TESTS_DIR}"
    else
        git clone --recurse-submodules https://github.com/duckduckgo/shared-web-tests.git "${SHARED_WEB_TESTS_DIR}"
    fi
fi

cd "${PROJECT_ROOT}/macOS"

echo "Building macOS Browser"
/bin/sh -c 'set -e -o pipefail && xcodebuild \
    -workspace "'"${PROJECT_ROOT}"'/DuckDuckGo.xcworkspace" \
    -scheme "macOS Browser" \
    -configuration "'"${BUILD_CONFIGURATION}"'" \
    -derivedDataPath "'"${DERIVED_DATA_PATH}"'" \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    | xcbeautify'

defaults write "${MACOS_APP_BUNDLE_ID}" moveToApplicationsFolderAlertSuppress -bool true
defaults write "${MACOS_APP_BUNDLE_ID}" onboarding.finished -bool true

cd "${SHARED_WEB_TESTS_DIR}"

if ! npm run build; then
    echo "‼️ Error: npm build failed."
    exit 1
fi

if ! grep -q "Start web-platform-tests hosts" /etc/hosts; then
    echo "Installing hosts, sudo required"
    sudo -- sh -c 'npm run install-hosts'
else
    echo "Hosts already installed, skipping"
fi

echo "Starting macOS shared web tests"
npm run test | tee "${PROJECT_ROOT}/tmp/test_out_$(date +"%Y%m%d_%H%M%S").log"
