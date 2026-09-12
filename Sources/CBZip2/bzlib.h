//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

// Thin shim: re-export the platform's system bzlib.h.
// Works on both macOS and iOS because <bzlib.h> is in all Apple SDKs.
#if __has_include(<bzlib.h>)
#include <bzlib.h>
#endif
