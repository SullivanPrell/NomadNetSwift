//===----------------------------------------------------------------------===//
// Copyright (c) 2026 NomadNetSwift contributors.
//
// Licensed under the GNU General Public License, version 3 (GPL-3.0). See
// LICENSE in the repository root for the full license text, and NOTICE for
// attribution of the upstream project this file is derived from.
//
// SPDX-License-Identifier: GPL-3.0-only
//===----------------------------------------------------------------------===//

import Foundation
import ReticulumSwift

// MARK: - DirectoryEntry

/// A single entry in the NomadNet node/peer directory.
///
/// Corresponds to Python `DirectoryEntry` in `nomadnet/Directory.py`.
public struct DirectoryEntry {

  // MARK:–Trust level constants (Python: WARNING, UNTRUSTED, UNKNOWN, TRUSTED)

  /// Trust a directory entry is held at.
  public enum TrustLevel: UInt8, Equatable, Comparable, Codable {
    case warning = 0x00
    case untrusted = 0x01
    case unknown = 0x02
    case trusted = 0xFF

    /// Orders trust levels from least to most trusted.
    public static func < (lhs: TrustLevel, rhs: TrustLevel) -> Bool {
      lhs.rawValue < rhs.rawValue
    }
  }

  // MARK:–Delivery mode constants (Python: DIRECT, PROPAGATED)

  /// Route messages to the entry are sent over.
  public enum Delivery: UInt8, Equatable, Codable {
    case direct = 0x01
    case propagated = 0x02
  }

  // MARK:–Properties

  /// 10-byte truncated identity hash of the destination.
  public var sourceHash: Data

  /// Human-readable display name.
  public var displayName: String?

  /// Trust level assigned to this entry.
  public var trustLevel: TrustLevel

  /// `true` if this peer is known to run a NomadNet node.
  public var hostsNode: Bool

  /// Preferred message delivery method.
  public var preferredDelivery: Delivery

  /// Whether to send an identity upon connecting.
  public var identify: Bool

  /// Optional numeric sort rank (lower = higher in lists).
  public var sortRank: Int?

  /// Optional user notes.
  public var notes: String

  // MARK:–Init

  /// Creates an entry for `sourceHash`.
  public init(
    sourceHash: Data,
    displayName: String? = nil,
    trustLevel: TrustLevel = .unknown,
    hostsNode: Bool = false,
    preferredDelivery: Delivery = .direct,
    identify: Bool = false,
    sortRank: Int? = nil,
    notes: String = ""
  ) {
    self.sourceHash = sourceHash
    self.displayName = displayName
    self.trustLevel = trustLevel
    self.hostsNode = hostsNode
    self.preferredDelivery = preferredDelivery
    self.identify = identify
    self.sortRank = sortRank
    self.notes = notes
  }
}

// MARK: - AnnounceRecord

/// A timestamped announce entry in the directory stream.
///
/// Corresponds to Python's `(timestamp, source_hash, app_data, kind)` tuples.
public struct AnnounceRecord {
  /// Time the announce was received.
  public let timestamp: Date
  /// Destination hash the announce came from.
  public let sourceHash: Data
  /// Application data the announce carried.
  public let appData: Data?
  /// `"node"`, `"peer"`, or `"pn"`.
  public let kind: String

  /// Creates a record of a received announce.
  public init(timestamp: Date, sourceHash: Data, appData: Data?, kind: String) {
    self.timestamp = timestamp
    self.sourceHash = sourceHash
    self.appData = appData
    self.kind = kind
  }
}

// MARK: - NNDirectory

/// In-memory directory of known NomadNet nodes and LXMF peers.
///
/// Corresponds to Python `Directory` in `nomadnet/Directory.py`.
///
/// - Stores `DirectoryEntry` values keyed by 10-byte source hash.
/// - Tracks rolling announce streams (node, peer, propagation-node).
/// - Persists entries to disk via msgpack (through the `save(to:)` / `load(from:)` API).
public class NNDirectory {

  // MARK:–Constants

  /// Maximum number of announces kept in each stream.
  ///
  /// Python: `Directory.ANNOUNCE_STREAM_MAXLENGTH = 256`.
  public static let announceStreamMaxLength: Int = 256

  /// Announce handler aspect filter for NomadNet nodes.
  public static let aspectFilter: String = "nomadnetwork.node"

  // MARK:–Directory entries

  /// The primary map from source hash → entry.
  public private(set) var directoryEntries: [Data: DirectoryEntry] = [:]

  // MARK:–Announce streams

  /// Node announces (newest first).
  ///
  /// Python: `self._node_announces`.
  public private(set) var nodeAnnounces: [AnnounceRecord] = []

  /// Peer announces (newest first).
  ///
  /// Python: `self._peer_announces`.
  public private(set) var peerAnnounces: [AnnounceRecord] = []

  /// Propagation-node announces (newest first).
  ///
  /// Python: `self._pn_announces`.
  public private(set) var pnAnnounces: [AnnounceRecord] = []

  // MARK:–Init

  /// Creates an empty directory.
  public init() {}

  // MARK:–Announce management

  /// Adds a new node announce to the stream.
  @available(
    *, deprecated,
    message:
      "Unused, and not in Python; use nodeAnnounceReceived(sourceHash:appData:associatedPeer:)."
  )
  public func addNodeAnnounce(_ record: AnnounceRecord) {
    nodeAnnounces.insert(record, at: 0)
    if nodeAnnounces.count > NNDirectory.announceStreamMaxLength {
      nodeAnnounces.removeLast()
    }
  }

  /// Adds a new peer announce to the stream.
  @available(
    *, deprecated,
    message: "Unused, and not in Python; use peerAnnounceReceived(sourceHash:appData:)."
  )
  public func addPeerAnnounce(_ record: AnnounceRecord) {
    peerAnnounces.insert(record, at: 0)
    if peerAnnounces.count > NNDirectory.announceStreamMaxLength {
      peerAnnounces.removeLast()
    }
  }

  /// Adds a new PN announce to the stream.
  @available(
    *, deprecated,
    message:
      "Unused, and not in Python; use pnAnnounceReceived(sourceHash:appData:associatedPeer:associatedNode:)."
  )
  public func addPNAnnounce(_ record: AnnounceRecord) {
    pnAnnounces.insert(record, at: 0)
    if pnAnnounces.count > NNDirectory.announceStreamMaxLength {
      pnAnnounces.removeLast()
    }
  }

  // MARK:–Combined stream (Python: Directory.announce_stream property)

  /// All announce records across node, peer, and PN streams.
  public var announceStream: [AnnounceRecord] {
    nodeAnnounces + peerAnnounces + pnAnnounces
  }

  // MARK:–Entry management (Python: remember / forget / find)

  /// Store or overwrite an entry.
  ///
  /// Python: `Directory.remember(entry)`.
  /// A peer's trust also goes to the node its identity hosts. Python then saves to disk;
  /// this directory has no path, so the caller saves.
  public func remember(_ entry: DirectoryEntry) {
    directoryEntries[entry.sourceHash] = entry
    if let identity = Identity.recall(destinationHash: entry.sourceHash) {
      let node = Destination.hash(fromFullName: "nomadnetwork.node", identity: identity)
      directoryEntries[node]?.trustLevel = entry.trustLevel
    }
  }

  /// Remove the entry with `sourceHash` if it exists.
  ///
  /// Python: `Directory.forget(source_hash)`.
  public func forget(_ sourceHash: Data) {
    directoryEntries.removeValue(forKey: sourceHash)
  }

  /// Return the entry for `sourceHash`, or `nil` if not known.
  ///
  /// Python: `Directory.find(source_hash)`.
  public func find(_ sourceHash: Data) -> DirectoryEntry? {
    directoryEntries[sourceHash]
  }

  // MARK:–Trust / display queries

  /// Trust level for `sourceHash`.
  ///
  /// Returns `.unknown` if not in the directory.
  /// Python: `Directory.trust_level(source_hash)`.
  public func trustLevel(_ sourceHash: Data) -> DirectoryEntry.TrustLevel {
    directoryEntries[sourceHash]?.trustLevel ?? .unknown
  }

  /// Display name for `sourceHash`, or `nil` if not known.
  ///
  /// Python: `Directory.display_name(source_hash)`.
  public func displayName(_ sourceHash: Data) -> String? {
    directoryEntries[sourceHash]?.displayName
  }

  /// Preferred delivery for `sourceHash`.
  ///
  /// Returns `.direct` if not in directory.
  /// Python: `Directory.preferred_delivery(source_hash)`.
  public func preferredDelivery(_ sourceHash: Data) -> DirectoryEntry.Delivery {
    directoryEntries[sourceHash]?.preferredDelivery ?? .direct
  }

  // MARK:–Known nodes (Python: Directory.known_nodes / number_of_known_nodes)

  /// All entries that host a NomadNet node, sorted by trust level (desc) then name.
  ///
  /// Python: `Directory.known_nodes()`.
  public func knownNodes() -> [DirectoryEntry] {
    directoryEntries.values
      .filter { $0.hostsNode }
      .sorted { lhs, rhs in
        // Python's key is (sort_rank or 2^32, TRUSTED - trust, name or "_"). In Python 2^32 is
        // XOR, 34, so an unranked node sorts after rank 33; kept for parity.
        let lr = lhs.sortRank ?? (2 ^ 32)
        let rr = rhs.sortRank ?? (2 ^ 32)
        if lr != rr { return lr < rr }
        if lhs.trustLevel != rhs.trustLevel { return lhs.trustLevel > rhs.trustLevel }
        return (lhs.displayName ?? "_") < (rhs.displayName ?? "_")
      }
  }

  /// Number of entries that host a NomadNet node.
  public func numberOfKnownNodes() -> Int {
    directoryEntries.values.filter { $0.hostsNode }.count
  }

  // MARK:–Announce stream updates (Python: node_announce_received / lxmf_announce_received)

  /// Record a NomadNet node announce.
  ///
  /// Python: `Directory.node_announce_received(…)`.
  /// An announce without app data is ignored. Python's auto-remember of a trusted peer's node
  /// is commented out, so the node is not remembered.
  public func nodeAnnounceReceived(sourceHash: Data, appData: Data?, associatedPeer: Data?) {
    guard appData != nil else { return }
    let record = AnnounceRecord(
      timestamp: Date(),
      sourceHash: sourceHash,
      appData: appData,
      kind: "node"
    )
    nodeAnnounces.insert(record, at: 0)
    while nodeAnnounces.count > Self.announceStreamMaxLength {
      nodeAnnounces.removeLast()
    }
  }

  /// Record an LXMF peer announce.
  ///
  /// Python: `Directory.lxmf_announce_received(…)`. An announce without app data is ignored.
  public func peerAnnounceReceived(sourceHash: Data, appData: Data?) {
    guard appData != nil else { return }
    let record = AnnounceRecord(
      timestamp: Date(),
      sourceHash: sourceHash,
      appData: appData,
      kind: "peer"
    )
    peerAnnounces.insert(record, at: 0)
    while peerAnnounces.count > Self.announceStreamMaxLength {
      peerAnnounces.removeLast()
    }
  }

  /// Record a propagation-node announce.
  ///
  /// Python: `Directory.pn_announce_received(…)`.
  public func pnAnnounceReceived(
    sourceHash: Data, appData: Data?,
    associatedPeer: Data?, associatedNode: Data?
  ) {
    let record = AnnounceRecord(
      timestamp: Date(),
      sourceHash: sourceHash,
      appData: appData,
      kind: "pn"
    )
    pnAnnounces.insert(record, at: 0)
    while pnAnnounces.count > Self.announceStreamMaxLength {
      pnAnnounces.removeLast()
    }
  }

  // MARK:–Disk persistence (Python: save_to_disk / load_from_disk via msgpack)
  //
  // The Python implementation uses msgpack. This port uses a simple msgpack-compatible
  // encoding via the NomadNet/ReticulumSwift MsgPack helpers. Each entry is
  // packed as an array: [sourceHash, displayName, trustLevel, hostsNode,
  //                      preferredDelivery, identify, sortRank, notes]

  /// Persist the directory entries to `url` in msgpack format.
  ///
  /// Python: `Directory.save_to_disk()`.
  public func save(to url: URL) throws {
    var entryList: [MsgPack.Value] = []
    for (_, e) in directoryEntries {
      let sortRankVal: MsgPack.Value
      if let rank = e.sortRank {
        sortRankVal = .int(Int64(rank))
      } else {
        sortRankVal = .nil
      }
      let nameVal: MsgPack.Value = e.displayName.map { .string($0) } ?? .nil
      let entry = MsgPack.Value.array([
        .bytes(e.sourceHash),
        nameVal,
        .uint(UInt64(e.trustLevel.rawValue)),
        .bool(e.hostsNode),
        .uint(UInt64(e.preferredDelivery.rawValue)),
        .bool(e.identify),
        sortRankVal,
        .string(e.notes),
      ])
      entryList.append(entry)
    }
    // Python packs each announce as the tuple (timestamp, source_hash, app_data, kind).
    let stream: [MsgPack.Value] = announceStream.map {
      .array([
        .double($0.timestamp.timeIntervalSince1970), .bytes($0.sourceHash),
        $0.appData.map { .bytes($0) } ?? .nil, .string($0.kind),
      ])
    }
    let root = MsgPack.Value.map([
      (.string("entry_list"), .array(entryList)), (.string("announce_stream"), .array(stream)),
    ])
    let data = MsgPack.encode(root)
    try data.write(to: url)
  }

  /// Load directory entries from `url`.
  ///
  /// If the file does not exist, does nothing.
  /// Python: `Directory.load_from_disk()`.
  public func load(from url: URL) throws {
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    let data = try Data(contentsOf: url)
    let value = try MsgPack.decode(data)
    guard case .map(let pairs) = value else { return }

    for (k, v) in pairs {
      guard case .string("announce_stream") = k, case .array(let stream) = v else { continue }
      let records: [AnnounceRecord] = stream.compactMap {
        guard case .array(let a) = $0, a.count >= 4, case .bytes(let hash) = a[1],
          case .string(let kind) = a[3]
        else { return nil }
        let ts: Double
        switch a[0] {
        case .double(let d): ts = d
        case .int(let i): ts = Double(i)
        case .uint(let u): ts = Double(u)
        default: return nil
        }
        let appData: Data? = {
          guard case .bytes(let d) = a[2] else { return nil }
          return d
        }()
        return AnnounceRecord(
          timestamp: Date(timeIntervalSince1970: ts), sourceHash: hash, appData: appData,
          kind: kind)
      }
      nodeAnnounces = records.filter { $0.kind == "node" }
      peerAnnounces = records.filter { $0.kind == "peer" }
      pnAnnounces = records.filter { $0.kind == "pn" }
    }

    // Find "entry_list" key
    for (k, v) in pairs {
      guard case .string(let key) = k, key == "entry_list",
        case .array(let list) = v
      else { continue }

      var entries: [Data: DirectoryEntry] = [:]
      for item in list {
        guard case .array(let arr) = item, arr.count >= 3,
          case .bytes(let hash) = arr[0]
        else { continue }

        let displayName: String = {
          if case .string(let s) = arr[1] { return s }
          return "Undefined"  // Python: if e[1] == None: e[1] = "Undefined"
        }()

        let trust: DirectoryEntry.TrustLevel = {
          // `UInt8(u)` traps if a persisted/corrupt value exceeds 255;
          // UInt8(exactly:) maps any out-of-range value to .unknown.
          if case .uint(let u) = arr[2], let raw = UInt8(exactly: u) {
            return DirectoryEntry.TrustLevel(rawValue: raw) ?? .unknown
          }
          return .unknown
        }()

        let hostsNode: Bool =
          arr.count > 3
          ? {
            if case .bool(let b) = arr[3] { return b }
            return false
          }() : false

        let delivery: DirectoryEntry.Delivery =
          arr.count > 4
          ? {
            // Guard the UInt8 narrowing (see `trust`): out-of-range → .direct.
            if case .uint(let u) = arr[4], let raw = UInt8(exactly: u) {
              return DirectoryEntry.Delivery(rawValue: raw) ?? .direct
            }
            return .direct
          }() : .direct

        let identify: Bool =
          arr.count > 5
          ? {
            if case .bool(let b) = arr[5] { return b }
            return false
          }() : false

        let sortRank: Int? =
          arr.count > 6
          ? {
            // msgpack writes a non-negative rank as an unsigned int.
            switch arr[6] {
            case .int(let i): return Int(exactly: i)
            case .uint(let u): return Int(exactly: u)
            default: return nil
            }
          }() : nil

        let notes: String =
          arr.count > 7
          ? {
            if case .string(let s) = arr[7] { return s }
            return ""
          }() : ""

        entries[hash] = DirectoryEntry(
          sourceHash: hash,
          displayName: displayName,
          trustLevel: trust,
          hostsNode: hostsNode,
          preferredDelivery: delivery,
          identify: identify,
          sortRank: sortRank,
          notes: notes
        )
      }
      directoryEntries = entries
    }
  }
}
