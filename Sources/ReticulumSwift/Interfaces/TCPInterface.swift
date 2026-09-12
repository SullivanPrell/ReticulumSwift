//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

// Legacy stub kept for source compatibility—superseded by
// TCPClientInterface, which is wire-compatible with `RNS.Interfaces.TCPInterface`.
import Foundation

@available(*, deprecated, renamed: "TCPClientInterface")
public typealias TCPInterface = TCPClientInterface
