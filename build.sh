#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ROOT="${BUILD_ROOT:-${ROOT_DIR}/.build}"
CORE_BUILD="${BUILD_ROOT}/core"
DERIVED_DATA="${BUILD_ROOT}/DerivedData"
PACKAGE_ROOT="${BUILD_ROOT}/package"
ARTIFACT_DIR="${BUILD_ROOT}/artifacts"
BUILD_LOG="${ARTIFACT_DIR}/xcodebuild.log"

case "${BUILD_ROOT}" in
    "${ROOT_DIR}"/*) ;;
    *) echo "BUILD_ROOT must be inside the repository: ${ROOT_DIR}" >&2; exit 2 ;;
esac

command -v cmake >/dev/null || { echo "cmake is required" >&2; exit 2; }
command -v xcodebuild >/dev/null || { echo "Xcode command-line tools are required" >&2; exit 2; }
command -v xcodegen >/dev/null || {
    echo "XcodeGen is required. Install it with: brew install xcodegen" >&2
    exit 2
}

mkdir -p "${BUILD_ROOT}" "${ARTIFACT_DIR}"

cmake -S "${ROOT_DIR}" -B "${CORE_BUILD}" -DCMAKE_BUILD_TYPE=Release
cmake --build "${CORE_BUILD}" --config Release --parallel
ctest --test-dir "${CORE_BUILD}" -C Release --output-on-failure

(
    cd "${ROOT_DIR}"
    xcodegen generate --spec project.yml
)

rm -rf -- "${DERIVED_DATA}" "${PACKAGE_ROOT}"
mkdir -p "${PACKAGE_ROOT}/Payload"

set -o pipefail
xcodebuild \
    -project "${ROOT_DIR}/POClockBridge.xcodeproj" \
    -scheme POClockBridgeApp \
    -configuration Release \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "${DERIVED_DATA}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY='' \
    DEVELOPMENT_TEAM='' \
    clean build | tee "${BUILD_LOG}"

APP_PATH="${DERIVED_DATA}/Build/Products/Release-iphoneos/POClockBridgeApp.app"
APPEX_PATH="${APP_PATH}/PlugIns/POClockBridgeAU.appex"

test -d "${APP_PATH}" || { echo "Missing app bundle: ${APP_PATH}" >&2; exit 3; }
test -d "${APPEX_PATH}" || { echo "Missing embedded AUv3: ${APPEX_PATH}" >&2; exit 3; }
test -x "${APP_PATH}/POClockBridgeApp" || { echo "Missing app executable" >&2; exit 3; }
test -x "${APPEX_PATH}/POClockBridgeAU" || { echo "Missing AU executable" >&2; exit 3; }

plutil -lint "${APP_PATH}/Info.plist" "${APPEX_PATH}/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' \
    "${APPEX_PATH}/Info.plist" | grep -qx 'com.apple.AudioUnit-UI'
/usr/libexec/PlistBuddy -c \
    'Print :NSExtension:NSExtensionAttributes:AudioComponents:0:type' \
    "${APPEX_PATH}/Info.plist" | grep -qx 'aumf'

APP_ARCHS="$(lipo -archs "${APP_PATH}/POClockBridgeApp")"
AU_ARCHS="$(lipo -archs "${APPEX_PATH}/POClockBridgeAU")"
grep -qw arm64 <<<"${APP_ARCHS}"
grep -qw arm64 <<<"${AU_ARCHS}"

ditto "${APP_PATH}" "${PACKAGE_ROOT}/Payload/POClockBridgeApp.app"
IPA_PATH="${ARTIFACT_DIR}/POClockBridge-unsigned.ipa"
rm -f -- "${IPA_PATH}" "${IPA_PATH}.sha256"
(
    cd "${PACKAGE_ROOT}"
    /usr/bin/zip -qry "${IPA_PATH}" Payload
)

shasum -a 256 "${IPA_PATH}" > "${IPA_PATH}.sha256"

echo "COMPILED AND VERIFIED"
echo "App: ${APP_PATH} (${APP_ARCHS})"
echo "AUv3: ${APPEX_PATH} (${AU_ARCHS})"
echo "IPA: ${IPA_PATH}"
echo "Log: ${BUILD_LOG}"
