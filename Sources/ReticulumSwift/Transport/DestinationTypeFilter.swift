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

/// RNS 1.6.0's destination-type filter (`Transport.py:2033-2042`, `4623-4693`).
///
/// A blocked type never passes announce ingress. With ``Transport/requiredDestinationsOnly``
/// set, only allowed types and types some requester wants do. Python's requester `signature`
/// is carried but never checked ("TODO: Add requester signature validation"), so it isn't
/// taken here.
extension Transport {

  /// Python's `Destination.name_hash(full_name)`.
  static func destinationTypeHash(_ fullName: String) -> Data {
    let (appName, aspects) = Destination.appAndAspects(fromFullName: fullName)
    return Destination.computeNameHash(appName: appName, aspects: aspects)
  }

  /// Python's `block_destination_type`: also drops every client's want of the type.
  @discardableResult
  public func blockDestinationType(_ fullName: String) -> Bool {
    let nameHash = Self.destinationTypeHash(fullName)
    destinationFiltersLock.lock()
    defer { destinationFiltersLock.unlock() }
    blockedDestinationTypes.insert(nameHash)
    clientDestinationTypes[nameHash] = nil
    return true
  }

  /// Python's `allow_destination_type`.
  @discardableResult
  public func allowDestinationType(_ fullName: String) -> Bool {
    let nameHash = Self.destinationTypeHash(fullName)
    destinationFiltersLock.lock()
    defer { destinationFiltersLock.unlock() }
    allowedDestinationTypes.insert(nameHash)
    return true
  }

  /// Python's `_wants_destination_type`: `false` for a blocked type.
  @discardableResult
  public func wantsDestinationType(_ fullName: String, requester: Data) -> Bool {
    let nameHash = Self.destinationTypeHash(fullName)
    destinationFiltersLock.lock()
    defer { destinationFiltersLock.unlock() }
    guard !blockedDestinationTypes.contains(nameHash) else { return false }
    clientDestinationTypes[nameHash, default: []].insert(requester)
    return true
  }

  /// Python's `_unwants_destination_type`: `true` only when `requester` wanted the type. The
  /// type goes once no requester wants it.
  @discardableResult
  public func unwantsDestinationType(_ fullName: String, requester: Data) -> Bool {
    unwants(Self.destinationTypeHash(fullName), requester: requester)
  }

  /// Python's `_unwants_all_destination_types`.
  @discardableResult
  public func unwantsAllDestinationTypes(requester: Data) -> Bool {
    destinationFiltersLock.lock()
    let nameHashes = Array(clientDestinationTypes.keys)
    destinationFiltersLock.unlock()
    for nameHash in nameHashes { unwants(nameHash, requester: requester) }
    return true
  }

  @discardableResult
  private func unwants(_ nameHash: Data, requester: Data) -> Bool {
    destinationFiltersLock.lock()
    defer { destinationFiltersLock.unlock() }
    guard var requesters = clientDestinationTypes[nameHash] else { return false }
    let wasRegistered = requesters.remove(requester) != nil
    clientDestinationTypes[nameHash] = requesters.isEmpty ? nil : requesters
    return wasRegistered
  }

  /// The type gate at the head of announce ingress (`Transport.py:2033-2042`).
  ///
  /// `packet.hops` hasn't been incremented yet here, so Python's `hops == 1` for an announce
  /// from a local client or the shared instance is `0`. An announce too short to carry a name
  /// hash passes, and announce validation reports it as the protocol violation Python does.
  func admitsDestinationType(of packet: Packet, from interface: any Interface) -> Bool {
    let data = packet.data
    let start = data.startIndex + Constants.keySize
    guard data.count >= Constants.keySize + Constants.nameHashLength else { return true }
    let nameHash = Data(data[start..<start + Constants.nameHashLength])
    destinationFiltersLock.lock()
    defer { destinationFiltersLock.unlock() }
    if blockedDestinationTypes.contains(nameHash) { return false }
    guard requiredDestinationsOnly else { return true }
    if allowedDestinationTypes.contains(nameHash) || clientDestinationTypes[nameHash] != nil {
      return true
    }
    if isLocalClientInterface(interface) || interfaceToSharedInstance(interface) {
      return packet.hops == 0
    }
    return false
  }
}
