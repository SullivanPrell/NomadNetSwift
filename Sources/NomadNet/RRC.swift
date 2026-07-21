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
/// Corresponds to Python `RRCMessage` in `nomadnet/RRC.py`.
public struct RRCMessage {
    public var kind:    String
    public var room:    String?
    public var src:     Data?
    public var nick:    String?
    public var text:    String
    public var ts:      Int64
    public var mention: Bool = false

    public init(kind: String, room: String?, src: Data?, nick: String?,
                text: String, ts: Int64) {
        self.kind = kind; self.room = room; self.src = src
        self.nick = nick; self.text = text; self.ts  = ts
    }
}

// MARK: - RRC constants

public enum RRC {
    public static let version: Int = 1

    /// Integer CBOR map keys — K_V, K_T, K_ID, K_TS, K_SRC, K_ROOM, K_BODY, K_NICK
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

    /// HELLO body indices — B_HELLO_NAME, B_HELLO_VER, B_HELLO_CAPS
    public enum HelloField {
        public static let name: Int = 0
        public static let ver:  Int = 1
        public static let caps: Int = 2
    }

    /// WELCOME body indices — B_WELCOME_HUB, B_WELCOME_VER, B_WELCOME_CAPS, B_WELCOME_LIMITS
    public enum WelcomeField {
        public static let hub:    Int = 0
        public static let ver:    Int = 1
        public static let caps:   Int = 2
        public static let limits: Int = 3
    }

    /// Capability flag indices — CAP_RESOURCE_ENVELOPE, CAP_ACTION
    public enum Cap {
        public static let resourceEnvelope: Int = 0
        public static let action:           Int = 1
    }

    /// Indices into the WELCOME limits dict — L_MAX_NICK_BYTES, …, L_RATE_LIMIT_MSGS_PER_MINUTE
    public enum LimitField {
        public static let maxNickBytes:            Int = 0
        public static let maxRoomNameBytes:        Int = 1
        public static let maxMsgBodyBytes:         Int = 2
        public static let maxRoomsPerSession:      Int = 3
        public static let rateLimitMsgsPerMinute:  Int = 4
    }

    /// Indices into T_RESOURCE_ENVELOPE body — B_RES_ID, …, B_RES_ENCODING
    public enum ResField {
        public static let id:       Int = 0
        public static let kind:     Int = 1
        public static let size:     Int = 2
        public static let sha256:   Int = 3
        public static let encoding: Int = 4
    }

    /// Resource kind strings — RES_KIND_NOTICE, RES_KIND_MOTD, RES_KIND_BLOB
    public enum ResKind {
        public static let notice: String = "notice"
        public static let motd:   String = "motd"
        public static let blob:   String = "blob"
    }

    /// CBOR text keys used in per-room history log entries — H_KIND, H_SRC, H_NICK, …
    public enum HistKey {
        public static let kind:    String = "k"
        public static let src:     String = "s"
        public static let nick:    String = "n"
        public static let text:    String = "t"
        public static let ts:      String = "ts"
        public static let mention: String = "m"
    }

    /// Default hub limits — DEFAULT_MAX_NICK_BYTES, …
    public static let defaultMaxNickBytes:  Int = 32
    public static let defaultMaxRoomBytes:  Int = 64
    public static let defaultMaxMsgBytes:   Int = 350
    public static let defaultMaxRooms:      Int = 32
    public static let defaultRatePerMinute: Int = 240

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

    public static let defaultDestName: String = "rrc.hub"

    // MARK: - Envelope

    public struct Envelope {
        public let version: Int
        public let type:    Int
        public let id:      Data
        public let ts:      Int64
        public let src:     Data
        public var room:    String?
        public var body:    String?
        public var nick:    String?
    }

    public static func makeEnvelope(type: Int, src: Data, mid: Data? = nil, ts: Int64? = nil,
                                     room: String? = nil, body: String? = nil,
                                     nick: String? = nil) -> Envelope {
        Envelope(version: version, type: type,
                 id:   mid ?? Data((0..<8).map { _ in UInt8.random(in: 0...255) }),
                 ts:   ts  ?? Int64(Date().timeIntervalSince1970 * 1000),
                 src:  src, room: room, body: body, nick: nick)
    }

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

    public enum DecodeError: Error {
        case missingField(String)
        case unexpectedType(String)
    }
}

// MARK: - RRCHubError

public enum RRCHubError: Error {
    case notConnected
    case emptyRoom
    case messageTooLong
    case commandMustStartWithSlash
    case identityUnavailable
}

// MARK: - RRCHub

/// A connection to a single RRC hub.
/// Corresponds to Python `RRCHub` in `nomadnet/RRC.py`.
public final class RRCHub {

    // MARK: Status

    public enum Status: Int {
        case disconnected = 0, connecting = 1, connected = 2, failed = 3
    }

    // MARK: Public read-only state

    public let hubHash: Data
    public let destName: String
    public var name: String

    public private(set) var status:      Status = .disconnected
    public private(set) var statusText:  String = "Disconnected"
    public private(set) var welcomed:    Bool   = false
    public private(set) var hubName:     String? = nil
    public private(set) var hubVersion:  String? = nil
    public private(set) var hubCaps:     [Int: Bool] = [:]
    public              var motd:        String? = nil

    // Hub-advertised limits (updated on T_WELCOME)
    public private(set) var maxNickBytes:          Int = RRC.defaultMaxNickBytes
    public private(set) var maxRoomNameBytes:      Int = RRC.defaultMaxRoomBytes
    public private(set) var maxMsgBodyBytes:       Int = RRC.defaultMaxMsgBytes
    public private(set) var maxRoomsPerSession:    Int = RRC.defaultMaxRooms
    public private(set) var rateLimitMsgsPerMinute:Int = RRC.defaultRatePerMinute

    // Room / message / member state (lock-protected)
    public private(set) var rooms:       Set<String> = []
    public private(set) var unreadRooms: Set<String> = []
    public private(set) var mentionRooms:Set<String> = []
    public private(set) var notices:     [RRCMessage] = []
    public private(set) var availableRooms: [String: String?] = [:]

    // Settings
    public var autoReconnect: Bool = false
    public var autoList:      Bool = false
    public var autoWho:       Bool = false
    public var nickOverride:  String? = nil

    // MARK: Internal state (accessible from tests via @testable import)

    internal var messages:  [String: [RRCMessage]] = [:]
    internal var members:   [String: Set<Data>] = [:]
    internal var nicks:     [Data: String] = [:]
    internal var _reconnectAttempts: Int = 0
    internal var _sentIDs:           [Data] = []    // ring buffer, maxlen = 256
    internal var _pendingPings:      [Data: (Int64, String?)] = [:]
    internal var _pendingJoins:      Set<String> = []
    internal var _pendingParts:      Set<String> = []
    internal var _silentJoins:       Set<String> = []
    internal var _silentWhoRooms:    Set<String> = []
    internal var _silentListPending: Int = 0
    internal var _sendHook:          ((Data) -> Void)? = nil

    // MARK: Class-level constants

    /// Minimum elapsed time (seconds) between consecutive `_cleanHistory` sweeps.
    /// Matches Python `RRCHub.CLEAN_HISTORY_INTERVAL = 5`.
    internal static let cleanHistoryInterval: TimeInterval = 5.0

    /// Default lifetime (seconds) for ephemeral messages when no app override is set.
    /// Matches Python `RRCHub.SYS_NOTICE_TIMEOUT = 600`.
    internal static let sysNoticeTimeout: TimeInterval = 600.0

    // MARK: Private

    private let _lock = NSLock()
    /// Serializes history-file writes. On non-POSIX platforms O_APPEND writes
    /// are not guaranteed to be atomic; this lock prevents interleaved writes.
    /// Mirrors Python `RRCHub._history_io_lock` added for cross-platform safety.
    private let _historyIOLock = NSLock()
    private var _link: Link? = nil
    private var _manualDisconnect: Bool = false
    private var _reconnectTask:    Task<Void, Never>? = nil
    private var _helloTask:        Task<Void, Never>? = nil
    private var _welcomed:         Bool = false
    private var _historyWriteFailed: Bool = false
    private var _lastHistoryClean: Date = .distantPast
    public  var cleanLastRemoved:  Date = .distantPast
    private var _resourceExpectations: [Data: ResourceExpectation] = [:]

    /// Strong reference to the owning manager.
    /// The retain cycle (manager→hub→manager) is broken by `RRCManager.removeHub`
    /// which sets `hub.manager = nil` before releasing the hub.
    internal var manager: RRCManager?

    /// Default cap on an accepted hub→client resource transfer (256 KiB).
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

    public init(manager: RRCManager, hubHash: Data, destName: String? = nil, name: String? = nil) {
        self.manager  = manager
        self.hubHash  = hubHash
        self.destName = destName ?? RRC.defaultDestName
        self.name     = name ?? hubHash.hex.prefix(8).description
    }

    // MARK: - Room management

    @discardableResult
    public func addRoom(_ room: String) -> String {
        let r = (try? normalizeRoom(room)) ?? room.lowercased().trimmingCharacters(in: .whitespaces)
        _lock.withLock {
            rooms.insert(r)
            if messages[r] == nil { messages[r] = [] }
        }
        manager?.save()
        manager?._notifyChange(self)
        return r
    }

    public func removeRoom(_ room: String) {
        guard let r = try? normalizeRoom(room) else { return }
        _lock.withLock {
            rooms.remove(r)
            messages.removeValue(forKey: r)
            unreadRooms.remove(r)
            mentionRooms.remove(r)
            members.removeValue(forKey: r)
        }
        _deleteHistory(room: r)
        manager?.save()
        manager?._notifyChange(self)
    }

    public func clearMessages(_ room: String) {
        guard let r = try? normalizeRoom(room) else { return }
        _lock.withLock {
            messages[r] = []
            unreadRooms.remove(r)
            mentionRooms.remove(r)
        }
        _deleteHistory(room: r)
        manager?._notifyChange(self)
    }

    public func getMembers(room: String) -> [Data] {
        guard let r = try? normalizeRoom(room) else { return [] }
        return _lock.withLock { Array(members[r] ?? []) }
    }

    public func markRead(_ room: String) {
        guard let r = try? normalizeRoom(room) else { return }
        _lock.withLock {
            unreadRooms.remove(r)
            mentionRooms.remove(r)
        }
        manager?._notifyChange(self)
    }

    public func getMessages(room: String) -> [RRCMessage] {
        guard let r = try? normalizeRoom(room) else { return [] }
        return _lock.withLock { Array(messages[r] ?? []) }
    }

    /// Snapshot the joined-rooms set under the hub lock (callers on other threads
    /// must not iterate `rooms` directly — packet handlers mutate it).
    internal func snapshotRooms() -> [String] {
        _lock.withLock { Array(rooms) }
    }

    /// Snapshot the joined rooms and the parted-room message keys atomically
    /// under the hub lock, for a consistent view during save().
    internal func snapshotRoomsForSave() -> (joined: [String], parted: [String]) {
        _lock.withLock {
            let joined = Array(rooms)
            let parted = messages.keys.filter { !rooms.contains($0) }
            return (joined, parted)
        }
    }

    public func normalizeRoom(_ room: String) throws -> String {
        let r = room.trimmingCharacters(in: .whitespaces).lowercased()
        guard !r.isEmpty else { throw RRCHubError.emptyRoom }
        return r
    }

    // MARK: - Nick / display name

    public func displayNameFor(_ peer: Data) -> String {
        let nick = _lock.withLock { nicks[peer] }
        if let n = nick, !n.isEmpty { return n }
        return peer.hex.prefix(12).description
    }

    public func getEffectiveNick() -> String? {
        if let n = nickOverride, !n.isEmpty { return n }
        return manager?.getNickname()
    }

    public func setNickOverride(_ nick: String?) {
        _lock.withLock {
            nickOverride = (nick == nil || nick!.isEmpty) ? nil : nick
        }
        manager?.save()
        manager?._notifyChange(self)
    }

    // MARK: - Settings

    public func setAutoReconnect(_ enabled: Bool, save: Bool = true) {
        _lock.withLock { autoReconnect = enabled }
        if save { manager?.save() }
        manager?._notifyChange(self)
    }

    public func setAutoList(_ enabled: Bool, save: Bool = true) {
        _lock.withLock { autoList = enabled }
        if save { manager?.save() }
        manager?._notifyChange(self)
    }

    public func setAutoWho(_ enabled: Bool, save: Bool = true) {
        _lock.withLock { autoWho = enabled }
        if save { manager?.save() }
        manager?._notifyChange(self)
    }

    // MARK: - Connection state machine

    public func connect() {
        let shouldSkip = _lock.withLock { () -> Bool in
            guard status != .connecting && status != .connected else { return true }
            _manualDisconnect = false
            _reconnectTask?.cancel(); _reconnectTask = nil
            let text = _reconnectAttempts > 0 ? "Reconnecting (attempt \(_reconnectAttempts))" : "Connecting"
            // Set state directly: we already hold `_lock`, and `_setStatus` would
            // re-acquire the same non-recursive NSLock → deadlock. Notify AFTER the
            // lock is released (below), mirroring `_setStatus`'s own ordering.
            self.status = .connecting
            self.statusText = text
            return false
        }
        guard !shouldSkip else { return }
        manager?._notifyChange(self)   // outside the lock (may re-enter the hub)
        Task { await _connectWorker() }
    }

    private func _connectWorker() async {
        guard let mgr = manager, let identity = mgr.identity else {
            _setStatus(.failed, text: "No identity"); return
        }
        guard let transport = mgr.app?.reticulum.transport else {
            _setStatus(.failed, text: "No transport"); return
        }

        // Request path if unknown. Wait up to 20s — path resolution over a real
        // multi-hop mesh (public transport backbone) can take well over the old 5s,
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
            _setStatus(.failed, text: "Hub identity unknown"); return
        }

        do {
            let dest = try Destination(identity: hubIdent, direction: .out, kind: .single,
                                       appName: "rrc", aspects: ["hub"])
            guard dest.hash == hubHash else {
                _setStatus(.failed, text: "Hash/destination name mismatch"); return
            }
            let link = try Link.initiate(destination: dest, transport: transport)
            link.onDataReceived = { [weak self] data, _ in self?._onPacket(data) }
            link.onEstablished  = { [weak self] _ in self?._onEstablished()      }
            link.onClosed       = { [weak self] _ in self?._onClosed()           }
            _lock.withLock { _link = link }
        } catch {
            _setStatus(.failed, text: "Connect error: \(error)")
        }
        _ = identity  // suppress unused warning
    }

    private func _onEstablished() {
        guard let mgr = manager, let identity = mgr.identity else { return }
        _setStatus(.connecting, text: "Identified, sending HELLO")
        try? _link?.identify(as: identity)
        _link?.resourceStrategy = .acceptApp
        // Accept and consume hub→client resource transfers (MOTD, long notices, and
        // large /who or /list replies the hub sends as a resource when they exceed the
        // link packet MDU). Without these callbacks the Link rejects every hub resource.
        _link?.onResourceAdvertised = { [weak self] adv, _ in self?._resourceAdvertised(size: Int(adv.dataSize)) ?? false }
        _link?.onResourceConcluded  = { [weak self] payload, _, _ in self?._resourceConcluded(payload: payload) }

        _helloTask?.cancel()
        _helloTask = Task { [weak self] in
            guard let self = self else { return }
            var attempts = 0
            while !Task.isCancelled && !self.welcomed && attempts < 5 {
                self._sendHello()
                attempts += 1
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
            if !self.welcomed && !Task.isCancelled {
                self._setStatus(.failed, text: "WELCOME timeout")
                self._lock.withLock {
                    try? self._link?.teardown()
                }
            }
        }
    }

    private func _onClosed() {
        _helloTask?.cancel(); _helloTask = nil
        let shouldReconnect = _lock.withLock { () -> Bool in
            _link = nil
            welcomed = false
            motd = nil
            members.removeAll()
            _resourceExpectations.removeAll()
            _pendingJoins.removeAll()
            _pendingParts.removeAll()
            _silentJoins.removeAll()
            _silentWhoRooms.removeAll()
            return autoReconnect && !_manualDisconnect
        }
        _setStatus(.disconnected, text: "Disconnected")
        if shouldReconnect { _scheduleReconnect() }
    }

    internal func _scheduleReconnect() {
        _lock.withLock { _reconnectAttempts += 1 }
        let attempts = _lock.withLock { _reconnectAttempts }
        let backoff = min(60.0, max(1.0, pow(2.0, Double(min(attempts, 6)))))
        _setStatus(.disconnected, text: "Reconnect in \(Int(backoff))s")
        _reconnectTask?.cancel()
        _reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
            guard !Task.isCancelled else { return }
            let go = self?._lock.withLock { () -> Bool in
                guard let s = self else { return false }
                return !s._manualDisconnect && s.autoReconnect
            } ?? false
            if go { self?.connect() }
        }
    }

    public func disconnect() {
        _helloTask?.cancel(); _helloTask = nil
        let link = _lock.withLock { () -> Link? in
            _manualDisconnect = true
            _reconnectAttempts = 0
            _reconnectTask?.cancel(); _reconnectTask = nil
            let l = _link; _link = nil; return l
        }
        try? link?.teardown()
        _setStatus(.disconnected, text: "Disconnected")
    }

    // MARK: - Outbound send

    /// Build and "send" a CBOR envelope. In tests, intercepted by `_sendHook`.
    internal func _sendEnv(_ pairs: [(CBOR.Value, CBOR.Value)]) throws {
        let payload = CBOR.encode(.map(pairs))
        if let hook = _sendHook { hook(payload); return }
        guard let link = _link else { throw RRCHubError.notConnected }
        try link.send(payload)
    }

    /// Sends the RRC HELLO handshake packet.
    internal func _sendHello() {
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
        try? _sendEnv(pairs)
    }

    // MARK: - Room messaging

    public func joinRoom(_ room: String, key: String? = nil, silent: Bool = false) throws {
        let r = try normalizeRoom(room)
        let ownSrc = manager?.identity?.hash ?? Data()
        var pairs: [(CBOR.Value, CBOR.Value)] = _makeBasePairs(type: RRC.MessageType.join, src: ownSrc, room: r)
        if let k = key, !k.isEmpty {
            pairs.append((.uint(UInt64(RRC.Key.body)), .text(k)))
        }
        if let nick = getEffectiveNick() {
            pairs.append((.uint(UInt64(RRC.Key.nick)), .text(nick)))
        }
        _lock.withLock {
            _pendingJoins.insert(r)
            if silent { _silentJoins.insert(r) }
        }
        try _sendEnv(pairs)
        _lock.withLock { if messages[r] == nil { messages[r] = [] } }
        manager?._notifyChange(self)
    }

    public func partRoom(_ room: String) {
        guard let r = try? normalizeRoom(room) else { return }
        let ownSrc = manager?.identity?.hash ?? Data()
        let pairs = _makeBasePairs(type: RRC.MessageType.part, src: ownSrc, room: r)
        _lock.withLock { _pendingParts.insert(r) }
        try? _sendEnv(pairs)
        _lock.withLock { rooms.remove(r) }
        manager?.save()
        manager?._notifyChange(self)
    }

    @discardableResult
    public func sendMessage(room: String, text: String) throws -> Data {
        let r = try normalizeRoom(room)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RRCHubError.messageTooLong }
        guard text.utf8.count <= maxMsgBodyBytes else { throw RRCHubError.messageTooLong }
        let ownSrc = manager?.identity?.hash ?? Data()
        let mid = Data((0..<8).map { _ in UInt8.random(in: 0...255) })
        var pairs = _makeBasePairs(type: RRC.MessageType.msg, src: ownSrc, room: r, mid: mid)
        pairs.append((.uint(UInt64(RRC.Key.body)), .text(text)))
        if let nick = getEffectiveNick() {
            pairs.append((.uint(UInt64(RRC.Key.nick)), .text(nick)))
        }
        _lock.withLock {
            _sentIDs.append(mid)
            if _sentIDs.count > 256 { _sentIDs.removeFirst(_sentIDs.count - 256) }
        }
        try _sendEnv(pairs)
        let msg = RRCMessage(kind: "msg", room: r, src: ownSrc,
                             nick: getEffectiveNick(), text: text,
                             ts: Int64(Date().timeIntervalSince1970 * 1000))
        _recordMessage(msg, local: true)
        return mid
    }

    @discardableResult
    public func sendAction(room: String, text: String) throws -> Data {
        let r = try normalizeRoom(room)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RRCHubError.messageTooLong }
        guard text.utf8.count <= maxMsgBodyBytes else { throw RRCHubError.messageTooLong }
        let ownSrc = manager?.identity?.hash ?? Data()
        let mid = Data((0..<8).map { _ in UInt8.random(in: 0...255) })
        var pairs = _makeBasePairs(type: RRC.MessageType.action, src: ownSrc, room: r, mid: mid)
        pairs.append((.uint(UInt64(RRC.Key.body)), .text(text)))
        if let nick = getEffectiveNick() {
            pairs.append((.uint(UInt64(RRC.Key.nick)), .text(nick)))
        }
        _lock.withLock {
            _sentIDs.append(mid)
            if _sentIDs.count > 256 { _sentIDs.removeFirst(_sentIDs.count - 256) }
        }
        try _sendEnv(pairs)
        let msg = RRCMessage(kind: "action", room: r, src: ownSrc,
                             nick: getEffectiveNick(), text: text,
                             ts: Int64(Date().timeIntervalSince1970 * 1000))
        _recordMessage(msg, local: true)
        return mid
    }

    @discardableResult
    public func sendPing(room: String? = nil) throws -> Data {
        let body = Data((0..<8).map { _ in UInt8.random(in: 0...255) })
        let ownSrc = manager?.identity?.hash ?? Data()
        var pairs = _makeBasePairs(type: RRC.MessageType.ping, src: ownSrc)
        pairs.append((.uint(UInt64(RRC.Key.body)), .bytes(body)))
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        _lock.withLock {
            _pendingPings[body] = (now, room)
            let cutoff = now - 15_000
            _pendingPings = _pendingPings.filter { $0.value.0 > cutoff }
        }
        try _sendEnv(pairs)
        return body
    }

    public func sendCommand(text: String, room: String? = nil) throws {
        guard text.hasPrefix("/") else { throw RRCHubError.commandMustStartWithSlash }
        let ownSrc = manager?.identity?.hash ?? Data()
        var pairs = _makeBasePairs(type: RRC.MessageType.msg, src: ownSrc, room: room)
        pairs.append((.uint(UInt64(RRC.Key.body)), .text(text)))
        if let nick = getEffectiveNick() {
            pairs.append((.uint(UInt64(RRC.Key.nick)), .text(nick)))
        }
        try _sendEnv(pairs)
    }

    // MARK: - Packet handler

    /// Called when a packet arrives on the link (or directly from tests).
    public func _onPacket(_ data: Data) {
        guard let value = try? CBOR.decode(data), case .map(let rawPairs) = value else { return }
        var env: [Int: CBOR.Value] = [:]
        for (k, v) in rawPairs { if case .uint(let u) = k { env[Int(u)] = v } }
        guard let typeVal = env[RRC.Key.type], case .uint(let tRaw) = typeVal else { return }
        let t = Int(tRaw)

        switch t {
        case RRC.MessageType.ping:   _handlePing(env: env)
        case RRC.MessageType.pong:   _handlePong(env: env)
        case RRC.MessageType.welcome: _handleWelcome(env: env)
        case RRC.MessageType.joined: _handleJoined(env: env)
        case RRC.MessageType.parted: _handleParted(env: env)
        case RRC.MessageType.msg:    _handleMsg(env: env, kind: "msg", msgType: t)
        case RRC.MessageType.action: _handleMsg(env: env, kind: "action", msgType: t)
        case RRC.MessageType.notice: _handleNotice(env: env)
        case RRC.MessageType.error:  _handleError(env: env)
        case RRC.MessageType.resourceEnvelope: _handleResourceEnvelope(env: env)
        default: break
        }
    }

    // MARK: - Private packet handlers

    private func _handlePing(env: [Int: CBOR.Value]) {
        guard let mgr = manager, let src = mgr.identity?.hash else { return }
        var pongPairs = _makeBasePairs(type: RRC.MessageType.pong, src: src)
        if let bodyVal = env[RRC.Key.body] {
            pongPairs.append((.uint(UInt64(RRC.Key.body)), bodyVal))
        }
        try? _sendEnv(pongPairs)
    }

    private func _handlePong(env: [Int: CBOR.Value]) {
        guard case .bytes(let body) = env[RRC.Key.body] else { return }
        let (sentMs, room) = _lock.withLock { () -> (Int64?, String?) in
            let pending = _pendingPings.removeValue(forKey: body)
            return (pending?.0, pending?.1)
        }
        guard let sent = sentMs else { return }
        let rtt = max(0, Int64(Date().timeIntervalSince1970 * 1000) - sent)
        if let r = room { _recordSystem(room: r, text: "Pong from hub: \(rtt) ms") }
    }

    private func _handleWelcome(env: [Int: CBOR.Value]) {
        _lock.withLock { welcomed = true }
        if case .map(let bodyPairs) = env[RRC.Key.body] {
            var body: [Int: CBOR.Value] = [:]
            for (k, v) in bodyPairs { if case .uint(let u) = k { body[Int(u)] = v } }
            // Assign the hub metadata/limits under the lock — they are readable
            // from other threads (UI). Building the local caps/lims dicts inside
            // the lock is fine (no callouts).
            _lock.withLock {
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
        _lock.withLock { _reconnectAttempts = 0 }
        _setStatus(.connected, text: "Connected")
        manager?._onWelcome(hub: self)
        if autoList {
            _lock.withLock { _silentListPending += 1 }
            try? sendCommand(text: "/list")
        }
    }

    private func _handleJoined(env: [Int: CBOR.Value]) {
        guard case .text(let rawRoom) = env[RRC.Key.room] else { return }
        let r = rawRoom.trimmingCharacters(in: .whitespaces).lowercased()
        guard !r.isEmpty else { return }

        var memberHashes: [Data] = []
        if case .array(let items) = env[RRC.Key.body] {
            memberHashes = items.compactMap { if case .bytes(let b) = $0 { return b } else { return nil } }
        }
        let joinerNick: String? = { if case .text(let n) = env[RRC.Key.nick] { return n } else { return nil } }()
        let ownHash = manager?.identity?.hash

        let (selfJoin, silent) = _lock.withLock { () -> (Bool, Bool) in
            let sj = _pendingJoins.contains(r)
            let sl = _silentJoins.contains(r)
            if sj { _pendingJoins.remove(r) }
            if sl { _silentJoins.remove(r) }
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
            if !silent { _recordSystem(room: r, text: "You joined #\(r)") }
            if autoWho {
                _lock.withLock { _silentWhoRooms.insert(r) }
                try? sendCommand(text: "/who \(r)", room: r)
            }
            manager?.save()
        } else {
            if let joiner = memberHashes.first, ownHash == nil || joiner != ownHash {
                _recordSystem(room: r, text: "\(displayNameFor(joiner)) joined")
            }
        }
        manager?._notifyChange(self)
    }

    private func _handleParted(env: [Int: CBOR.Value]) {
        guard case .text(let rawRoom) = env[RRC.Key.room] else { return }
        let r = rawRoom.trimmingCharacters(in: .whitespaces).lowercased()
        guard !r.isEmpty else { return }

        var memberHashes: [Data] = []
        if case .array(let items) = env[RRC.Key.body] {
            memberHashes = items.compactMap { if case .bytes(let b) = $0 { return b } else { return nil } }
        }
        let parterNick: String? = { if case .text(let n) = env[RRC.Key.nick] { return n } else { return nil } }()
        let ownHash = manager?.identity?.hash

        let selfPart = _lock.withLock { () -> Bool in
            let sp = _pendingParts.contains(r)
            if sp { _pendingParts.remove(r) }
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
                _recordSystem(room: r, text: "\(displayNameFor(parter)) left")
            }
        }
        manager?._notifyChange(self)
    }

    private func _handleMsg(env: [Int: CBOR.Value], kind: String, msgType: Int) {
        guard case .text(let body) = env[RRC.Key.body] else { return }
        let rawRoom: String? = { if case .text(let r) = env[RRC.Key.room] { return r } else { return nil } }()
        let src: Data? = { if case .bytes(let b) = env[RRC.Key.src] { return b } else { return nil } }()
        let nick: String? = { if case .text(let n) = env[RRC.Key.nick] { return n } else { return nil } }()
        let mid: Data? = { if case .bytes(let b) = env[RRC.Key.id] { return b } else { return nil } }()
        let ownHash = manager?.identity?.hash

        // Deduplicate own echoes
        if let s = src, let own = ownHash, s == own {
            if let m = mid, _lock.withLock({ _sentIDs.contains(m) }) { return }
        }

        // Learn nick
        if let s = src, let n = nick, !n.isEmpty {
            _lock.withLock {
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
            msg.mention = _mentionDetected(ownNick: ownNick, in: body)
        }

        _recordMessage(msg)
    }

    /// Parse hub service notices (`/list` and `/who` replies) regardless of whether
    /// they arrived as a packet or a resource transfer. Returns `true` when the notice
    /// was consumed silently (an auto `/list` or `/who`) and should not be recorded to
    /// the message log. Mirrors Python `RRCHub._process_notice_text` (commit f07a035).
    private func _processNoticeText(_ body: String) -> Bool {
        // Detect /list response
        if let parsed = RRCHub.parseRoomListNotice(body) {
            let silent: Bool = _lock.withLock {
                availableRooms = parsed
                let s = _silentListPending > 0
                if s { _silentListPending -= 1 }
                return s
            }
            manager?._notifyChange(self)
            if silent { return true }
        }

        // Detect /who response
        if let (whoRoom, entries) = RRCHub.parseWhoNotice(body) {
            let silentWho: Bool = _lock.withLock {
                var mset = members[whoRoom] ?? []
                for (nick, hexStr) in entries {
                    guard let hBytes = _rrcHexData(hexStr) else { continue }
                    if nick == nil {
                        mset.insert(hBytes)
                    } else {
                        for ph in mset {
                            if ph.hex.hasPrefix(hexStr) { nicks[ph] = nick; break }
                        }
                    }
                }
                members[whoRoom] = mset
                let s = _silentWhoRooms.contains(whoRoom)
                if s { _silentWhoRooms.remove(whoRoom) }
                return s
            }
            manager?._notifyChange(self)
            if silentWho { return true }
        }

        return false
    }

    private func _handleNotice(env: [Int: CBOR.Value]) {
        guard case .text(let body) = env[RRC.Key.body] else { return }
        let src: Data? = { if case .bytes(let b) = env[RRC.Key.src] { return b } else { return nil } }()
        let rawRoom: String? = { if case .text(let r) = env[RRC.Key.room] { return r } else { return nil } }()

        // Parse /list and /who service notices; a silently-consumed auto reply is
        // not recorded to the log.
        if _processNoticeText(body) { return }

        // MOTD: a notice with no room
        let room = rawRoom?.trimmingCharacters(in: .whitespaces).lowercased()
        if room == nil {
            _lock.withLock { motd = body }
            manager?._notifyChange(self)
        }

        let msg = RRCMessage(kind: "notice", room: room, src: src, nick: nil, text: body,
                             ts: Int64(Date().timeIntervalSince1970 * 1000))
        _recordNotice(msg)
    }

    private func _handleError(env: [Int: CBOR.Value]) {
        let text: String
        if case .text(let b) = env[RRC.Key.body] { text = b } else { text = "(error)" }
        let rawRoom: String? = { if case .text(let r) = env[RRC.Key.room] { return r } else { return nil } }()
        let r = rawRoom?.trimmingCharacters(in: .whitespaces).lowercased()

        var rollbackJoin = false
        if let rm = r {
            _lock.withLock {
                rollbackJoin = _pendingJoins.contains(rm)
                _pendingJoins.remove(rm)
                _silentJoins.remove(rm)
                _pendingParts.remove(rm)
                if rollbackJoin { rooms.remove(rm) }
            }
            if rollbackJoin { manager?.save() }
        }
        let msg = RRCMessage(kind: "error", room: r, src: nil, nick: nil, text: text,
                             ts: Int64(Date().timeIntervalSince1970 * 1000))
        _recordNotice(msg)
    }

    private func _handleResourceEnvelope(env: [Int: CBOR.Value]) {
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
        _lock.withLock {
            // Sweep expired expectations on insert too (not only in
            // _resourceConcluded) — a peer sending envelopes that never conclude
            // would otherwise grow this dictionary without bound.
            let now = Date()
            for (k, v) in _resourceExpectations where v.expires < now { _resourceExpectations[k] = nil }
            _resourceExpectations[rid] = ResourceExpectation(kind: kind, size: size, sha256: sha256,
                                                              encoding: encoding, room: room,
                                                              expires: Date().addingTimeInterval(30))
        }
    }

    /// Accept/reject an inbound hub resource advertisement by size.
    /// Mirrors Python `RRCHub._resource_advertised` (commit 510d476): reject when the
    /// advertised data size exceeds the configured cap, or the cap is disabled (<= 0).
    internal func _resourceAdvertised(size: Int) -> Bool {
        let maxSize = manager?.maxAcceptedResourceSize ?? RRCHub.defaultMaxAcceptedResourceSize
        if maxSize <= 0 || size > maxSize { return false }
        return true
    }

    /// Handle a concluded hub→client resource transfer. Matches the assembled payload
    /// to a previously-advertised `ResourceExpectation` (by exact size), verifies the
    /// optional sha256, decodes the text, and routes MOTD / `/who` / `/list` notices
    /// through the same parser as the packet path. Mirrors Python
    /// `RRCHub._resource_concluded` (commit f07a035).
    internal func _resourceConcluded(payload: Data) {
        let now = Date()
        let matched: ResourceExpectation? = _lock.withLock {
            // Drop expired expectations, then match on exact assembled size.
            for (k, v) in _resourceExpectations where v.expires < now { _resourceExpectations[k] = nil }
            for (k, exp) in _resourceExpectations where exp.size == payload.count {
                _resourceExpectations[k] = nil
                return exp
            }
            return nil
        }

        let kind = matched?.kind ?? RRC.ResKind.blob
        let room = matched?.room

        // Verify the optional integrity hash before trusting the payload.
        if let sha = matched?.sha256, Data(SHA256.hash(data: payload)) != sha { return }

        // Only notice/MOTD payloads carry text we act on; blobs are ignored.
        guard kind == RRC.ResKind.notice || kind == RRC.ResKind.motd else { return }

        // Decode as UTF-8 (lossy — mirrors Python decode(errors="replace")). Resource
        // envelopes use utf-8; unknown encodings fall back to the same lossy decode.
        let text = String(decoding: payload, as: UTF8.self)

        if kind == RRC.ResKind.motd {
            _lock.withLock { motd = text }
            manager?._notifyChange(self)
        } else if _processNoticeText(text) {
            return
        }

        let msg = RRCMessage(kind: "notice", room: room, src: nil, nick: nil, text: text,
                             ts: Int64(Date().timeIntervalSince1970 * 1000))
        _recordNotice(msg)
    }

    // MARK: - Message recording

    internal func _recordMessage(_ msg: RRCMessage, local: Bool = false) {
        let room = msg.room ?? "*"
        let cap = _perRoomCap()
        _lock.withLock {
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
        // onMessageCallback, which may re-enter the hub — non-recursive lock).
        manager?._notifyMessages(hub: self, msg: msg)
        _appendHistory(room: room, msg: msg)
        _cleanHistory()
    }

    internal func _recordSystem(room: String, text: String) {
        let msg = RRCMessage(kind: "system", room: room, src: nil, nick: nil, text: text,
                             ts: Int64(Date().timeIntervalSince1970 * 1000))
        let cap = _perRoomCap()
        _lock.withLock {
            var buf = messages[room] ?? []
            buf.append(msg)
            if let cap, buf.count > cap { buf.removeFirst(buf.count - cap) }
            messages[room] = buf
        }
        manager?._notifyMessages(hub: self, msg: msg)   // outside the lock (see _recordMessage)
        _appendHistory(room: room, msg: msg)
        _cleanHistory()
    }

    internal func _recordNotice(_ msg: RRCMessage) {
        var target = msg.room
        if target == nil { target = manager?.activeRoomFor(hub: self) }
        let cap = _perRoomCap()
        _lock.withLock {
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
        manager?._notifyMessages(hub: self, msg: msg)   // outside the lock (see _recordMessage)
        if let r = target {
            _appendHistory(room: r, msg: msg)
            _cleanHistory()
        }
    }

    // MARK: - History persistence

    internal func _entryFor(_ msg: RRCMessage) -> [String: CBOR.Value] {
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

    public static func _msgFromEntry(room: String, entry: [String: CBOR.Value]) -> RRCMessage? {
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

    public static func _persistableRoom(_ room: String) -> Bool {
        !room.isEmpty && room != "*"
    }

    internal func _appendHistory(room: String, msg: RRCMessage) {
        guard RRCHub._persistableRoom(room), let mgr = manager else { return }
        let pairs = _entryFor(msg).map { (CBOR.Value.text($0.key), $0.value) }
        let data  = CBOR.encode(.map(pairs))
        // Serialize disk writes under _historyIOLock. On non-POSIX platforms
        // O_APPEND writes are not guaranteed atomic; the lock prevents interleaved
        // records from different concurrent callers.
        // Mirrors Python RRCHub._history_io_lock added in NomadNet RRC.py.
        _historyIOLock.withLock {
            do {
                let dir = mgr._historyDir(hub: self)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let path = mgr._historyPath(hub: self, room: room)
                if let handle = FileHandle(forWritingAtPath: path.path) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                } else {
                    FileManager.default.createFile(atPath: path.path, contents: data)
                }
                _historyWriteFailed = false
            } catch {
                if !_historyWriteFailed {
                    _historyWriteFailed = true
                }
            }
        }
    }

    internal func _deleteHistory(room: String) {
        guard RRCHub._persistableRoom(room), let mgr = manager else { return }
        let path = mgr._historyPath(hub: self, room: room)
        try? FileManager.default.removeItem(at: path)
    }

    internal func _loadHistory() {
        let doFilter = _filterHistory()
        let cap      = _perRoomCap()
        let roomList = _lock.withLock { Array(messages.keys) }
        for room in roomList {
            guard RRCHub._persistableRoom(room), let mgr = manager else { continue }
            let path = mgr._historyPath(hub: self, room: room)
            guard let data = try? Data(contentsOf: path), !data.isEmpty else { continue }
            guard let items = try? CBOR.decodeAll(data) else { continue }
            var msgs: [RRCMessage] = []
            for item in items {
                guard case .map(let pairs) = item else { continue }
                var entry: [String: CBOR.Value] = [:]
                for (k, v) in pairs { if case .text(let s) = k { entry[s] = v } }
                guard let m = RRCHub._msgFromEntry(room: room, entry: entry) else { continue }
                // Filter ephemeral messages when enabled (matches Python _filter_history)
                if doFilter && (m.kind == "system" || m.kind == "notice") { continue }
                msgs.append(m)
            }
            // Apply per-room cap: keep the most recent `cap` messages
            if let cap, msgs.count > cap { msgs = Array(msgs.suffix(cap)) }
            _lock.withLock { messages[room] = msgs }
        }
    }

    // MARK: - Notice parsing helpers (static, testable)

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

    private func _makeBasePairs(type: Int, src: Data, room: String? = nil,
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

    private func _mentionDetected(ownNick: String, in text: String) -> Bool {
        guard !ownNick.isEmpty else { return false }
        let escaped = NSRegularExpression.escapedPattern(for: ownNick)
        let pattern = "(?<![A-Za-z0-9_])@\(escaped)(?![A-Za-z0-9_])"
        let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        return re?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    internal func _setStatus(_ status: Status, text: String? = nil) {
        _lock.withLock {
            self.status = status
            if let t = text { statusText = t }
        }
        manager?._notifyChange(self)   // outside the lock (may re-enter the hub)
    }

    // MARK: - History behaviour helpers (Phase 22)

    /// Maximum in-memory messages per room (nil = no cap).
    /// Reads from `manager._rrcHistoryPerRoomCap`.
    internal func _perRoomCap() -> Int? {
        guard let v = manager?._rrcHistoryPerRoomCap, v > 0 else { return nil }
        return v
    }

    /// Whether system/notice messages should be skipped when loading history from disk.
    /// Defaults to true (matches Python `rrc_filter_loaded_history`).
    internal func _filterHistory() -> Bool {
        manager?._rrcFilterLoadedHistory ?? true
    }

    /// Seconds after which a system/notice message is pruned by `_cleanHistory`.
    internal func _ephemeralNoticesTimeout() -> TimeInterval {
        manager?._rrcEphemeralNoticesTimeout ?? RRCHub.sysNoticeTimeout
    }

    /// Sweep the in-memory message buffers, removing old ephemeral (system/notice) messages.
    /// Rate-limited to at most once per `cleanHistoryInterval` seconds.
    /// Matches Python `RRCHub._clean_history`.
    internal func _cleanHistory() {
        let now = Date()
        let removeAfter = _ephemeralNoticesTimeout()
        // Do the rate-limit check, the sweep, and the timestamp updates all under
        // the lock so `_lastHistoryClean`/`cleanLastRemoved` don't race concurrent
        // record calls from the UI and link threads.
        _lock.withLock {
            guard now.timeIntervalSince(_lastHistoryClean) > RRCHub.cleanHistoryInterval else { return }
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
            _lastHistoryClean = now
            if didClean { cleanLastRemoved = now }
        }
    }

    // MARK: - Test helpers (accessible via @testable import)

    /// Directly insert a message into the in-memory buffer without side effects (for tests).
    internal func _testInjectMessage(room: String, msg: RRCMessage) {
        _lock.withLock { messages[room, default: []].append(msg) }
    }

    /// Reset the history-clean cooldown so the next `_cleanHistory()` call runs immediately.
    internal func _testResetHistoryClean() {
        _lastHistoryClean = .distantPast
    }
}

// MARK: - RRCManager

/// Manages a list of RRC hub connections and persists their configuration.
/// Corresponds to Python `RRCManager` in `nomadnet/RRC.py`.
public final class RRCManager {

    // MARK: Public state

    public private(set) var hubs: [RRCHub] = []
    public var onChangeCallback:  ((RRCHub?) -> Void)?
    public var onMessageCallback: ((RRCHub, RRCMessage) -> Void)?

    /// Maximum size, in bytes, of a hub→client resource transfer this client will
    /// accept. Larger advertisements are rejected; `<= 0` disables all resource
    /// acceptance. Mirrors Python `rrc_max_accepted_resource_size` (default 256 KiB).
    public var maxAcceptedResourceSize: Int = RRCHub.defaultMaxAcceptedResourceSize

    // Optional production app protocol — provides identity + storage
    public weak var app: NomadNetworkAppProtocol?

    // Direct identity / storage for test-mode construction (override app)
    private var _identityOverride:  Identity?
    private var _storageOverride:   URL?
    private var _nicknameOverride:  String?

    // Test-friendly overrides for history behavior (bypass app protocol)
    internal var _rrcHistoryPerRoomCapOverride:       Int?          = nil
    internal var _rrcFilterLoadedHistoryOverride:     Bool?         = nil
    internal var _rrcEphemeralNoticesTimeoutOverride: TimeInterval? = nil

    internal var _rrcHistoryPerRoomCap: Int? {
        _rrcHistoryPerRoomCapOverride ?? app?.rrcHistoryPerRoomCap
    }
    internal var _rrcFilterLoadedHistory: Bool {
        _rrcFilterLoadedHistoryOverride ?? app?.rrcFilterLoadedHistory ?? true
    }
    internal var _rrcEphemeralNoticesTimeout: TimeInterval {
        _rrcEphemeralNoticesTimeoutOverride ?? app?.rrcEphemeralNoticesTimeout ?? 600.0
    }

    private let _lock     = NSLock()
    private let _saveLock = NSLock()
    private var _loaded   = false
    private var _loading  = false
    private var _activeHub:  RRCHub? = nil
    private var _activeRoom: String? = nil

    // MARK: Internal (tests share hub lists for path resolution)
    internal var _hubs: [RRCHub] {
        get { _lock.withLock { hubs } }
        set { _lock.withLock { hubs = newValue } }
    }

    // MARK: Init

    /// Production init — supply an app conforming to `NomadNetworkAppProtocol`.
    public init(app: NomadNetworkAppProtocol? = nil) {
        self.app = app
    }

    /// Test-friendly init — supply identity / storagePath / nickname directly.
    public convenience init(identity: Identity, storagePath: URL? = nil, nickname: String? = nil) {
        self.init(app: nil)
        _identityOverride = identity
        _storageOverride  = storagePath
        _nicknameOverride = nickname
    }

    // MARK: Identity / storage / nick

    public var identity: Identity? {
        _identityOverride ?? app?.identity
    }

    public var storagePath: URL? {
        _storageOverride ?? app?.storagePath
    }

    public func getNickname() -> String? {
        _nicknameOverride ?? app?.peerDisplayName
    }

    // MARK: Hub management

    @discardableResult
    public func addHub(hash: Data, destName: String? = nil, name: String? = nil) -> RRCHub {
        let dn = destName ?? RRC.defaultDestName
        if let existing = _lock.withLock({ hubs.first(where: { $0.hubHash == hash && $0.destName == dn }) }) {
            return existing
        }
        let hub = RRCHub(manager: self, hubHash: hash, destName: destName, name: name)
        _lock.withLock { hubs.append(hub) }
        if !_loading { save() }
        _notifyChange(nil)
        return hub
    }

    public func removeHub(_ hub: RRCHub) {
        hub.manager = nil   // break retain cycle before release
        _lock.withLock { hubs.removeAll { $0 === hub } }
        hub.disconnect()
        save()
        _notifyChange(nil)
    }

    public func findHub(hash: Data, destName: String? = nil) -> RRCHub? {
        let dn = destName ?? RRC.defaultDestName
        return _lock.withLock { hubs.first { $0.hubHash == hash && $0.destName == dn } }
    }

    // MARK: Active room / unread

    public var hasUnread: Bool {
        _lock.withLock { hubs.contains { !$0.unreadRooms.isEmpty } }
    }

    public func setActive(hub: RRCHub, room: String?) {
        // _activeHub/_activeRoom are read by activeRoomFor from other threads.
        _lock.withLock { _activeHub = hub; _activeRoom = room }
        if let r = room { hub.markRead(r) }   // outside the lock (takes the hub's lock)
    }

    public func activeRoomFor(hub: RRCHub) -> String? {
        _lock.withLock { _activeHub === hub ? _activeRoom : nil }
    }

    // MARK: Callbacks

    internal func _notifyChange(_ hub: RRCHub?) {
        onChangeCallback?(hub)
    }

    internal func _notifyMessages(hub: RRCHub, msg: RRCMessage) {
        onMessageCallback?(hub, msg)
    }

    /// Called when a hub receives T_WELCOME: re-join all remembered rooms.
    internal func _onWelcome(hub: RRCHub) {
        // Snapshot the rooms Set under the hub's lock (packet handlers mutate it).
        for r in hub.snapshotRooms() {
            try? hub.joinRoom(r, silent: true)
        }
    }

    // MARK: Shutdown

    public func shutdown() {
        // Break the RRCHub -> manager strong reference too (as removeHub does),
        // so tearing down a manager without removing hubs first doesn't leak.
        _lock.withLock { hubs }.forEach { $0.disconnect(); $0.manager = nil }
    }

    // MARK: Persistence (CBOR, matches Python's save/load format)

    internal func _storePath() -> URL? {
        storagePath?.appendingPathComponent("rrc_hubs")
    }

    internal func _historyRoot() -> URL? {
        storagePath?.appendingPathComponent("rrc_history")
    }

    internal func _historyDir(hub: RRCHub) -> URL {
        let root = _historyRoot() ?? URL(fileURLWithPath: NSTemporaryDirectory())
        var key = hub.hubHash.hex
        if hub.destName != RRC.defaultDestName {
            let suffix = SHA256.hash(data: Data(hub.destName.utf8))
                .prefix(4).map { String(format: "%02x", $0) }.joined()
            key = key + "__" + suffix
        }
        return root.appendingPathComponent(key)
    }

    internal func _historyPath(hub: RRCHub, room: String) -> URL {
        let dir = _historyDir(hub: hub)
        let sanitized = String(room.replacingOccurrences(of: "[^a-z0-9._-]",
            with: "_", options: .regularExpression).prefix(64))
        let roomHash = SHA256.hash(data: Data(room.utf8))
            .prefix(4).map { String(format: "%02x", $0) }.joined()
        let filename = sanitized.isEmpty ? "\(roomHash).log" : "\(sanitized)_\(roomHash).log"
        return dir.appendingPathComponent(filename)
    }

    public func save() {
        guard !_loading else { return }
        guard let path = _storePath() else { return }
        let tmpPath = path.appendingPathExtension("tmp")
        _saveLock.lock(); defer { _saveLock.unlock() }
        let hubList = _lock.withLock { hubs }
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
            entries.append((.text(""), .map(e)))  // key ignored — we store as array item
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

    public func load() {
        guard !_loaded, let path = _storePath() else { return }
        guard FileManager.default.fileExists(atPath: path.path) else { _loaded = true; return }
        _loaded   = true
        _loading  = true
        defer { _loading = false }
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
                hub._loadHistory()
            }
        } catch {}
    }
}

// MARK: - NomadNetworkAppProtocol

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

    /// Seconds after which a loaded system/notice message is removed by `_cleanHistory`.
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

private func _rrcHexData(_ hex: String) -> Data? {
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
