/*
 * CI2PDCShims — headers-only Clang module for the embedded i2pd daemon.
 *
 * Why this exists (and why it's a *separate* target from the `CI2PD`
 * binaryTarget rather than headers bundled inside the xcframework):
 *
 * Both `CI2PD.xcframework` (this package, macOS-only) and
 * `codec2.xcframework` (LXSTSwift, all platforms) used to bundle their own
 * `Headers/module.modulemap`. When RetiOS links natively for macOS, both
 * static-library xcframeworks land in the same app product and Xcode's
 * `ProcessXCFramework` build phase stages *both* bundled `module.modulemap`
 * files to the exact same shared path
 * `$(BUILT_PRODUCTS_DIR)/include/module.modulemap` — a hard
 * "Multiple commands produce ... module.modulemap" build-system error,
 * regardless of the two modulemaps' differing module names or content.
 *
 * The fix: strip `CI2PD.xcframework` down to a pure headerless static
 * library (no `HeadersPath` in its `Info.plist`, so `ProcessXCFramework`
 * has nothing to copy and never emits that command for it), and move its
 * tiny hand-written C API surface — `capi.h` / `capi_client.h` plus the
 * `module CI2PD { ... }` modulemap that exposes them to Swift — into this
 * ordinary source target instead. SPM/Xcode handle a regular target's
 * `include/module.modulemap` via the normal header-map mechanism, which
 * doesn't collide with anything.
 *
 * This file exists only because SPM requires at least one compiled source
 * in a non-binary, non-system-library target; the actual i2pd object code
 * still comes from `libCI2PD.a` in the (now headerless) `CI2PD` binaryTarget,
 * which `ReticulumSwift` links directly alongside this module.
 */

/* Intentionally no symbols — see comment above. */
