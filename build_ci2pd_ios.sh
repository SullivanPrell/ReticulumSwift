#!/bin/bash
# build_ci2pd_ios.sh - Build CI2PD.xcframework with iOS arm64 and iOS Simulator arm64 slices.
#
# Prerequisites: cmake, Xcode (with iOS SDK), internet access for source downloads.
# Usage:  cd swift_devel/ReticulumSwift && bash build_ci2pd_ios.sh
# Output: Resources/CI2PD.xcframework  (macOS arm64 + iOS arm64 + iOS-Sim arm64)
#
# The existing macOS arm64 slice is preserved unchanged.
# All build artefacts go into /tmp/ci2pd_build (~3 GB; safe to delete afterwards).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XCFW="$SCRIPT_DIR/Resources/CI2PD.xcframework"
BUILD_ROOT="${BUILD_ROOT:-/tmp/ci2pd_build}"
mkdir -p "${BUILD_ROOT}"

# Pinned upstream versions (this is a deliberate, reviewed pin — NOT auto-tracked).
I2PD_VERSION="${I2PD_VERSION:-2.60.0}"
OPENSSL_VERSION="3.3.2"
BOOST_VERSION="1.90.0"
BOOST_UNDERSCORE="boost_1_90_0"
IOS_MIN="16.0"
MACOS_MIN="13.0"

# i2pd source. Not bundled with this repo — by default we clone a pinned commit.
# `capi_client.cpp` (C_StartClientServices / C_StopClientServices, required by the
# Swift I2P interface) landed AFTER the 2.60.0 release tag, so we pin the exact
# post-release commit instead of the bare tag.
# Override with a local checkout: I2PD_SRC=/path/to/i2pd bash build_ci2pd_ios.sh
I2PD_COMMIT="${I2PD_COMMIT:-af6d1442fdd661a23ea960837e0e206c589747ba}"
if [ -z "${I2PD_SRC:-}" ]; then
    I2PD_SRC="${BUILD_ROOT}/i2pd-${I2PD_COMMIT}"
    if [ ! -d "${I2PD_SRC}" ]; then
        echo "==> cloning i2pd @ ${I2PD_COMMIT} (v${I2PD_VERSION}+)"
        git clone https://github.com/PurpleI2P/i2pd "${I2PD_SRC}"
        git -C "${I2PD_SRC}" checkout --quiet "${I2PD_COMMIT}"
    fi
fi
I2PD_SRC="$(realpath "${I2PD_SRC}")"

IPHONEOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
IPHONE_SIM_SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
CLANG="$(xcrun --find clang)"
CLANGXX="$(xcrun --find clang++)"
LIBTOOL_TOOL="$(xcrun --find libtool)"
RANLIB="$(xcrun --find ranlib)"
NCPU="$(sysctl -n hw.logicalcpu)"

# Prefer Homebrew cmake (still ships FindBoost.cmake) over MacPorts cmake 3.31
# which removed FindBoost.cmake, breaking the i2pd find_package(Boost) call.
if [ -x "/opt/homebrew/bin/cmake" ]; then
    CMAKE="/opt/homebrew/bin/cmake"
else
    CMAKE="$(which cmake)"
fi
echo "==> cmake:  ${CMAKE} ($("${CMAKE}" --version | head -1))"

echo "==> i2pd source:  ${I2PD_SRC}"
echo "==> xcframework:  ${XCFW}"
echo "==> build root:   ${BUILD_ROOT}"
echo "==> iOS SDK:      ${IPHONEOS_SDK}"
echo "==> Sim SDK:      ${IPHONE_SIM_SDK}"

mkdir -p "${BUILD_ROOT}"

# -----------------------------------------------------------------------------
# 1. OpenSSL for iOS arm64 / iOS-Simulator arm64
# -----------------------------------------------------------------------------

build_openssl() {
    local PLATFORM="$1"   # ios | sim
    local OPENSSL_TARGET="$2"   # ios64-xcrun | iossimulator-xcrun
    local SDK="$3"
    local CLANG_TARGET="$4"   # arm64-apple-ios16.0 | arm64-apple-ios16.0-simulator
    local OUT="${BUILD_ROOT}/openssl-${PLATFORM}"

    if [ -d "${OUT}" ] && [ -f "${OUT}/lib/libssl.a" ]; then
        echo "==> OpenSSL (${PLATFORM}) already built - skipping"
        return
    fi

    local SRC="${BUILD_ROOT}/openssl-${OPENSSL_VERSION}"
    if [ ! -d "${SRC}" ]; then
        echo "==> Downloading OpenSSL ${OPENSSL_VERSION} ..."
        curl -fsSL \
            "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz" \
            -o "${BUILD_ROOT}/openssl.tar.gz"
        tar -xzf "${BUILD_ROOT}/openssl.tar.gz" -C "${BUILD_ROOT}"
    fi

    echo "==> Building OpenSSL ${OPENSSL_VERSION} for ${PLATFORM} ..."
    local BUILD_DIR="${BUILD_ROOT}/openssl-build-${PLATFORM}"
    cp -R "${SRC}" "${BUILD_DIR}"
    pushd "${BUILD_DIR}" > /dev/null

    export CROSS_TOP="$(dirname "$(dirname "${SDK}")")"
    export CROSS_SDK="$(basename "${SDK}")"

    # Pass the explicit clang target triple via CC so object files get the correct
    # LC_BUILD_VERSION platform tag (platform 2 = iOS device, platform 7 = iOS Simulator).
    # Without -target, iossimulator-xcrun emits platform 2 (iOS device) not 7 (Simulator).
    ./Configure \
        "${OPENSSL_TARGET}" \
        "CC=xcrun cc -target ${CLANG_TARGET}" \
        no-shared no-tests no-ui-console \
        "--prefix=${OUT}" \
        "--openssldir=${OUT}"

    make -j"${NCPU}" build_libs
    make install_dev
    popd > /dev/null
    rm -rf "${BUILD_DIR}"
    echo "==> OpenSSL (${PLATFORM}) done"
}

# -----------------------------------------------------------------------------
# 2. Boost (filesystem + program_options + atomic) for iOS arm64 / iOS-Sim arm64
# -----------------------------------------------------------------------------

build_boost() {
    local PLATFORM="$1"   # ios | sim
    local TARGET="$2"     # arm64-apple-ios16.0 | arm64-apple-ios16.0-simulator
    local SDK="$3"
    local OUT="${BUILD_ROOT}/boost-${PLATFORM}"

    if [ -d "${OUT}" ] && [ -f "${OUT}/lib/libboost_filesystem.a" ]; then
        echo "==> Boost (${PLATFORM}) already built - skipping"
        return
    fi

    local SRC="${BUILD_ROOT}/${BOOST_UNDERSCORE}"
    if [ ! -d "${SRC}" ]; then
        echo "==> Downloading Boost ${BOOST_VERSION} ..."
        curl -fsSL \
            "https://archives.boost.io/release/${BOOST_VERSION}/source/${BOOST_UNDERSCORE}.tar.bz2" \
            -o "${BUILD_ROOT}/boost.tar.bz2"
        tar -xjf "${BUILD_ROOT}/boost.tar.bz2" -C "${BUILD_ROOT}"
    fi

    echo "==> Building Boost ${BOOST_VERSION} for ${PLATFORM} ..."
    local BUILD_DIR="${BUILD_ROOT}/boost-build-${PLATFORM}"
    cp -R "${SRC}" "${BUILD_DIR}"
    pushd "${BUILD_DIR}" > /dev/null

    ./bootstrap.sh --with-toolset=clang 2>/dev/null

    cat > user-config.jam << JAMEOF
using clang : ${PLATFORM} : ${CLANGXX} :
    <compileflags>"-target ${TARGET} -isysroot ${SDK} -mios-version-min=${IOS_MIN}"
    <linkflags>"-target ${TARGET} -isysroot ${SDK} -mios-version-min=${IOS_MIN}"
    ;
JAMEOF

    ./b2 \
        "--user-config=user-config.jam" \
        "toolset=clang-${PLATFORM}" \
        target-os=iphone \
        architecture=arm \
        address-model=64 \
        variant=release \
        link=static \
        threading=multi \
        runtime-link=static \
        --with-filesystem \
        --with-program_options \
        --with-atomic \
        "--prefix=${OUT}" \
        "--build-dir=${BUILD_ROOT}/boost-bjam-${PLATFORM}" \
        "-j${NCPU}" \
        install 2>&1 | tail -5

    popd > /dev/null
    rm -rf "${BUILD_DIR}" "${BUILD_ROOT}/boost-bjam-${PLATFORM}"
    echo "==> Boost (${PLATFORM}) done"
}

# -----------------------------------------------------------------------------
# 3. Build i2pd as a merged static lib
# -----------------------------------------------------------------------------

build_i2pd() {
    local PLATFORM="$1"   # ios | sim
    local TARGET="$2"
    local SDK="$3"
    local OPENSSL_DIR="${BUILD_ROOT}/openssl-${PLATFORM}"
    local BOOST_DIR="${BUILD_ROOT}/boost-${PLATFORM}"
    local OUT="${BUILD_ROOT}/i2pd-${PLATFORM}"

    if [ -d "${OUT}" ] && [ -f "${OUT}/libCI2PD.a" ]; then
        echo "==> i2pd (${PLATFORM}) already built - skipping"
        return
    fi

    echo "==> Building i2pd for ${PLATFORM} (${TARGET}) ..."
    # Wipe cmake dir only if the compiled libs are absent (avoids full recompile
    # when re-running after a capi/libtool-only failure).
    if [ ! -f "${OUT}/cmake/libi2pd.a" ]; then
        rm -rf "${OUT}/cmake"
    fi
    mkdir -p "${OUT}/cmake"
    pushd "${OUT}/cmake" > /dev/null

    "${CMAKE}" "${I2PD_SRC}/build" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${IOS_MIN}" \
        -DCMAKE_OSX_SYSROOT="${SDK}" \
        -DCMAKE_C_COMPILER="${CLANG}" \
        -DCMAKE_CXX_COMPILER="${CLANGXX}" \
        -DCMAKE_C_FLAGS="-target ${TARGET} -isysroot ${SDK}" \
        -DCMAKE_CXX_FLAGS="-target ${TARGET} -isysroot ${SDK} -std=c++17" \
        -DCMAKE_EXE_LINKER_FLAGS="-target ${TARGET}" \
        -DCMAKE_SHARED_LINKER_FLAGS="-target ${TARGET}" \
        -DWITH_BINARY=OFF \
        -DWITH_LIBRARY=ON \
        -DWITH_STATIC=ON \
        -DWITH_UPNP=OFF \
        -DBUILD_TESTING=OFF \
        -DBoost_NO_BOOST_CMAKE=ON \
        -DBoost_NO_SYSTEM_PATHS=ON \
        -DBoost_USE_STATIC_LIBS=ON \
        -DBoost_USE_STATIC_RUNTIME=ON \
        -DBOOST_ROOT="${BOOST_DIR}" \
        -DBoost_ROOT="${BOOST_DIR}" \
        -DBoost_INCLUDE_DIR="${BOOST_DIR}/include" \
        -DBoost_FILESYSTEM_LIBRARY_RELEASE="${BOOST_DIR}/lib/libboost_filesystem.a" \
        -DBoost_PROGRAM_OPTIONS_LIBRARY_RELEASE="${BOOST_DIR}/lib/libboost_program_options.a" \
        -DBoost_ATOMIC_LIBRARY_RELEASE="${BOOST_DIR}/lib/libboost_atomic.a" \
        -DOPENSSL_ROOT_DIR="${OPENSSL_DIR}" \
        -DOPENSSL_USE_STATIC_LIBS=ON \
        -DOPENSSL_INCLUDE_DIR="${OPENSSL_DIR}/include" \
        -DOPENSSL_CRYPTO_LIBRARY="${OPENSSL_DIR}/lib/libcrypto.a" \
        -DOPENSSL_SSL_LIBRARY="${OPENSSL_DIR}/lib/libssl.a" \
        -DZLIB_INCLUDE_DIR="${SDK}/usr/include" \
        -DZLIB_LIBRARY="${SDK}/usr/lib/libz.tbd"

    "${CMAKE}" --build . --config Release "-j${NCPU}"
    popd > /dev/null

    echo "==> Compiling C API wrapper for ${PLATFORM} ..."
    local CFLAGS="-target ${TARGET} -isysroot ${SDK} -mios-version-min=${IOS_MIN}"
    local CXXFLAGS="${CFLAGS} -std=c++17 -DMAC_OSX"
    local SHIMS_INC="${SCRIPT_DIR}/Sources/CI2PDCShims/include"
    local INC="-I${I2PD_SRC}/libi2pd -I${I2PD_SRC}/libi2pd_client -I${I2PD_SRC}/i18n -I${SHIMS_INC} -I${BOOST_DIR}/include -I${OPENSSL_DIR}/include"

    "${CLANGXX}" ${CXXFLAGS} ${INC} \
        -c "${I2PD_SRC}/libi2pd_wrapper/capi.cpp" \
        -o "${OUT}/capi.cpp.o"

    "${CLANGXX}" ${CXXFLAGS} ${INC} \
        -c "${I2PD_SRC}/libi2pd_wrapper/capi_client.cpp" \
        -o "${OUT}/capi_client.cpp.o"

    echo "==> Merging all objects into libCI2PD.a for ${PLATFORM} ..."

    "${LIBTOOL_TOOL}" -static \
        "${OUT}/cmake/libi2pd.a" \
        "${OUT}/cmake/libi2pdclient.a" \
        "${OUT}/cmake/libi2pdlang.a" \
        "${OPENSSL_DIR}/lib/libssl.a" \
        "${OPENSSL_DIR}/lib/libcrypto.a" \
        "${BOOST_DIR}/lib/libboost_filesystem.a" \
        "${BOOST_DIR}/lib/libboost_program_options.a" \
        "${OUT}/capi.cpp.o" \
        "${OUT}/capi_client.cpp.o" \
        -o "${OUT}/libCI2PD.a"

    "${RANLIB}" "${OUT}/libCI2PD.a"

    local SIZE
    SIZE="$(du -sh "${OUT}/libCI2PD.a" | cut -f1)"
    echo "==> i2pd (${PLATFORM}) done: ${SIZE}"
}

# -----------------------------------------------------------------------------
# 3b. Build i2pd for macOS arm64 (native). OpenSSL + Boost come from Homebrew —
#     this mirrors how the original macОS slice was produced. i2pd itself is the
#     pinned 2.60.0 source, same as the iOS slices. Run `brew install boost
#     openssl@3` first (the CI workflow does this).
# -----------------------------------------------------------------------------

build_i2pd_macos() {
    local OUT="${BUILD_ROOT}/i2pd-mac"
    if [ -d "${OUT}" ] && [ -f "${OUT}/libCI2PD.a" ]; then
        echo "==> i2pd (macos) already built - skipping"; return
    fi
    local OPENSSL_DIR BOOST_DIR
    OPENSSL_DIR="$(brew --prefix openssl@3)"
    BOOST_DIR="$(brew --prefix boost)"
    echo "==> Building i2pd for macOS arm64 (Homebrew OpenSSL/Boost) ..."
    rm -rf "${OUT}/cmake"; mkdir -p "${OUT}/cmake"
    pushd "${OUT}/cmake" > /dev/null
    "${CMAKE}" "${I2PD_SRC}/build" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${MACOS_MIN}" \
        -DBUILD_SHARED_LIBS=OFF \
        -DWITH_LIBRARY=ON -DWITH_BINARY=OFF -DWITH_STATIC=ON \
        -DWITH_UPNP=OFF -DBUILD_TESTING=OFF \
        -DOPENSSL_ROOT_DIR="${OPENSSL_DIR}" \
        -DOPENSSL_USE_STATIC_LIBS=ON \
        -DBOOST_ROOT="${BOOST_DIR}" \
        -DBoost_USE_STATIC_LIBS=ON
    "${CMAKE}" --build . --config Release "-j${NCPU}"
    popd > /dev/null

    echo "==> Compiling C API wrapper for macOS ..."
    local MACOS_SDK; MACOS_SDK="$(xcrun --sdk macosx --show-sdk-path)"
    local CXXFLAGS="-target arm64-apple-macos${MACOS_MIN} -isysroot ${MACOS_SDK} -mmacosx-version-min=${MACOS_MIN} -std=c++17 -DMAC_OSX"
    local SHIMS_INC="${SCRIPT_DIR}/Sources/CI2PDCShims/include"
    local INC="-I${I2PD_SRC}/libi2pd -I${I2PD_SRC}/libi2pd_client -I${I2PD_SRC}/i18n -I${SHIMS_INC} -I${BOOST_DIR}/include -I${OPENSSL_DIR}/include"
    "${CLANGXX}" ${CXXFLAGS} ${INC} -c "${I2PD_SRC}/libi2pd_wrapper/capi.cpp"        -o "${OUT}/capi.cpp.o"
    "${CLANGXX}" ${CXXFLAGS} ${INC} -c "${I2PD_SRC}/libi2pd_wrapper/capi_client.cpp" -o "${OUT}/capi_client.cpp.o"

    echo "==> Merging objects into libCI2PD.a for macOS ..."
    "${LIBTOOL_TOOL}" -static \
        "${OUT}/cmake/libi2pd.a" \
        "${OUT}/cmake/libi2pdclient.a" \
        "${OUT}/cmake/libi2pdlang.a" \
        "${OPENSSL_DIR}/lib/libssl.a" \
        "${OPENSSL_DIR}/lib/libcrypto.a" \
        "${BOOST_DIR}/lib/libboost_filesystem.a" \
        "${BOOST_DIR}/lib/libboost_program_options.a" \
        "${OUT}/capi.cpp.o" \
        "${OUT}/capi_client.cpp.o" \
        -o "${OUT}/libCI2PD.a"
    "${RANLIB}" "${OUT}/libCI2PD.a"
    echo "==> i2pd (macos) done: $(du -sh "${OUT}/libCI2PD.a" | cut -f1)"
}

# -----------------------------------------------------------------------------
# 4. Rebuild xcframework (macOS + iOS + iOS-simulator, all built from source)
# -----------------------------------------------------------------------------

rebuild_xcframework() {
    local IOS_LIB="${BUILD_ROOT}/i2pd-ios/libCI2PD.a"
    local SIM_LIB="${BUILD_ROOT}/i2pd-sim/libCI2PD.a"
    local MACOS_LIB="${BUILD_ROOT}/i2pd-mac/libCI2PD.a"

    # CI2PD.xcframework is deliberately headerless: headers are provided by the
    # separate CI2PDCShims SPM target (capi.h + capi_client.h + module.modulemap).
    # Bundling headers here causes a "Multiple commands produce module.modulemap"
    # collision with codec2.xcframework. See Package.swift for the full explanation.
    local ARGS=(
        -create-xcframework
        -library "${MACOS_LIB}"
        -library "${IOS_LIB}"
    )

    if [ -f "${SIM_LIB}" ]; then
        ARGS+=(-library "${SIM_LIB}")
    fi

    local TMP_XCF="${BUILD_ROOT}/CI2PD.xcframework"
    rm -rf "${TMP_XCF}"
    echo "==> Creating xcframework ..."
    xcodebuild "${ARGS[@]}" -output "${TMP_XCF}"

    rm -rf "${XCFW}"
    cp -R "${TMP_XCF}" "${XCFW}"
    echo "==> xcframework updated: ${XCFW}"
    plutil -p "${XCFW}/Info.plist" | grep -E "SupportedPlatform|LibraryIdentifier"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

echo ""
echo "======================================================"
echo " Phase 1 - OpenSSL"
echo "======================================================"
build_openssl ios "ios64-xcrun"         "${IPHONEOS_SDK}"  "arm64-apple-ios${IOS_MIN}"
build_openssl sim "iossimulator-xcrun"  "${IPHONE_SIM_SDK}" "arm64-apple-ios${IOS_MIN}-simulator"

echo ""
echo "======================================================"
echo " Phase 2 - Boost"
echo "======================================================"
build_boost ios "arm64-apple-ios${IOS_MIN}"            "${IPHONEOS_SDK}"
build_boost sim "arm64-apple-ios${IOS_MIN}-simulator"  "${IPHONE_SIM_SDK}"

echo ""
echo "======================================================"
echo " Phase 3 - i2pd (iOS device + simulator, then macOS)"
echo "======================================================"
build_i2pd ios "arm64-apple-ios${IOS_MIN}"            "${IPHONEOS_SDK}"
build_i2pd sim "arm64-apple-ios${IOS_MIN}-simulator"  "${IPHONE_SIM_SDK}"
build_i2pd_macos

echo ""
echo "======================================================"
echo " Phase 4 - xcframework"
echo "======================================================"
rebuild_xcframework

echo ""
echo "======================================================"
echo " Phase 5 - package (zip + SwiftPM checksum)"
echo "======================================================"
( cd "${SCRIPT_DIR}/Resources" && rm -f CI2PD.xcframework.zip && zip -q -r -y CI2PD.xcframework.zip CI2PD.xcframework )
echo "==> CI2PD.xcframework.zip ready:"
swift package compute-checksum "${SCRIPT_DIR}/Resources/CI2PD.xcframework.zip"

echo ""
echo "Done."
echo "  Build artefacts in ${BUILD_ROOT} (safe to delete - approx 3 GB)."
echo "  Run 'swift build' in ReticulumSwift to verify."
echo "  Run 'swift test'  to check for regressions."
