// Thin shim: re-export the platform's system bzlib.h.
// Works on both macOS and iOS because <bzlib.h> is in all Apple SDKs.
#if __has_include(<bzlib.h>)
#include <bzlib.h>
#endif
