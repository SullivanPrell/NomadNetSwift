import Foundation

/// A parsed NomadNet URL.
///
/// # Format (mirroring Python Browser.parse_url / retrieve_url)
///
/// ```
/// <32-hex-char destination hash>:<path>
/// ```
///
/// Examples:
/// - `abc123def456789012abcdef01234567:/page/index.mu`
/// - `abc123def456789012abcdef01234567:`  → path defaults to `/page/index.mu`
/// - `abc123def456789012abcdef01234567`   → path defaults to `/page/index.mu`
///
/// The destination hash is always 16 bytes (= 32 hex characters), matching
/// `RNS.Reticulum.TRUNCATED_HASHLENGTH // 8 = 128 // 8 = 16` in the Python reference.
///
/// Colon (`:`) is the separator used by the Python browser. The path
/// component is everything after the first colon.
public struct NomadNetURL: Equatable, Sendable {

    // MARK: - Constants

    /// Number of bytes in a truncated RNS destination hash.
    /// Python: `RNS.Reticulum.TRUNCATED_HASHLENGTH // 8 = 128 // 8 = 16`.
    public static let hashByteLength: Int = 16

    /// Number of hex characters encoding the 10-byte hash (2 chars per byte).
    public static let hashHexLength: Int = hashByteLength * 2

    /// Default page path served by a NomadNet node.
    public static let defaultPath: String = "/page/index.mu"

    // MARK: - Stored properties

    /// The 10-byte truncated destination hash.
    public let destinationHash: Data

    /// The request path, always non-empty (defaults to `defaultPath`).
    public let path: String

    /// URL variables parsed from the `` `name=value|… `` tail of a link target.
    ///
    /// Keyed by variable name without the `var_` prefix. When sent over RNS the
    /// keys are prefixed with `var_` in the msgpack request map — mirroring
    /// Python's `request_data["var_<name>"]` (Browser.retrieve_url / handle_link).
    public let variables: [String: String]

    // MARK: - Initialiser (internal)

    init(destinationHash: Data, path: String, variables: [String: String] = [:]) {
        self.destinationHash = destinationHash
        self.path = path
        self.variables = variables
    }

    // MARK: - Parsing

    /// Parse a NomadNet URL string.
    ///
    /// Accepted forms:
    /// - `<20hex>`                     — destination hash only; path defaults to `/page/index.mu`
    /// - `<20hex>:`                    — empty path; defaults to `/page/index.mu`
    /// - `<20hex>:<path>`              — fully specified URL
    ///
    /// Returns `nil` for any malformed input (wrong hash length, non-hex
    /// characters, etc.).
    public static func parse(_ urlString: String) -> NomadNetURL? {
        guard !urlString.isEmpty else { return nil }

        // Split off any inline variables appended after a backtick
        // e.g.  "abc...:/page/index.mu`name=alice|city=NYC"
        // The portion before the backtick is the destination/path; the portion
        // after is a "|"-separated list of "name=value" URL variables.
        let stripped: String
        let variables: [String: String]
        if let backtick = urlString.firstIndex(of: "`") {
            stripped = String(urlString[..<backtick])
            let tail = String(urlString[urlString.index(after: backtick)...])
            variables = parseVariables(tail)
        } else {
            stripped = urlString
            variables = [:]
        }

        let components = stripped.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)

        let hexPart: String
        let rawPath: String

        switch components.count {
        case 1:
            hexPart = String(components[0])
            rawPath = ""
        case 2:
            hexPart = String(components[0])
            rawPath = String(components[1])
        default:
            return nil
        }

        // Validate hash: must be exactly hashHexLength hex chars
        guard hexPart.count == hashHexLength else { return nil }
        guard let hashData = Data(hexString: hexPart) else { return nil }
        guard hashData.count == hashByteLength else { return nil }

        let path = rawPath.isEmpty ? defaultPath : rawPath
        return NomadNetURL(destinationHash: hashData, path: path, variables: variables)
    }

    /// Parse the `` `name=value|… `` tail of a link target into URL variables.
    ///
    /// Mirrors Python's `Browser.retrieve_url` (~line 892): the tail is split on
    /// `|`, and each segment containing exactly one `=` becomes a `name=value`
    /// pair. Segments without `=` are form-field references (handled elsewhere)
    /// and are ignored here; segments with more than one `=` are malformed and
    /// skipped (Python checks `len(c) == 2`).
    private static func parseVariables(_ tail: String) -> [String: String] {
        guard !tail.isEmpty else { return [:] }
        var variables: [String: String] = [:]
        for segment in tail.split(separator: "|", omittingEmptySubsequences: false) {
            let parts = segment.split(separator: "=", omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            variables[String(parts[0])] = String(parts[1])
        }
        return variables
    }

    // MARK: - Serialisation

    /// Returns the canonical string representation: `<20hex>:<path>`.
    ///
    /// When URL variables are present they are appended as a backtick-separated,
    /// `|`-joined `name=value` list (keys sorted for deterministic output), so
    /// that `parse(url.toString())` round-trips — matching the link-target form
    /// produced by Python's `Browser.marked_link`.
    public func toString() -> String {
        let base = destinationHash.hexString + ":" + path
        guard !variables.isEmpty else { return base }
        let tail = variables.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "|")
        return base + "`" + tail
    }
}

// MARK: - Data hex helpers

private extension Data {
    init?(hexString: String) {
        let hex = hexString
        guard hex.count % 2 == 0 else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            let byteStr = String(hex[index..<nextIndex])
            guard let byte = UInt8(byteStr, radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
