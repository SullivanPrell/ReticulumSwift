// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ReticulumSwift",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(name: "ReticulumSwift", targets: ["ReticulumSwift"]),
        .executable(name: "rnsd", targets: ["rnsd"])
    ],
    dependencies: [
        // CryptoKit ships with Apple platforms; for portability we may add
        // swift-crypto here in the future.
    ],
    targets: [
        // CBZip2: thin system-library module that exposes Apple's libbz2 to Swift.
        // bzlib.h and libbz2 ship in every Apple SDK (macOS, iOS, tvOS, watchOS).
        // pkgConfig = nil → SPM uses the Xcode SDK search paths directly.
        .systemLibrary(
            name: "CBZip2",
            pkgConfig: nil,
            providers: [.brew(["bzip2"]), .apt(["libbz2-dev"])]
        ),
        // CI2PD: embedded i2pd daemon static library (libi2pd + libi2pd_client + Boost + OpenSSL).
        // Provides ONLY libCI2PD.a — deliberately headerless (no `HeadersPath` in its
        // Info.plist, no `Headers/` dir in the slice). See `CI2PDCShims` below for why.
        // Built from i2pd source (https://github.com/PurpleI2P/i2pd) using:
        //   build_ci2pd_ios.sh   (see CONTRIBUTING.md → Rebuilding CI2PD)
        // Currently ships: macOS arm64, iOS arm64, iOS-Simulator arm64.
        .binaryTarget(
            name: "CI2PD",
            path: "Resources/CI2PD.xcframework"
        ),
        // CI2PDCShims: the `CI2PD` Clang module (capi.h / capi_client.h + module.modulemap)
        // as an ordinary headers-only C target — deliberately *separate* from the `CI2PD`
        // binaryTarget above.
        //
        // Why split it out: both `CI2PD.xcframework` and LXSTSwift's `codec2.xcframework`
        // used to bundle their own `Headers/module.modulemap`. When RetiOS links natively
        // for macOS, both static-library xcframeworks land in the same app product, and
        // Xcode's `ProcessXCFramework` build phase stages *each* bundled modulemap to the
        // identical shared path `$(BUILT_PRODUCTS_DIR)/include/module.modulemap` — a hard
        // "Multiple commands produce ... module.modulemap" build error, independent of the
        // two modules' differing names/content.
        //
        // Stripping CI2PD's xcframework down to a pure headerless static library means
        // `ProcessXCFramework` has no modulemap to copy for it — only codec2's remains, and
        // the collision disappears. This regular target supplies the same `module CI2PD`
        // Clang module via the normal (non-xcframework) header-map mechanism instead, which
        // never goes through `ProcessXCFramework`. See `shims.c` for more detail.
        .target(
            name: "CI2PDCShims",
            path: "Sources/CI2PDCShims",
            publicHeadersPath: "include"
        ),
        .target(
            name: "ReticulumSwift",
            dependencies: [
                "CBZip2",
                // CI2PD (binary .a) and CI2PDCShims (its Clang module).
                // Platforms: macOS arm64 always; iOS arm64 after running build_ci2pd_ios.sh.
                // The build script updates these conditions automatically once the iOS slice exists.
                .target(name: "CI2PDCShims", condition: .when(platforms: [.macOS, .iOS])),
                .target(name: "CI2PD", condition: .when(platforms: [.macOS, .iOS])),
            ],
            path: "Sources/ReticulumSwift",
            // CI2PD embeds full i2pd (C++) + Boost + OpenSSL — needs C++ runtime.
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedLibrary("c++abi"),
                // zlib — i2pd (CI2PD) references _crc32/_deflate/_deflateEnd for its
                // gzip + reseed code. libz ships in every Apple SDK (like the libbz2
                // CBZip2 already relies on). Required explicitly for the iOS / iOS-
                // simulator link; macOS happened to resolve it transitively.
                .linkedLibrary("z"),
            ]
        ),
        .executableTarget(
            name: "rnsd",
            dependencies: ["ReticulumSwift"],
            path: "Sources/rnsd",
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedLibrary("c++abi"),
                .linkedLibrary("z"),
            ]
        ),
        .testTarget(
            name: "ReticulumSwiftTests",
            dependencies: ["ReticulumSwift"],
            path: "Tests/ReticulumSwiftTests"
        )
    ]
)
