//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import Foundation

/// An interface another interface created, rather than one an operator configured.
///
/// Python has no such protocol: `get_interface_stats` asks
/// `hasattr(interface, "parent_interface")` and reads the attribute whatever type carries it
/// (`Reticulum.py`). Duck typing makes that uniform for free. Declaring it here is what keeps
/// the stats payload from growing one `as?` cast per spawned type—a shape in which the fifth
/// type someone adds publishes no parent, and nothing says so.
///
/// The published name and hash are the only thing distinguishing several sibling interfaces in
/// an `rnstatus` listing: clients of one server share a display name by design, and the parent
/// is what says which server, radio or tunnel each belongs to.
public protocol SpawnedInterface: Interface {
    /// The interface that created this one, or `nil` once that interface goes away.
    ///
    /// Every conformer holds its parent weakly, so this can go `nil` at any time. Upstream's
    /// `interface.parent_interface != None` guard has the same effect once Python collects it.
    var spawningInterface: (any Interface)? { get }
}
