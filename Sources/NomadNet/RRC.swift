//===----------------------------------------------------------------------===//
// Copyright (c) 2026 NomadNetSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import Foundation
import CryptoKit
import ReticulumSwift

// MARK: - Utilities

extension Data {
    /// Lowercase hexadecimal representation (matches Python's `bytes.hex()`).
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}

extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock(); defer { unlock() }; return try body()
    }
}

// MARK: - RRCMessage

/// A received or sent RRC chat message.
///
/// Corresponds to Python `RRCMessage` in `nomadnet/RRC.py`.
public struct RRCMessage {
    /// Message kind, as recorded in the room history log.
    public var kind:    String
    /// Room the message belongs to, or `nil` for hub-level messages.
    public var room:    String?
    /// Destination hash of the sender, or `nil` when unknown.
    public var src:     Data?
    /// Sender nickname, when one was supplied.
    public var nick:    String?
    /// Message body text.
    public var text:    String
    /// Unix timestamp, in seconds, the message was stamped with.
    public var ts:      Int64
    /// Whether the message mentions the local peer.
    public var mention: Bool = false

    /// Creates a message from its decoded fields.
    public init(kind: String, room: String?, src: Data?, nick: String?,
                text: String, ts: Int64) {
        self.kind = kind; self.room = room; self.src = src
        self.nick = nick; self.text = text; self.ts  = ts
    }
}

// MARK: - RRC constants

/// Wire constants and envelope coding for the RRC protocol.
public enum RRC {
    /// Protocol version carried in every envelope.
    public static let version: Int = 1

    // The members below are the reference's own map-key names.
    // swift-format-ignore: AllPublicDeclarationsHaveDocumentation
    /// Integer CBOR map keys—K_V, K_T, K_ID, K_TS, K_SRC, K_ROOM, K_BODY, K_NICK.
    public enum Key {
        public static let version: Int = 0
        public static let type:    Int = 1
        public static let id:      Int = 2
        public static let ts:      Int = 3
        public static let src:     Int = 4
        public static let room:    Int = 5
        public static let body:    Int = 6
        public static let nick:    Int = 7
    }

    // The members below are the reference's own field names.
    // swift-format-ignore: AllPublicDeclarationsHaveDocumentation
    /// HELLO body indices—B_HELLO_NAME, B_HELLO_VER, B_HELLO_CAPS.
    public enum HelloField {
        public static let name: Int = 0
        public static let ver:  Int = 1
        public static let caps: Int = 2
    }

    // The members below are the reference's own field names.
    // swift-format-ignore: AllPublicDeclarationsHaveDocumentation
    /// WELCOME body indices—B_WELCOME_HUB, B_WELCOME_VER, B_WELCOME_CAPS, B_WELCOME_LIMITS.
    public enum WelcomeField {
        public static let hub:    Int = 0
        public static let ver:    Int = 1
        public static let caps:   Int = 2
        public static let limits: Int = 3
    }

    // The members below are the reference's own field names.
    // swift-format-ignore: AllPublicDeclarationsHaveDocumentation
    /// Capability flag indices—CAP_RESOURCE_ENVELOPE, CAP_ACTION.
    public enum Cap {
        public static let resourceEnvelope: Int = 0
        public static let action:           Int = 1
    }

    // The members below are the reference's own field names.
    // swift-format-ignore: AllPublicDeclarationsHaveDocumentation
    /// Indices into the WELCOME limits dict—L_MAX_NICK_BYTES, …, L_RATE_LIMIT_MSGS_PER_MINUTE.
    public enum LimitField {
        public static let maxNickBytes:            Int = 0
        public static let maxRoomNameBytes:        Int = 1
        public static let maxMsgBodyBytes:         Int = 2
        public static let maxRoomsPerSession:      Int = 3
        public static let rateLimitMsgsPerMinute:  Int = 4
    }

    // The members below are the reference's own field names.
    // swift-format-ignore: AllPublicDeclarationsHaveDocumentation
    /// Indices into T_RESOURCE_ENVELOPE body—B_RES_ID, …, B_RES_ENCODING.
    public enum ResField {
        public static let id:       Int = 0
        public static let kind:     Int = 1
        public static let size:     Int = 2
        public static let sha256:   Int = 3
        public static let encoding: Int = 4
    }

    // The members below are the reference's own field names.
    // swift-format-ignore: AllPublicDeclarationsHaveDocumentation
    /// Resource kind strings—RES_KIND_NOTICE, RES_KIND_MOTD, RES_KIND_BLOB.
    public enum ResKind {
        public static let notice: String = "notice"
        public static let motd:   String = "motd"
        public static let blob:   String = "blob"
    }

    // The members below are the reference's own field names.
    // swift-format-ignore: AllPublicDeclarationsHaveDocumentation
    /// CBOR text keys used in per-room history log entries.
    public enum HistKey {
        public static let kind:    String = "k"
        public static let src:     String = "s"
        public static let nick:    String = "n"
        public static let text:    String = "t"
        public static let ts:      String = "ts"
        public static let mention: String = "m"
    }

    /// Default maximum nickname length in bytes.
    public static let defaultMaxNickBytes:  Int = 32
    /// Default maximum room-name length in bytes.
    public static let defaultMaxRoomBytes:  Int = 64
    /// Default maximum message body length in bytes.
    public static let defaultMaxMsgBytes:   Int = 350
    /// Default maximum rooms one session may join.
    public static let defaultMaxRooms:      Int = 32
    /// Default message rate limit per minute.
    public static let defaultRatePerMinute: Int = 240

    // The members below are the reference's own message-type names.
    // swift-format-ignore: AllPublicDeclarationsHaveDocumentation
    /// Integer message-type codes carried under `Key.type`.
    public enum MessageType {
        public static let hello:            Int = 1
        public static let welcome:          Int = 2
        public static let join:             Int = 10
        public static let joined:           Int = 11
        public static let part:             Int = 12
        public static let parted:           Int = 13
        public static let msg:              Int = 20
        public static let notice:           Int = 21
        public static let action:           Int = 22
        public static let ping:             Int = 30
        public static let pong:             Int = 31
        public static let error:            Int = 40
        public static let resourceEnvelope: Int = 50
    }

    /// Default destination name a hub is reached at.
    public static let defaultDestName: String = "rrc.hub"

    // MARK: - Envelope

    /// Decoded RRC envelope.
    public struct Envelope {
        /// Protocol version the envelope was encoded with.
        public let version: Int
        /// Message-type code, one of `MessageType`.
        public let type:    Int
        /// Message identifier.
        public let id:      Data
        /// Unix timestamp, in seconds, the envelope was stamped with.
        public let ts:      Int64
        /// Destination hash of the sender.
        public let src:     Data
        /// Room the message belongs to, or `nil` for hub-level messages.
        public var room:    String?
        /// Message body, when the type carries one.
        public var body:    String?
        /// Sender nickname, when one was supplied.
        public var nick:    String?
    }

    /// Builds an envelope, supplying a random identifier and the current time when they are omitted.
    public static func makeEnvelope(type: Int, src: Data, mid: Data? = nil, ts: Int64? = nil,
                                     room: String? = nil, body: String? = nil,
                                     nick: String? = nil) -> Envelope {
        Envelope(version: version, type: type,
                 id:   mid ?? Data((0..<8).map { _ in UInt8.random(in: 0...255) }),
                 ts:   ts  ?? Int64(Date().timeIntervalSince1970 * 1000),
                 src:  src, room: room, body: body, nick: nick)
    }

    /// Encodes `env` to its CBOR wire representation.
    public static func encode(_ env: Envelope) throws -> Data {
        var pairs: [(CBOR.Value, CBOR.Value)] = [
            (.uint(UInt64(Key.version)), .uint(UInt64(env.version))),
            (.uint(UInt64(Key.type)),    .uint(UInt64(env.type))),
            (.uint(UInt64(Key.id)),      .bytes(env.id)),
            (.uint(UInt64(Key.ts)),      .uint(UInt64(bitPattern: env.ts))),
            (.uint(UInt64(Key.src)),     .bytes(env.src)),
        ]
        if let r = env.room { pairs.append((.uint(UInt64(Key.room)), .text(r))) }
        if let b = env.body { pairs.append((.uint(UInt64(Key.body)), .text(b))) }
        if let n = env.nick, !n.isEmpty { pairs.append((.uint(UInt64(Key.nick)), .text(n))) }
        return CBOR.encode(.map(pairs))
    }

    /// Decodes an envelope from its CBOR wire representation.
    public static func decode(_ data: Data) throws -> Envelope {
        let value = try CBOR.decode(data)
        guard case .map(let pairs) = value else { throw DecodeError.unexpectedType("Expected CBOR map") }
        var kv: [Int: CBOR.Value] = [:]
        for (k, v) in pairs { if case .uint(let u) = k { kv[Int(u)] = v } }
        guard let vVersion = kv[Key.version], case .uint(let ver) = vVersion
        else { throw DecodeError.missingField("version") }
        guard let vType = kv[Key.type], case .uint(let rawType) = vType
        else { throw DecodeError.missingField("type") }
        guard let vID = kv[Key.id], case .bytes(let id) = vID
        else { throw DecodeError.missingField("id") }
        guard let vTS = kv[Key.ts], case .uint(let tsRaw) = vTS
        else { throw DecodeError.missingField("ts") }
        guard let vSrc = kv[Key.src], case .bytes(let src) = vSrc
        else { throw DecodeError.missingField("src") }
        var room: String? = nil
        if let vRoom = kv[Key.room], case .text(let r) = vRoom { room = r }
        var body: String? = nil
        if let vBody = kv[Key.body], case .text(let b) = vBody { body = b }
        var nick: String? = nil
        if let vNick = kv[Key.nick], case .text(let n) = vNick { nick = n }
        return Envelope(version: Int(ver), type: Int(rawType), id: id,
                        ts: Int64(bitPattern: tsRaw), src: src, room: room, body: body, nick: nick)
    }

    /// Failures raised while decoding an envelope.
    public enum DecodeError: Error {
        case missingField(String)
        case unexpectedType(String)
    }
}

// MARK: - RRCHubError

/// Failures raised by hub operations.
public enum RRCHubError: Error {
    case notConnected
    case emptyRoom
    case messageTooLong
    case commandMustStartWithSlash
    case identityUnavailable
}

// MARK: - RRCHub

/// A connection to a single RRC hub.
///
/// Corresponds to Python `RRCHub` in `nomadnet/RRC.py`.
public final class RRCHub {

    // MARK: Status

    /// Connection state of a hub.
    public enum Status: Int {
        case disconnected = 0, connecting = 1, connected = 2, failed = 3
    }

    // MARK: Public read-only state

    /// Destination hash of the hub.
    public let hubHash: Data
    /// Destination name the hub is reached at.
    public let destName: String
    /// Local display name for the hub.
    public var name: String

    /// Current connection state.
    public private(set) var status:      Status = .disconnected
    /// Human-readable form of `status`.
    public private(set) var statusText:  String = "Disconnected"
    /// Whether the hub has answered HELLO with WELCOME.
    public private(set) var welcomed:    Bool   = false
    /// Name the hub reported in WELCOME.
    public private(set) var hubName:     String? = nil
    /// Version the hub reported in WELCOME.
    public private(set) var hubVersion:  String? = nil
    /// Capability flags the hub reported in WELCOME.
    public private(set) var hubCaps:     [Int: Bool] = [:]
    /// Message of the day the hub last published.
    public              var motd:        String? = nil

    // Hub-advertised limits (updated on T_WELCOME)
    /// Maximum nickname length the hub accepts, in bytes.
    public private(set) var maxNickBytes:          Int = RRC.defaultMaxNickBytes
    /// Maximum room-name length the hub accepts, in bytes.
    public private(set) var maxRoomNameBytes:      Int = RRC.defaultMaxRoomBytes
    /// Maximum message body length the hub accepts, in bytes.
    public private(set) var maxMsgBodyBytes:       Int = RRC.defaultMaxMsgBytes
    /// Maximum rooms one session may join.
    public private(set) var maxRoomsPerSession:    Int = RRC.defaultMaxRooms
    /// Messages per minute the hub accepts from one session.
    public private(set) var rateLimitMsgsPerMinute:Int = RRC.defaultRatePerMinute

    // Room / message / member state (lock-protected)
    /// Rooms this session has joined.
    public private(set) var rooms:       Set<String> = []
    /// Rooms holding messages the user has not read.
    public private(set) var unreadRooms: Set<String> = []
    /// Rooms holding an unread message that mentions the user.
    public private(set) var mentionRooms:Set<String> = []
    /// Hub-level notices received outside any room.
    public private(set) var notices:     [RRCMessage] = []
    /// Rooms the hub advertised, mapped to their topics.
    public private(set) var availableRooms: [String: String?] = [:]

    // Settings
    /// Whether the hub is redialled after an unexpected disconnect.
    public var autoReconnect: Bool = false
    /// Whether the room list is requested on connect.
    public var autoList:      Bool = false
    /// Whether the member list is requested on join.
    public var autoWho:       Bool = false
    /// Nickname used instead of the app-wide one, when set.
    public var nickOverride:  String? = nil

    // MARK: Internal state (accessible from tests via @testable import)

    internal var messages:  [String: [RRCMessage]] = [:]
    internal var members:   [String: Set<Data>] = [:]
    internal var nicks:     [Data: String] = [:]
    internal var reconnectAttempts: Int = 0
    internal var sentIDs:           [Data] = []    // ring buffer, maxlen = 256
    internal var pendingPings:      [Data: (Int64, String?)] = [:]
    internal var pendingJoins:      Set<String> = []
    internal var pendingParts:      Set<String> = []
    internal var silentJoins:       Set<String> = []
    internal var silentWhoRooms:    Set<String> = []
    internal var silentListPending: Int = 0
    internal var sendHook:          ((Data) -> Void)? = nil

    // MARK: Class-level constants

    /// Minimum elapsed time (seconds) between consecutive `cleanHistory` sweeps.
    ///
    /// Matches Python `RRCHub.CLEAN_HISTORY_INTERVAL = 5`.
    internal static let cleanHistoryInterval: TimeInterval = 5.0

    /// Default lifetime (seconds) for ephemeral messages when no app override is set.
    ///
    /// Matches Python `RRCHub.SYS_NOTICE_TIMEOUT = 600`.
    internal static let sysNoticeTimeout: TimeInterval = 600.0

    // MARK: Private

    private let lock = NSLock()
    /// Serializes history-file writes.
    ///
    /// On non-POSIX platforms O_APPEND writes
    /// are not guaranteed to be atomic; this lock prevents interleaved writes.
    /// Mirrors Python `RRCHub._history_io_lock` added for cross-platform safety.
    private let historyIOLock = NSLock()
    private var unsafeLink: Link? = nil
    private var manualDisconnect: Bool = false
    private var reconnectTask:    Task<Void, Never>? = nil
    private var helloTask:        Task<Void, Never>? = nil
    private var historyWriteFailed: Bool = false
    private var lastHistoryClean: Date = .distantPast
    /// Time `cleanHistory` last removed an entry.
    public  var cleanLastRemoved:  Date = .distantPast
    private var resourceExpectations: [Data: ResourceExpectation] = [:]

    /// Strong reference to the owning manager.
    ///
    /// The retain cycle (manager→hub→manager) is broken by `RRCManager.removeHub`
    /// which sets `hub.manager = nil` before releasing the hub.
    internal var manager: RRCManager?

    /// Default cap on an accepted hub→client resource transfer (256 KiB).
    ///
    /// Mirrors Python's `rrc_max_accepted_resource_size` default (commit 510d476).
    public static let defaultMaxAcceptedResourceSize: Int = 262144

    private struct ResourceExpectation {
        var kind: String
        var size: Int
        var sha256: Data?
        var encoding: String
        var room: String?
        var expires: Date
    }

    // MARK: Init

    /// Creates a hub connection owned by `manager`.
    public init(manager: RRCManager, hubHash: Data, destName: String? = nil, name: String? = nil) {
        self.manager  = manager
        self.hubHash  = hubHash
        self.destName = destName ?? RRC.defaultDestName
        self.name     = name ?? hubHash.hex.prefix(8).description
    }

    // MARK: - Room management

    /// Adds `room` to the local room set and returns its normalized name.
    @discardableResult
    public func addRoom(_ room: String) -> String {
        let r = (try? normalizeRoom(room)) ?? room.lowercased().trimmingCharacters(in: .whitespaces)
        lock.withLock {
            rooms.insert(r)
            if messages[r] == nil { messages[r] = [] }
        }
        manager?.save()
        manager?.notifyChange(self)
        return r
    }

    /// Drops `room` from the local room set along with its buffered messages.
    public func removeRoom(_ room: String) {
        guard let r = try? normalizeRoom(room) else { return }
        lock.withLock {
            rooms.remove(r)
            messages.removeValue(forKey: r)
            unreadRooms.remove(r)
            mentionRooms.remove(r)
            members.removeValue(forKey: r)
        }
        deleteHistory(room: r)
        manager?.save()
        manager?.notifyChange(self)
    }

    /// Clears the buffered messages for `room`.
    public func clearMessages(_ room: String) {
        guard let r = try? normalizeRoom(room) else { return }
        lock.withLock {
            messages[r] = []
            unreadRooms.remove(r)
            mentionRooms.remove(r)
        }
        deleteHistory(room: r)
        manager?.notifyChange(self)
    }

    /// Returns the member destination hashes last reported for `room`.
    public func getMembers(room: String) -> [Data] {
        guard let r = try? normalizeRoom(room) else { return [] }
        return lock.withLock { Array(members[r] ?? []) }
    }

    /// Marks `room` read, clearing its unread and mention flags.
    public func markRead(_ room: String) {
        guard let r = try? normalizeRoom(room) else { return }
        lock.withLock {
            unreadRooms.remove(r)
            mentionRooms.remove(r)
        }
        manager?.notifyChange(self)
    }

    /// Returns the buffered messages for `room`, oldest first.
    public func getMessages(room: String) -> [RRCMessage] {
        guard let r = try? normalizeRoom(room) else { return [] }
        return lock.withLock { Array(messages[r] ?? []) }
    }

    /// Snapshot the joined-rooms set under the hub lock (callers on other threads
    /// must not iterate `rooms` directly—packet handlers mutate it).
    internal func snapshotRooms() -> [String] {
        lock.withLock { Array(rooms) }
    }

    /// Snapshot the joined rooms and the parted-room message keys atomically
    /// under the hub lock, for a consistent view during save().
    internal func snapshotRoomsForSave() -> (joined: [String], parted: [String]) {
        lock.withLock {
            let joined = Array(rooms)
            let parted = messages.keys.filter { !rooms.contains($0) }
            return (joined, parted)
        }
    }

    /// Returns `room` lowercased and trimmed, rejecting empty or oversized names.
    public func normalizeRoom(_ room: String) throws -> String {
        let r = room.trimmingCharacters(in: .whitespaces).lowercased()
        guard !r.isEmpty else { throw RRCHubError.emptyRoom }
        return r
    }

    // MARK: - Nick / display name

    /// Returns the nickname last seen for `peer`, or its short hash.
    public func displayNameFor(_ peer: Data) -> String {
        let nick = lock.withLock { nicks[peer] }
        if let n = nick, !n.isEmpty { return n }
        return peer.hex.prefix(12).description
    }

    /// Returns the nickname this session sends, preferring the override.
    public func getEffectiveNick() -> String? {
        if let n = nickOverride, !n.isEmpty { return n }
        return manager?.getNickname()
    }

    /// Sets the nickname used instead of the app-wide one.
    public func setNickOverride(_ nick: String?) {
        lock.withLock {
            nickOverride = (nick?.isEmpty ?? true) ? nil : nick
        }
        manager?.save()
        manager?.notifyChange(self)
    }

    // MARK: - Settings

    /// Enables or disables redialling after an unexpected disconnect.
    public func setAutoReconnect(_ enabled: Bool, save: Bool = true) {
        lock.withLock { autoReconnect = enabled }
        if save { manager?.save() }
        manager?.notifyChange(self)
    }

    /// Enables or disables requesting the room list on connect.
    public func setAutoList(_ enabled: Bool, save: Bool = true) {
        lock.withLock { autoList = enabled }
        if save { manager?.save() }
        manager?.notifyChange(self)
    }

    /// Enables or disables requesting the member list on join.
    public func setAutoWho(_ enabled: Bool, save: Bool = true) {
        lock.withLock { autoWho = enabled }
        if save { manager?.save() }
        manager?.notifyChange(self)
    }

    // MARK: - Connection state machine

    /// Opens a link to the hub and sends HELLO.
    public func connect() {
        let shouldSkip = lock.withLock { () -> Bool in
            guard status != .connecting && status != .connected else { return true }
            manualDisconnect = false
            reconnectTask?.cancel(); reconnectTask = nil
            let text = reconnectAttempts > 0 ? "Reconnecting (attempt \(reconnectAttempts))" : "Connecting"
            // Set state directly: `lock` is already held, and `setStatus` would
            // re-acquire the same non-recursive NSLock → deadlock. Notify AFTER the
            // lock is released (below), mirroring `setStatus`'s own ordering.
            self.status = .connecting
            self.statusText = text
            return false
        }
        guard !shouldSkip else { return }
        manager?.notifyChange(self)   // outside the lock (may re-enter the hub)
        Task { await connectWorker() }
    }

    private func connectWorker() async {
        guard let mgr = manager, let identity = mgr.identity else {
            setStatus(.failed, text: "No identity"); return
        }
        guard let transport = mgr.app?.reticulum.transport else {
            setStatus(.failed, text: "No transport"); return
        }

        // Request path if unknown. Wait up to 20 seconds—path resolution over a real
        // multi-hop mesh (public transport backbone) can take well over the old 5 seconds,
        // and it must not be shorter than the identity-recall wait just below it, or
        // a slow-mesh connect fails with a misleading "Hub identity unknown".
        if !transport.hasPath(to: hubHash) {
            try? transport.requestPath(for: hubHash)
            for _ in 0..<200 {
                if transport.hasPath(to: hubHash) { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        // Wait for identity recall
        var hubIdentity: Identity? = nil
        for _ in 0..<100 {
            hubIdentity = Identity.recall(destinationHash: hubHash)
            if hubIdentity != nil { break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        guard let hubIdent = hubIdentity else {
            setStatus(.failed, text: "Hub identity unknown"); return
        }

        do {
            let dest = try Destination(identity: hubIdent, direction: .out, kind: .single,
                                       appName: "rrc", aspects: ["hub"])
            guard dest.hash == hubHash else {
                setStatus(.failed, text: "Hash/destination name mismatch"); return
            }
            let link = try Link.initiate(destination: dest, transport: transport)
            link.onDataReceived = { [weak self] data, _ in self?.onPacket(data) }
            link.onEstablished  = { [weak self] _ in self?.onEstablished()      }
            link.onClosed       = { [weak self] _ in self?.onClosed()           }
            lock.withLock { unsafeLink = link }
        } catch {
            setStatus(.failed, text: "Connect error: \(error)")
        }
        _ = identity  // suppress unused warning
    }

    private func onEstablished() {
        guard let mgr = manager, let identity = mgr.identity else { return }
        setStatus(.connecting, text: "Identified, sending HELLO")
        try? unsafeLink?.identify(as: identity)
        unsafeLink?.resourceStrategy = .acceptApp
        // Accept and consume hub→client resource transfers (MOTD, long notices, and
        // large /who or /list replies the hub sends as a resource when they exceed the
        // link packet MDU). Without these callbacks the Link rejects every hub resource.
        unsafeLink?.onResourceAdvertised = { [weak self] adv, _ in self?.resourceAdvertised(size: Int(adv.dataSize)) ?? false }
        unsafeLink?.onResourceConcluded  = { [weak self] payload, _, _ in self?.resourceConcluded(payload: payload) }

        helloTask?.cancel()
        helloTask = Task { [weak self] in
            guard let self = self else { return }
            var attempts = 0
            while !Task.isCancelled && !self.welcomed && attempts < 5 {
                self.sendHello()
                attempts += 1
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
            if !self.welcomed && !Task.isCancelled {
                self.setStatus(.failed, text: "WELCOME timeout")
                self.lock.withLock {
                    try? self.unsafeLink?.teardown()
                }
            }
        }
    }

    private func onClosed() {
        helloTask?.cancel(); helloTask = nil
        let shouldReconnect = lock.withLock { () -> Bool in
            unsafeLink = nil
            welcomed = false
            motd = nil
            members.removeAll()
            resourceExpectations.removeAll()
            pendingJoins.removeAll()
            pendingParts.removeAll()
            silentJoins.removeAll()
            silentWhoRooms.removeAll()
            return autoReconnect && !manualDisconnect
        }
        setStatus(.disconnected, text: "Disconnected")
        if shouldReconnect { scheduleReconnect() }
    }

    internal func scheduleReconnect() {
        lock.withLock { reconnectAttempts += 1 }
        let attempts = lock.withLock { reconnectAttempts }
        let backoff = min(60.0, max(1.0, pow(2.0, Double(min(attempts, 6)))))
        setStatus(.disconnected, text: "Reconnect in \(Int(backoff))s")
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
            guard !Task.isCancelled else { return }
            let go = self?.lock.withLock { () -> Bool in
                guard let s = self else { return false }
                return !s.manualDisconnect && s.autoReconnect
            } ?? false
            if go { self?.connect() }
        }
    }

    /// Tears down the link and stops reconnecting.
    public func disconnect() {
        helloTask?.cancel(); helloTask = nil
        let link = lock.withLock { () -> Link? in
            manualDisconnect = true
            reconnectAttempts = 0
            reconnectTask?.cancel(); reconnectTask = nil
            let l = unsafeLink; unsafeLink = nil; return l
        }
        try? link?.teardown()
        setStatus(.disconnected, text: "Disconnected")
    }

    // MARK: - Outbound send

    /// Build and "send" a CBOR envelope.
    ///
    /// In tests, intercepted by `sendHook`.
    internal func sendEnv(_ pairs: [(CBOR.Value, CBOR.Value)]) throws {
        let payload = CBOR.encode(.map(pairs))
        if let hook = sendHook { hook(payload); return }
        guard let link = unsafeLink else { throw RRCHubError.notConnected }
        try link.send(payload)
    }

    /// Sends the RRC HELLO handshake packet.
    internal func sendHello() {
        guard let src = manager?.identity?.hash else { return }
        let caps: CBOR.Value = .map([
            (.uint(UInt64(RRC.Cap.resourceEnvelope)), .bool(true)),
            (.uint(UInt64(RRC.Cap.action)),           .bool(true)),
        ])
        let body: CBOR.Value = .map([
            (.uint(UInt64(RRC.HelloField.name)), .text("nomadnet")),
            (.uint(UInt64(RRC.HelloField.ver)),  .text("0.1")),
            (.uint(UInt64(RRC.HelloField.caps)), caps),
        ])
        var pairs: [(CBOR.Value, CBOR.Value)] = [
            (.uint(UInt64(RRC.Key.version)), .uint(UInt64(RRC.version))),
            (.uint(UInt64(RRC.Key.type)),    .uint(UInt64(RRC.MessageType.hello))),
            (.uint(UInt64(RRC.Key.id)),      .bytes(Data((0..<8).map { _ in UInt8.random(in: 0...255) }))),
            (.uint(UInt64(RRC.Key.ts)),      .uint(UInt64(bitPattern: Int64(Date().timeIntervalSince1970 * 1000)))),
            (.uint(UInt64(RRC.Key.src)),     .bytes(src)),
            (.uint(UInt64(RRC.Key.body)),    body),
        ]
        if let nick = getEffectiveNick() {
            pairs.append((.uint(UInt64(RRC.Key.nick)), .text(nick)))
        }
        try? sendEnv(pairs)
    }

    // MARK: - Room messaging

    /// Sends JOIN for `room`.
    public func joinRoom(_ room: String, key: String? = nil, silent: Bool = false) throws {
        let r = try normalizeRoom(room)
        let ownSrc = manager?.identity?.hash ?? Data()
        var pairs: [(CBOR.Value, CBOR.Value)] = makeBasePairs(type: RRC.MessageType.join, src: ownSrc, room: r)
        if let k = key, !k.isEmpty {
            pairs.append((.uint(UInt64(RRC.Key.body)), .text(k)))
        }
        if let nick = getEffectiveNick() {
            pairs.append((.uint(UInt64(RRC.Key.nick)), .text(nick)))
        }
        lock.withLock {
            pendingJoins.insert(r)
            if silent { silentJoins.insert(r) }
        }
        try sendEnv(pairs)
        lock.withLock { if messages[r] == nil { messages[r] = [] } }
        manager?.notifyChange(self)
    }

    /// Sends PART for `room`.
    public func partRoom(_ room: String) {
        guard let r = try? normalizeRoom(room) else { return }
        let ownSrc = manager?.identity?.hash ?? Data()
        let pairs = makeBasePairs(type: RRC.MessageType.part, src: ownSrc, room: r)
        lock.withLock { pendingParts.insert(r) }
        try? sendEnv(pairs)
        lock.withLock { rooms.remove(r) }
        manager?.save()
        manager?.notifyChange(self)
    }

    /// Sends `text` to `room` and returns the message identifier.
    @discardableResult
    public func sendMessage(room: String, text: String) throws -> Data {
        let r = try normalizeRoom(room)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RRCHubError.messageTooLong }
        guard text.utf8.count <= maxMsgBodyBytes else { throw RRCHubError.messageTooLong }
        let ownSrc = manager?.identity?.hash ?? Data()
        let mid = Data((0..<8).map { _ in UInt8.random(in: 0...255) })
        var pairs = makeBasePairs(type: RRC.MessageType.msg, src: ownSrc, room: r, mid: mid)
        pairs.append((.uint(UInt64(RRC.Key.body)), .text(text)))
        if let nick = getEffectiveNick() {
            pairs.append((.uint(UInt64(RRC.Key.nick)), .text(nick)))
        }
        lock.withLock {
            sentIDs.append(mid)
            if sentIDs.count > 256 { sentIDs.removeFirst(sentIDs.count - 256) }
        }
        try sendEnv(pairs)
        let msg = RRCMessage(kind: "msg", room: r, src: ownSrc,
                             nick: getEffectiveNick(), text: text,
                             ts: Int64(Date().timeIntervalSince1970 * 1000))
        recordMessage(msg, local: true)
        return mid
    }

    /// Sends `text` to `room` as an action and returns the message identifier.
    @discardableResult
    public func sendAction(room: String, text: String) throws -> Data {
        let r = try normalizeRoom(room)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RRCHubError.messageTooLong }
        guard text.utf8.count <= maxMsgBodyBytes else { throw RRCHubError.messageTooLong }
        let ownSrc = manager?.identity?.hash ?? Data()
        let mid = Data((0..<8).map { _ in UInt8.random(in: 0...255) })
        var pairs = makeBasePairs(type: RRC.MessageType.action, src: ownSrc, room: r, mid: mid)
        pairs.append((.uint(UInt64(RRC.Key.body)), .text(text)))
        if let nick = getEffectiveNick() {
            pairs.append((.uint(UInt64(RRC.Key.nick)), .text(nick)))
        }
        lock.withLock {
            sentIDs.append(mid)
            if sentIDs.count > 256 { sentIDs.removeFirst(sentIDs.count - 256) }
        }
        try sendEnv(pairs)
        let msg = RRCMessage(kind: "action", room: r, src: ownSrc,
                             nick: getEffectiveNick(), text: text,
                             ts: Int64(Date().timeIntervalSince1970 * 1000))
        recordMessage(msg, local: true)
        return mid
    }

    /// Sends a ping and returns its message identifier.
    @discardableResult
    public func sendPing(room: String? = nil) throws -> Data {
        let body = Data((0..<8).map { _ in UInt8.random(in: 0...255) })
        let ownSrc = manager?.identity?.hash ?? Data()
        var pairs = makeBasePairs(type: RRC.MessageType.ping, src: ownSrc)
        pairs.append((.uint(UInt64(RRC.Key.body)), .bytes(body)))
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        lock.withLock {
            pendingPings[body] = (now, room)
            let cutoff = now - 15_000
            pendingPings = pendingPings.filter { $0.value.0 > cutoff }
        }
        try sendEnv(pairs)
        return body
    }

    /// Sends a slash command to the hub.
    public func sendCommand(text: String, room: String? = nil) throws {
        guard text.hasPrefix("/") else { throw RRCHubError.commandMustStartWithSlash }
        let ownSrc = manager?.identity?.hash ?? Data()
        var pairs = makeBasePairs(type: RRC.MessageType.msg, src: ownSrc, room: room)
        pairs.append((.uint(UInt64(RRC.Key.body)), .text(text)))
        if let nick = getEffectiveNick() {
            pairs.append((.uint(UInt64(RRC.Key.nick)), .text(nick)))
        }
        try sendEnv(pairs)
    }

    // MARK: - Packet handler

    /// Called when a packet arrives on the link (or directly from tests).
    public func onPacket(_ data: Data) {
        guard let value = try? CBOR.decode(data), case .map(let rawPairs) = value else { return }
        var env: [Int: CBOR.Value] = [:]
        for (k, v) in rawPairs { if case .uint(let u) = k { env[Int(u)] = v } }
        guard let typeVal = env[RRC.Key.type], case .uint(let tRaw) = typeVal else { return }
        let t = Int(tRaw)

        switch t {
        case RRC.MessageType.ping:   handlePing(env: env)
        case RRC.MessageType.pong:   handlePong(env: env)
        case RRC.MessageType.welcome: handleWelcome(env: env)
        case RRC.MessageType.joined: handleJoined(env: env)
        case RRC.MessageType.parted: handleParted(env: env)
        case RRC.MessageType.msg:    handleMsg(env: env, kind: "msg", msgType: t)
        case RRC.MessageType.action: handleMsg(env: env, kind: "action", msgType: t)
        case RRC.MessageType.notice: handleNotice(env: env)
        case RRC.MessageType.error:  handleError(env: env)
        case RRC.MessageType.resourceEnvelope: handleResourceEnvelope(env: env)
        default: break
        }
    }

    // MARK: - Private packet handlers

    private func handlePing(env: [Int: CBOR.Value]) {
        guard let mgr = manager, let src = mgr.identity?.hash else { return }
        var pongPairs = makeBasePairs(type: RRC.MessageType.pong, src: src)
        if let bodyVal = env[RRC.Key.body] {
            pongPairs.append((.uint(UInt64(RRC.Key.body)), bodyVal))
        }
        try? sendEnv(pongPairs)
    }

    private func handlePong(env: [Int: CBOR.Value]) {
        guard case .bytes(let body) = env[RRC.Key.body] else { return }
        let (sentMs, room) = lock.withLock { () -> (Int64?, String?) in
            let pending = pendingPings.removeValue(forKey: body)
            return (pending?.0, pending?.1)
        }
        guard let sent = sentMs else { return }
        let rtt = max(0, Int64(Date().timeIntervalSince1970 * 1000) - sent)
        if let r = room { recordSystem(room: r, text: "Pong from hub: \(rtt) ms") }
    }

    private func handleWelcome(env: [Int: CBOR.Value]) {
        lock.withLock { welcomed = true }
        if case .map(let bodyPairs) = env[RRC.Key.body] {
            var body: [Int: CBOR.Value] = [:]
            for (k, v) in bodyPairs { if case .uint(let u) = k { body[Int(u)] = v } }
            // Assign the hub metadata/limits under the lock—they are readable
            // from other threads (UI). Building the local caps/lims dicts inside
            // the lock is fine (no callouts).
            lock.withLock {
                if case .text(let n) = body[RRC.WelcomeField.hub]  { hubName    = n }
                if case .text(let v) = body[RRC.WelcomeField.ver]  { hubVersion = v }
                if case .map(let cp) = body[RRC.WelcomeField.caps] {
                    var caps: [Int: Bool] = [:]
                    for (k, v) in cp {
                        if case .uint(let u) = k, case .bool(let b) = v { caps[Int(u)] = b }
                    }
                    hubCaps = caps
                }
                if case .map(let lp) = body[RRC.WelcomeField.limits] {
                    var lims: [Int: Int] = [:]
                    for (k, v) in lp {
                        if case .uint(let u) = k {
                            if case .uint(let n) = v { lims[Int(u)] = Int(n) }
                        }
                    }
                    if let v = lims[RRC.LimitField.maxNickBytes]            { maxNickBytes = v }
                    if let v = lims[RRC.LimitField.maxRoomNameBytes]        { maxRoomNameBytes = v }
                    if let v = lims[RRC.LimitField.maxMsgBodyBytes]         { maxMsgBodyBytes = v }
                    if let v = lims[RRC.LimitField.maxRoomsPerSession]      { maxRoomsPerSession = v }
                    if let v = lims[RRC.LimitField.rateLimitMsgsPerMinute]  { rateLimitMsgsPerMinute = v }
                }
            }
        }
        lock.withLock { reconnectAttempts = 0 }
        setStatus(.connected, text: "Connected")
        manager?.onWelcome(hub: self)
        if autoList {
            lock.withLock { silentListPending += 1 }
            try? sendCommand(text: "/list")
        }
    }

    private func handleJoined(env: [Int: CBOR.Value]) {
        guard case .text(let rawRoom) = env[RRC.Key.room] else { return }
        let r = rawRoom.trimmingCharacters(in: .whitespaces).lowercased()
        guard !r.isEmpty else { return }

        var memberHashes: [Data] = []
        if case .array(let items) = env[RRC.Key.body] {
            memberHashes = items.compactMap { if case .bytes(let b) = $0 { return b } else { return nil } }
        }
        let joinerNick: String? = { if case .text(let n) = env[RRC.Key.nick] { return n } else { return nil } }()
        let ownHash = manager?.identity?.hash

        let (selfJoin, silent) = lock.withLock { () -> (Bool, Bool) in
            let sj = pendingJoins.contains(r)
            let sl = silentJoins.contains(r)
            if sj { pendingJoins.remove(r) }
            if sl { silentJoins.remove(r) }
            rooms.insert(r)
            if messages[r] == nil { messages[r] = [] }
            var mset = members[r] ?? []
            for h in memberHashes { mset.insert(h) }
            if let own = ownHash { mset.insert(own) }
            // Learn nick from single-joiner JOINED (rrcd 0.3.2+)
            if !sj, let nick = joinerNick, !nick.isEmpty, memberHashes.count == 1 {
                let jh = memberHashes[0]
                if ownHash == nil || jh != ownHash { nicks[jh] = nick }
            }
            members[r] = mset
            return (sj, sl)
        }

        if selfJoin {
            if !silent { recordSystem(room: r, text: "You joined #\(r)") }
            if autoWho {
                lock.withLock { silentWhoRooms.insert(r) }
                try? sendCommand(text: "/who \(r)", room: r)
            }
            manager?.save()
        } else {
            if let joiner = memberHashes.first, ownHash == nil || joiner != ownHash {
                recordSystem(room: r, text: "\(displayNameFor(joiner)) joined")
            }
        }
        manager?.notifyChange(self)
    }

    private func handleParted(env: [Int: CBOR.Value]) {
        guard case .text(let rawRoom) = env[RRC.Key.room] else { return }
        let r = rawRoom.trimmingCharacters(in: .whitespaces).lowercased()
        guard !r.isEmpty else { return }

        var memberHashes: [Data] = []
        if case .array(let items) = env[RRC.Key.body] {
            memberHashes = items.compactMap { if case .bytes(let b) = $0 { return b } else { return nil } }
        }
        let parterNick: String? = { if case .text(let n) = env[RRC.Key.nick] { return n } else { return nil } }()
        let ownHash = manager?.identity?.hash

        let selfPart = lock.withLock { () -> Bool in
            let sp = pendingParts.contains(r)
            if sp { pendingParts.remove(r) }
            // Learn nick before removing from member set
            if !sp, let nick = parterNick, !nick.isEmpty, memberHashes.count == 1 {
                let ph = memberHashes[0]
                if ownHash == nil || ph != ownHash { nicks[ph] = nick }
            }
            for h in memberHashes { members[r]?.remove(h) }
            if sp { rooms.remove(r); members.removeValue(forKey: r) }
            return sp
        }

        if selfPart {
            manager?.save()
        } else {
            if let parter = memberHashes.first, ownHash == nil || parter != ownHash {
                recordSystem(room: r, text: "\(displayNameFor(parter)) left")
            }
        }
        manager?.notifyChange(self)
    }

    private func handleMsg(env: [Int: CBOR.Value], kind: String, msgType: Int) {
        guard case .text(let body) = env[RRC.Key.body] else { return }
        let rawRoom: String? = { if case .text(let r) = env[RRC.Key.room] { return r } else { return nil } }()
        let src: Data? = { if case .bytes(let b) = env[RRC.Key.src] { return b } else { return nil } }()
        let nick: String? = { if case .text(let n) = env[RRC.Key.nick] { return n } else { return nil } }()
        let mid: Data? = { if case .bytes(let b) = env[RRC.Key.id] { return b } else { return nil } }()
        let ownHash = manager?.identity?.hash

        // Deduplicate own echoes
        if let s = src, let own = ownHash, s == own {
            if let m = mid, lock.withLock({ sentIDs.contains(m) }) { return }
        }

        // Learn nick
        if let s = src, let n = nick, !n.isEmpty {
            lock.withLock {
                nicks[s] = n
                if let r = rawRoom?.trimmingCharacters(in: .whitespaces).lowercased(), !r.isEmpty {
                    members[r, default: []].insert(s)
                }
            }
        }

        let room = rawRoom?.trimmingCharacters(in: .whitespaces).lowercased()
        var msg = RRCMessage(kind: kind, room: room, src: src, nick: nick,
                             text: body, ts: Int64(Date().timeIntervalSince1970 * 1000))

        // Mention detection
        let isOwn = (src != nil && ownHash != nil && src == ownHash)
        if !isOwn, let ownNick = getEffectiveNick(), !ownNick.isEmpty {
            msg.mention = mentionDetected(ownNick: ownNick, in: body)
        }

        recordMessage(msg)
    }

    /// Parse hub service notices (`/list` and `/who` replies) regardless of whether
    /// they arrived as a packet or a resource transfer.
    ///
    /// Returns `true` when the notice
    /// was consumed silently (an auto `/list` or `/who`) and should not be recorded to
    /// the message log. Mirrors Python `RRCHub._process_notice_text` (commit f07a035).
    private func processNoticeText(_ body: String) -> Bool {
        // Detect /list response
        if let parsed = RRCHub.parseRoomListNotice(body) {
            let silent: Bool = lock.withLock {
                availableRooms = parsed
                let s = silentListPending > 0
                if s { silentListPending -= 1 }
                return s
            }
            manager?.notifyChange(self)
            if silent { return true }
        }

        // Detect /who response
        if let (whoRoom, entries) = RRCHub.parseWhoNotice(body) {
            let silentWho: Bool = lock.withLock {
                var mset = members[whoRoom] ?? []
                for (nick, hexStr) in entries {
                    guard let hBytes = rrcHexData(hexStr) else { continue }
                    if nick == nil {
                        mset.insert(hBytes)
                    } else {
                        for ph in mset {
                            if ph.hex.hasPrefix(hexStr) { nicks[ph] = nick; break }
                        }
                    }
                }
                members[whoRoom] = mset
                let s = silentWhoRooms.contains(whoRoom)
                if s { silentWhoRooms.remove(whoRoom) }
                return s
            }
            manager?.notifyChange(self)
            if silentWho { return true }
        }

        return false
    }

    private func handleNotice(env: [Int: CBOR.Value]) {
        guard case .text(let body) = env[RRC.Key.body] else { return }
        let src: Data? = { if case .bytes(let b) = env[RRC.Key.src] { return b } else { return nil } }()
        let rawRoom: String? = { if case .text(let r) = env[RRC.Key.room] { return r } else { return nil } }()

        // Parse /list and /who service notices; a silently consumed auto reply is
        // not recorded to the log.
        if processNoticeText(body) { return }

        // MOTD: a notice with no room
        let room = rawRoom?.trimmingCharacters(in: .whitespaces).lowercased()
        if room == nil {
            lock.withLock { motd = body }
            manager?.notifyChange(self)
        }

        let msg = RRCMessage(kind: "notice", room: room, src: src, nick: nil, text: body,
                             ts: Int64(Date().timeIntervalSince1970 * 1000))
        recordNotice(msg)
    }

    private func handleError(env: [Int: CBOR.Value]) {
        let text: String
        if case .text(let b) = env[RRC.Key.body] { text = b } else { text = "(error)" }
        let rawRoom: String? = { if case .text(let r) = env[RRC.Key.room] { return r } else { return nil } }()
        let r = rawRoom?.trimmingCharacters(in: .whitespaces).lowercased()

        var rollbackJoin = false
        if let rm = r {
            lock.withLock {
                rollbackJoin = pendingJoins.contains(rm)
                pendingJoins.remove(rm)
                silentJoins.remove(rm)
                pendingParts.remove(rm)
                if rollbackJoin { rooms.remove(rm) }
            }
            if rollbackJoin { manager?.save() }
        }
        let msg = RRCMessage(kind: "error", room: r, src: nil, nick: nil, text: text,
                             ts: Int64(Date().timeIntervalSince1970 * 1000))
        recordNotice(msg)
    }

    private func handleResourceEnvelope(env: [Int: CBOR.Value]) {
        guard case .map(let bodyPairs) = env[RRC.Key.body] else { return }
        var body: [Int: CBOR.Value] = [:]
        for (k, v) in bodyPairs { if case .uint(let u) = k { body[Int(u)] = v } }
        guard case .bytes(let rid) = body[RRC.ResField.id],
              case .text(let kind) = body[RRC.ResField.kind],
              case .uint(let sizeu) = body[RRC.ResField.size], sizeu > 0 else { return }
        let size = Int(sizeu)
        let sha256: Data? = { if case .bytes(let b) = body[RRC.ResField.sha256] { return b } else { return nil } }()
        let encoding: String = { if case .text(let e) = body[RRC.ResField.encoding] { return e } else { return "utf-8" } }()
        let room: String? = { if case .text(let r) = env[RRC.Key.room] { return r.lowercased() } else { return nil } }()
        lock.withLock {
            // Sweep expired expectations on insert too (not only in
            // resourceConcluded)—a peer sending envelopes that never conclude
            // would otherwise grow this dictionary without bound.
            let now = Date()
            for (k, v) in resourceExpectations where v.expires < now { resourceExpectations[k] = nil }
            resourceExpectations[rid] = ResourceExpectation(kind: kind, size: size, sha256: sha256,
                                                              encoding: encoding, room: room,
                                                              expires: Date().addingTimeInterval(30))
        }
    }

    /// Accept/reject an inbound hub resource advertisement by size.
    ///
    /// Mirrors Python `RRCHub._resource_advertised` (commit 510d476): reject when the
    /// advertised data size exceeds the configured cap, or the cap is disabled (<= 0).
    internal func resourceAdvertised(size: Int) -> Bool {
        let maxSize = manager?.maxAcceptedResourceSize ?? RRCHub.defaultMaxAcceptedResourceSize
        if maxSize <= 0 || size > maxSize { return false }
        return true
    }

    /// Handle a concluded hub→client resource transfer.
    ///
    /// Matches the assembled payload
    /// to a previously advertised `ResourceExpectation` (by exact size), verifies the
    /// optional sha256, decodes the text, and routes MOTD / `/who` / `/list` notices
    /// through the same parser as the packet path. Mirrors Python
    /// `RRCHub._resource_concluded` (commit f07a035).
    internal func resourceConcluded(payload: Data) {
        let now = Date()
        let matched: ResourceExpectation? = lock.withLock {
            // Drop expired expectations, then match on exact assembled size.
            for (k, v) in resourceExpectations where v.expires < now { resourceExpectations[k] = nil }
            for (k, exp) in resourceExpectations where exp.size == payload.count {
                resourceExpectations[k] = nil
                return exp
            }
            return nil
        }

        let kind = matched?.kind ?? RRC.ResKind.blob
        let room = matched?.room

        // Verify the optional integrity hash before trusting the payload.
        if let sha = matched?.sha256, Data(SHA256.hash(data: payload)) != sha { return }

        // Only notice/MOTD payloads carry text that is acted on; blobs are ignored.
        guard kind == RRC.ResKind.notice || kind == RRC.ResKind.motd else { return }

        // Decode as UTF-8 (lossy—mirrors Python decode(errors="replace")). Resource
        // envelopes use utf-8; unknown encodings fall back to the same lossy decode.
        let text = String(decoding: payload, as: UTF8.self)

        if kind == RRC.ResKind.motd {
            lock.withLock { motd = text }
            manager?.notifyChange(self)
        } else if processNoticeText(text) {
            return
        }

        let msg = RRCMessage(kind: "notice", room: room, src: nil, nick: nil, text: text,
                             ts: Int64(Date().timeIntervalSince1970 * 1000))
        recordNotice(msg)
    }

    // MARK: - Message recording

    internal func recordMessage(_ msg: RRCMessage, local: Bool = false) {
        let room = msg.room ?? "*"
        let cap = perRoomCap()
        lock.withLock {
            var buf = messages[room] ?? []
            buf.append(msg)
            if let cap, buf.count > cap { buf.removeFirst(buf.count - cap) }
            messages[room] = buf
            if !local, let r = msg.room {
                if r != manager?.activeRoomFor(hub: self) {
                    unreadRooms.insert(r)
                    if msg.mention { mentionRooms.insert(r) }
                }
            }
        }
        // Fire the message callback OUTSIDE the hub lock (it invokes the app's
        // onMessageCallback, which may re-enter the hub—non-recursive lock).
        manager?.notifyMessages(hub: self, msg: msg)
        appendHistory(room: room, msg: msg)
        cleanHistory()
    }

    internal func recordSystem(room: String, text: String) {
        let msg = RRCMessage(kind: "system", room: room, src: nil, nick: nil, text: text,
                             ts: Int64(Date().timeIntervalSince1970 * 1000))
        let cap = perRoomCap()
        lock.withLock {
            var buf = messages[room] ?? []
            buf.append(msg)
            if let cap, buf.count > cap { buf.removeFirst(buf.count - cap) }
            messages[room] = buf
        }
        manager?.notifyMessages(hub: self, msg: msg)   // outside the lock (see recordMessage)
        appendHistory(room: room, msg: msg)
        cleanHistory()
    }

    internal func recordNotice(_ msg: RRCMessage) {
        var target = msg.room
        if target == nil { target = manager?.activeRoomFor(hub: self) }
        let cap = perRoomCap()
        lock.withLock {
            var m = msg; m.room = target
            notices.append(m)
            if notices.count > 200 { notices.removeFirst(notices.count - 200) }
            if let r = target {
                var buf = messages[r] ?? []
                buf.append(m)
                if let cap, buf.count > cap { buf.removeFirst(buf.count - cap) }
                messages[r] = buf
                if r != manager?.activeRoomFor(hub: self) { unreadRooms.insert(r) }
            }
        }
        manager?.notifyMessages(hub: self, msg: msg)   // outside the lock (see recordMessage)
        if let r = target {
            appendHistory(room: r, msg: msg)
            cleanHistory()
        }
    }

    // MARK: - History persistence

    internal func entryFor(_ msg: RRCMessage) -> [String: CBOR.Value] {
        var e: [String: CBOR.Value] = [
            RRC.HistKey.kind:    .text(msg.kind),
            RRC.HistKey.text:    .text(msg.text),
            RRC.HistKey.ts:      .uint(UInt64(bitPattern: msg.ts)),
            RRC.HistKey.mention: .bool(msg.mention),
        ]
        if let src = msg.src, !src.isEmpty { e[RRC.HistKey.src] = .bytes(src) }
        if let nick = msg.nick, !nick.isEmpty { e[RRC.HistKey.nick] = .text(nick) }
        return e
    }

    /// Rebuilds a message from a decoded history-log entry.
    public static func msgFromEntry(room: String, entry: [String: CBOR.Value]) -> RRCMessage? {
        guard let kindVal = entry[RRC.HistKey.kind], case .text(let kind) = kindVal,
              let textVal = entry[RRC.HistKey.text], case .text(let text) = textVal,
              let tsVal   = entry[RRC.HistKey.ts] else { return nil }
        let ts: Int64
        if case .uint(let u) = tsVal { ts = Int64(bitPattern: u) }
        else { ts = 0 }
        let src: Data?  = { if let v = entry[RRC.HistKey.src],  case .bytes(let b) = v { return b } else { return nil } }()
        let nick: String? = { if let v = entry[RRC.HistKey.nick], case .text(let n) = v { return n } else { return nil } }()
        let mention: Bool = { if let v = entry[RRC.HistKey.mention], case .bool(let b) = v { return b } else { return false } }()
        var msg = RRCMessage(kind: kind, room: room, src: src, nick: nick, text: text, ts: ts)
        msg.mention = mention
        return msg
    }

    /// Returns whether the history of `room` is written to disk.
    public static func persistableRoom(_ room: String) -> Bool {
        !room.isEmpty && room != "*"
    }

    internal func appendHistory(room: String, msg: RRCMessage) {
        guard RRCHub.persistableRoom(room), let mgr = manager else { return }
        let pairs = entryFor(msg).map { (CBOR.Value.text($0.key), $0.value) }
        let data  = CBOR.encode(.map(pairs))
        // Serialize disk writes under historyIOLock. On non-POSIX platforms
        // O_APPEND writes are not guaranteed atomic; the lock prevents interleaved
        // records from different concurrent callers.
        // Mirrors Python RRCHub._history_io_lock added in NomadNet RRC.py.
        historyIOLock.withLock {
            do {
                let dir = mgr.historyDir(hub: self)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let path = mgr.historyPath(hub: self, room: room)
                if let handle = FileHandle(forWritingAtPath: path.path) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                } else {
                    FileManager.default.createFile(atPath: path.path, contents: data)
                }
                historyWriteFailed = false
            } catch {
                if !historyWriteFailed {
                    historyWriteFailed = true
                }
            }
        }
    }

    internal func deleteHistory(room: String) {
        guard RRCHub.persistableRoom(room), let mgr = manager else { return }
        let path = mgr.historyPath(hub: self, room: room)
        try? FileManager.default.removeItem(at: path)
    }

    internal func loadHistory() {
        let doFilter = filterHistory()
        let cap      = perRoomCap()
        let roomList = lock.withLock { Array(messages.keys) }
        for room in roomList {
            guard RRCHub.persistableRoom(room), let mgr = manager else { continue }
            let path = mgr.historyPath(hub: self, room: room)
            guard let data = try? Data(contentsOf: path), !data.isEmpty else { continue }
            guard let items = try? CBOR.decodeAll(data) else { continue }
            var msgs: [RRCMessage] = []
            for item in items {
                guard case .map(let pairs) = item else { continue }
                var entry: [String: CBOR.Value] = [:]
                for (k, v) in pairs { if case .text(let s) = k { entry[s] = v } }
                guard let m = RRCHub.msgFromEntry(room: room, entry: entry) else { continue }
                // Filter ephemeral messages when enabled (matches Python _filter_history)
                if doFilter && (m.kind == "system" || m.kind == "notice") { continue }
                msgs.append(m)
            }
            // Apply per-room cap: keep the most recent `cap` messages
            if let cap, msgs.count > cap { msgs = Array(msgs.suffix(cap)) }
            lock.withLock { messages[room] = msgs }
        }
    }

    // MARK: - Notice parsing helpers (static, testable)

    /// Parses a `/who` notice into its room and member entries.
    public static func parseWhoNotice(_ text: String) -> (room: String, entries: [(nick: String?, hex: String)])? {
        let prefix = "members in "
        guard text.hasPrefix(prefix) else { return nil }
        let rest = String(text.dropFirst(prefix.count))
        guard let sepRange = rest.range(of: ": ") else { return nil }
        let room = String(rest[rest.startIndex..<sepRange.lowerBound]).trimmingCharacters(in: .whitespaces).lowercased()
        guard !room.isEmpty else { return nil }
        let bodyStr = String(rest[sepRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        if bodyStr == "(none)" || bodyStr.isEmpty { return (room, []) }

        var entries: [(nick: String?, hex: String)] = []
        // Split on ", " and parse each token as "nick (hex12)" or "fullhex32".
        let tokens = bodyStr.components(separatedBy: ", ")
        let hex32 = try? NSRegularExpression(pattern: "^[0-9a-fA-F]{32}$")
        let nickParen = try? NSRegularExpression(pattern: "^(.+?)\\s\\(([0-9a-fA-F]{12})\\)$")
        for token in tokens {
            let t = token.trimmingCharacters(in: .whitespaces)
            if hex32?.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil {
                entries.append((nick: nil, hex: t.lowercased()))
            } else if let m = nickParen?.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) {
                let nickRange = m.range(at: 1); let hexRange = m.range(at: 2)
                if let nr = Range(nickRange, in: t), let hr = Range(hexRange, in: t) {
                    entries.append((nick: String(t[nr]), hex: String(t[hr]).lowercased()))
                }
            }
        }
        return (room, entries)
    }

    /// Parses a `/list` notice into room names and topics.
    public static func parseRoomListNotice(_ text: String) -> [String: String?]? {
        let stripped = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped == "No public rooms registered" { return [:] }
        let lines = text.components(separatedBy: "\n")
        guard !lines.isEmpty, lines[0].trimmingCharacters(in: .whitespaces).hasPrefix("Registered public rooms")
        else { return nil }
        var rooms: [String: String?] = [:]
        for line in lines.dropFirst() {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty else { continue }
            if s.contains(" - ") {
                let parts = s.components(separatedBy: " - ")
                let name = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
                let rawTopic = parts.count > 1 ? parts[1...].joined(separator: " - ").trimmingCharacters(in: .whitespaces) : ""
                // Use updateValue to store nil without removing the key
                rooms.updateValue(rawTopic.isEmpty ? nil : rawTopic, forKey: name)
            } else {
                // Use updateValue to store nil without removing the key
                rooms.updateValue(nil, forKey: s.lowercased())
            }
        }
        return rooms
    }

    // MARK: - Private helpers

    private func makeBasePairs(type: Int, src: Data, room: String? = nil,
                                 mid: Data? = nil, ts: Int64? = nil) -> [(CBOR.Value, CBOR.Value)] {
        var pairs: [(CBOR.Value, CBOR.Value)] = [
            (.uint(UInt64(RRC.Key.version)), .uint(UInt64(RRC.version))),
            (.uint(UInt64(RRC.Key.type)),    .uint(UInt64(type))),
            (.uint(UInt64(RRC.Key.id)),      .bytes(mid ?? Data((0..<8).map { _ in UInt8.random(in: 0...255) }))),
            (.uint(UInt64(RRC.Key.ts)),      .uint(UInt64(bitPattern: ts ?? Int64(Date().timeIntervalSince1970 * 1000)))),
            (.uint(UInt64(RRC.Key.src)),     .bytes(src)),
        ]
        if let r = room { pairs.append((.uint(UInt64(RRC.Key.room)), .text(r))) }
        return pairs
    }

    private func mentionDetected(ownNick: String, in text: String) -> Bool {
        guard !ownNick.isEmpty else { return false }
        let escaped = NSRegularExpression.escapedPattern(for: ownNick)
        let pattern = "(?<![A-Za-z0-9_])@\(escaped)(?![A-Za-z0-9_])"
        let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        return re?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    internal func setStatus(_ status: Status, text: String? = nil) {
        lock.withLock {
            self.status = status
            if let t = text { statusText = t }
        }
        manager?.notifyChange(self)   // outside the lock (may re-enter the hub)
    }

    // MARK: - History behaviour helpers (Phase 22)

    /// Maximum in-memory messages per room (nil = no cap).
    ///
    /// Reads from `manager.rrcHistoryPerRoomCap`.
    internal func perRoomCap() -> Int? {
        guard let v = manager?.rrcHistoryPerRoomCap, v > 0 else { return nil }
        return v
    }

    /// Whether system/notice messages should be skipped when loading history from disk.
    ///
    /// Defaults to true (matches Python `rrc_filter_loaded_history`).
    internal func filterHistory() -> Bool {
        manager?.rrcFilterLoadedHistory ?? true
    }

    /// Seconds after which a system/notice message is pruned by `cleanHistory`.
    internal func ephemeralNoticesTimeout() -> TimeInterval {
        manager?.rrcEphemeralNoticesTimeout ?? RRCHub.sysNoticeTimeout
    }

    /// Sweep the in-memory message buffers, removing old ephemeral (system/notice) messages.
    ///
    /// Rate-limited to at most once per `cleanHistoryInterval` seconds.
    /// Matches Python `RRCHub._clean_history`.
    internal func cleanHistory() {
        let now = Date()
        let removeAfter = ephemeralNoticesTimeout()
        // Do the rate-limit check, the sweep, and the timestamp updates all under
        // the lock so `lastHistoryClean`/`cleanLastRemoved` don't race concurrent
        // record calls from the UI and link threads.
        lock.withLock {
            guard now.timeIntervalSince(lastHistoryClean) > RRCHub.cleanHistoryInterval else { return }
            var didClean = false
            for r in Array(messages.keys) {
                let before = messages[r]?.count ?? 0
                messages[r]?.removeAll { m in
                    let isEphemeral = m.kind == "system" || m.kind == "notice"
                    let ageSeconds  = now.timeIntervalSince1970 - Double(m.ts) / 1000.0
                    return isEphemeral && ageSeconds > removeAfter
                }
                if (messages[r]?.count ?? 0) < before { didClean = true }
            }
            lastHistoryClean = now
            if didClean { cleanLastRemoved = now }
        }
    }

    // MARK: - Test helpers (accessible via @testable import)

    /// Directly insert a message into the in-memory buffer without side effects (for tests).
    internal func testInjectMessage(room: String, msg: RRCMessage) {
        lock.withLock { messages[room, default: []].append(msg) }
    }

    /// Reset the history-clean cooldown so the next `cleanHistory()` call runs immediately.
    internal func testResetHistoryClean() {
        lastHistoryClean = .distantPast
    }
}

// MARK: - RRCManager

/// Manages a list of RRC hub connections and persists their configuration.
///
/// Corresponds to Python `RRCManager` in `nomadnet/RRC.py`.
public final class RRCManager {

    // MARK: Public state

    /// Hubs this manager holds.
    public private(set) var hubs: [RRCHub] = []
    /// Fires when hub or room state changes.
    public var onChangeCallback:  ((RRCHub?) -> Void)?
    /// Fires for each message received on any hub.
    public var onMessageCallback: ((RRCHub, RRCMessage) -> Void)?

    /// Maximum size, in bytes, of a hub→client resource transfer this client
    /// accepts.
    ///
    /// Larger advertisements are rejected; `<= 0` disables all resource
    /// acceptance. Mirrors Python `rrc_max_accepted_resource_size` (default 256 KiB).
    public var maxAcceptedResourceSize: Int = RRCHub.defaultMaxAcceptedResourceSize

    // Optional production app protocol—provides identity + storage
    /// Owning application, supplying identity and storage.
    public weak var app: NomadNetworkAppProtocol?

    // Direct identity / storage for test-mode construction (override app)
    private var identityOverride:  Identity?
    private var storageOverride:   URL?
    private var nicknameOverride:  String?

    // Test-friendly overrides for history behavior (bypass app protocol)
    internal var rrcHistoryPerRoomCapOverride:       Int?          = nil
    internal var rrcFilterLoadedHistoryOverride:     Bool?         = nil
    internal var rrcEphemeralNoticesTimeoutOverride: TimeInterval? = nil

    internal var rrcHistoryPerRoomCap: Int? {
        rrcHistoryPerRoomCapOverride ?? app?.rrcHistoryPerRoomCap
    }
    internal var rrcFilterLoadedHistory: Bool {
        rrcFilterLoadedHistoryOverride ?? app?.rrcFilterLoadedHistory ?? true
    }
    internal var rrcEphemeralNoticesTimeout: TimeInterval {
        rrcEphemeralNoticesTimeoutOverride ?? app?.rrcEphemeralNoticesTimeout ?? 600.0
    }

    private let lock     = NSLock()
    private let saveLock = NSLock()
    private var loaded   = false
    private var loading  = false
    private var activeHub:  RRCHub? = nil
    private var activeRoom: String? = nil

    // MARK: Internal (tests share hub lists for path resolution)
    internal var lockedHubs: [RRCHub] {
        get { lock.withLock { hubs } }
        set { lock.withLock { hubs = newValue } }
    }

    // MARK: Init

    /// Production init—supply an app conforming to `NomadNetworkAppProtocol`.
    public init(app: NomadNetworkAppProtocol? = nil) {
        self.app = app
    }

    /// Test-friendly init—supply identity / storagePath / nickname directly.
    public convenience init(identity: Identity, storagePath: URL? = nil, nickname: String? = nil) {
        self.init(app: nil)
        identityOverride = identity
        storageOverride  = storagePath
        nicknameOverride = nickname
    }

    // MARK: Identity / storage / nick

    /// Identity used for hub links.
    public var identity: Identity? {
        identityOverride ?? app?.identity
    }

    /// Directory hub history and settings are stored under.
    public var storagePath: URL? {
        storageOverride ?? app?.storagePath
    }

    /// Returns the application-wide display nickname.
    public func getNickname() -> String? {
        nicknameOverride ?? app?.peerDisplayName
    }

    // MARK: Hub management

    /// Adds a hub, returning the existing one when it is already held.
    @discardableResult
    public func addHub(hash: Data, destName: String? = nil, name: String? = nil) -> RRCHub {
        let dn = destName ?? RRC.defaultDestName
        if let existing = lock.withLock({ hubs.first(where: { $0.hubHash == hash && $0.destName == dn }) }) {
            return existing
        }
        let hub = RRCHub(manager: self, hubHash: hash, destName: destName, name: name)
        lock.withLock { hubs.append(hub) }
        if !loading { save() }
        notifyChange(nil)
        return hub
    }

    /// Removes `hub` and disconnects it.
    public func removeHub(_ hub: RRCHub) {
        hub.manager = nil   // break retain cycle before release
        lock.withLock { hubs.removeAll { $0 === hub } }
        hub.disconnect()
        save()
        notifyChange(nil)
    }

    /// Returns the held hub matching `hash` and `destName`.
    public func findHub(hash: Data, destName: String? = nil) -> RRCHub? {
        let dn = destName ?? RRC.defaultDestName
        return lock.withLock { hubs.first { $0.hubHash == hash && $0.destName == dn } }
    }

    // MARK: Active room / unread

    /// Whether any hub holds unread messages.
    public var hasUnread: Bool {
        lock.withLock { hubs.contains { !$0.unreadRooms.isEmpty } }
    }

    /// Marks `room` on `hub` as the active view.
    public func setActive(hub: RRCHub, room: String?) {
        // activeHub/activeRoom are read by activeRoomFor from other threads.
        lock.withLock { activeHub = hub; activeRoom = room }
        if let r = room { hub.markRead(r) }   // outside the lock (takes the hub's lock)
    }

    /// Returns the active room for `hub`.
    public func activeRoomFor(hub: RRCHub) -> String? {
        lock.withLock { activeHub === hub ? activeRoom : nil }
    }

    // MARK: Callbacks

    internal func notifyChange(_ hub: RRCHub?) {
        onChangeCallback?(hub)
    }

    internal func notifyMessages(hub: RRCHub, msg: RRCMessage) {
        onMessageCallback?(hub, msg)
    }

    /// Called when a hub receives T_WELCOME: re-join all remembered rooms.
    internal func onWelcome(hub: RRCHub) {
        // Snapshot the rooms Set under the hub's lock (packet handlers mutate it).
        for r in hub.snapshotRooms() {
            try? hub.joinRoom(r, silent: true)
        }
    }

    // MARK: Shutdown

    /// Disconnects every hub and stops background work.
    public func shutdown() {
        // Break the RRCHub -> manager strong reference too (as removeHub does),
        // so tearing down a manager without removing hubs first doesn't leak.
        lock.withLock { hubs }.forEach { $0.disconnect(); $0.manager = nil }
    }

    // MARK: Persistence (CBOR, matches Python's save/load format)

    internal func storePath() -> URL? {
        storagePath?.appendingPathComponent("rrc_hubs")
    }

    internal func historyRoot() -> URL? {
        storagePath?.appendingPathComponent("rrc_history")
    }

    internal func historyDir(hub: RRCHub) -> URL {
        let root = historyRoot() ?? URL(fileURLWithPath: NSTemporaryDirectory())
        var key = hub.hubHash.hex
        if hub.destName != RRC.defaultDestName {
            let suffix = SHA256.hash(data: Data(hub.destName.utf8))
                .prefix(4).map { String(format: "%02x", $0) }.joined()
            key = key + "__" + suffix
        }
        return root.appendingPathComponent(key)
    }

    internal func historyPath(hub: RRCHub, room: String) -> URL {
        let dir = historyDir(hub: hub)
        let sanitized = String(room.replacingOccurrences(of: "[^a-z0-9._-]",
            with: "_", options: .regularExpression).prefix(64))
        let roomHash = SHA256.hash(data: Data(room.utf8))
            .prefix(4).map { String(format: "%02x", $0) }.joined()
        let filename = sanitized.isEmpty ? "\(roomHash).log" : "\(sanitized)_\(roomHash).log"
        return dir.appendingPathComponent(filename)
    }

    /// Writes hub settings to storage.
    public func save() {
        guard !loading else { return }
        guard let path = storePath() else { return }
        let tmpPath = path.appendingPathExtension("tmp")
        saveLock.lock(); defer { saveLock.unlock() }
        let hubList = lock.withLock { hubs }
        var entries: [(CBOR.Value, CBOR.Value)] = []
        for h in hubList {
            // Snapshot rooms + message-room keys atomically under the hub's lock
            // (packet handlers mutate both concurrently).
            let (joined, parted) = h.snapshotRoomsForSave()
            var e: [(CBOR.Value, CBOR.Value)] = [
                (.text("hash"),           .bytes(h.hubHash)),
                (.text("dest_name"),      .text(h.destName)),
                (.text("name"),           .text(h.name)),
                (.text("rooms"),          .array(joined.sorted().map { .text($0) })),
                (.text("parted_rooms"),   .array(parted.sorted().map { .text($0) })),
                (.text("auto_reconnect"), .bool(h.autoReconnect)),
                (.text("auto_list"),      .bool(h.autoList)),
                (.text("auto_who"),       .bool(h.autoWho)),
            ]
            if let nick = h.nickOverride, !nick.isEmpty {
                e.append((.text("nick"), .text(nick)))
            }
            entries.append((.text(""), .map(e)))  // key ignored; stored as an array item
        }
        let entryValues: [CBOR.Value] = entries.map { $0.1 }
        let payload = CBOR.encode(.map([(.text("hubs"), .array(entryValues))]))
        do {
            try payload.write(to: tmpPath)
            _ = try FileManager.default.replaceItemAt(path, withItemAt: tmpPath)
        } catch {
            try? FileManager.default.removeItem(at: tmpPath)
        }
    }

    /// Reads hub settings from storage.
    public func load() {
        guard !loaded, let path = storePath() else { return }
        guard FileManager.default.fileExists(atPath: path.path) else { loaded = true; return }
        loaded   = true
        loading  = true
        defer { loading = false }
        do {
            let data = try Data(contentsOf: path)
            let top  = try CBOR.decode(data)
            guard case .map(let topPairs) = top else { return }
            var topDict: [String: CBOR.Value] = [:]
            for (k, v) in topPairs { if case .text(let s) = k { topDict[s] = v } }
            guard case .array(let items) = topDict["hubs"] else { return }
            for item in items {
                guard case .map(let pairs) = item else { continue }
                var d: [String: CBOR.Value] = [:]
                for (k, v) in pairs { if case .text(let s) = k { d[s] = v } }
                guard case .bytes(let hh) = d["hash"] else { continue }
                let dn: String? = { if case .text(let s) = d["dest_name"] { return s } else { return nil } }()
                let nm: String? = { if case .text(let s) = d["name"]      { return s } else { return nil } }()
                let hub = addHub(hash: hh, destName: dn, name: nm)
                if case .array(let rs) = d["rooms"] {
                    for rv in rs { if case .text(let r) = rv { _ = hub.addRoom(r) } }
                }
                if case .array(let ps) = d["parted_rooms"] {
                    for rv in ps {
                        if case .text(let r) = rv, let rn = try? hub.normalizeRoom(r) {
                            if hub.messages[rn] == nil { hub.messages[rn] = [] }
                        }
                    }
                }
                if case .bool(let b) = d["auto_reconnect"] { hub.autoReconnect = b }
                if case .bool(let b) = d["auto_list"]      { hub.autoList      = b }
                if case .bool(let b) = d["auto_who"]       { hub.autoWho       = b }
                if case .text(let n) = d["nick"], !n.isEmpty { hub.nickOverride = n }
                hub.loadHistory()
            }
        } catch {}
    }
}

// MARK: - NomadNetworkAppProtocol

/// Host application services an `RRCManager` needs.
public protocol NomadNetworkAppProtocol: AnyObject {
    var reticulum:    Reticulum { get }
    var identity:     Identity  { get }
    var storagePath:  URL?      { get }
    var peerDisplayName: String? { get }

    /// Maximum messages to keep per room in the in-memory buffer and when loading history.
    /// nil (or 0) means no cap. Default: nil.
    var rrcHistoryPerRoomCap: Int? { get }

    /// If true, system/notice messages are filtered out when loading history from disk.
    /// Default: true (matches Python `rrc_filter_loaded_history`).
    var rrcFilterLoadedHistory: Bool { get }

    /// Seconds after which a loaded system/notice message is removed by `cleanHistory`.
    /// Default: 600.0 (matches Python `SYS_NOTICE_TIMEOUT`).
    var rrcEphemeralNoticesTimeout: TimeInterval { get }
}

/// Default implementations for optional history-tuning properties.
public extension NomadNetworkAppProtocol {
    var rrcHistoryPerRoomCap:       Int?         { nil }
    var rrcFilterLoadedHistory:     Bool         { true }
    var rrcEphemeralNoticesTimeout: TimeInterval { 600.0 }
}

// MARK: - Data helpers (private, avoids collision with NomadNetURL.swift)

private func rrcHexData(_ hex: String) -> Data? {
    let h = hex.count % 2 == 0 ? hex : "0" + hex
    var data = Data(capacity: h.count / 2)
    var idx = h.startIndex
    while idx < h.endIndex {
        let next = h.index(idx, offsetBy: 2)
        guard let byte = UInt8(h[idx..<next], radix: 16) else { return nil }
        data.append(byte)
        idx = next
    }
    return data
}
