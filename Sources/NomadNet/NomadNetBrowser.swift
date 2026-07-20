import Foundation
import ReticulumSwift

// MARK: - PageRequest

/// A pending or completed NomadNet page request.
///
/// Carries the target URL, any form field values, and the wall-clock
/// time at which the request was created — matching the Python browser's
/// tracking of `destination_hash`, `path`, and `request_data`.
public struct PageRequest: Sendable {

    /// The URL being requested.
    public let url: NomadNetURL

    /// Form field values keyed by field name (without the `field_` prefix).
    /// When sent over RNS the keys are prefixed with `field_` in the msgpack map.
    public let fields: [String: String]

    /// Wall-clock time the request was created.
    public let timestamp: Date

    public init(url: NomadNetURL, fields: [String: String] = [:], timestamp: Date = Date()) {
        self.url = url
        self.fields = fields
        self.timestamp = timestamp
    }
}

// MARK: - NomadNetBrowser

/// Manages NomadNet page navigation over RNS Links.
///
/// # Protocol summary (from Python Browser.py)
///
/// 1. Parse URL: `<20-hex-dest-hash>:<path>`
/// 2. Check RNS transport has a path to the destination.
/// 3. Establish an `RNS.Link` to the destination.
/// 4. Call `link.request(path, data: encodedFields)`.
/// 5. Receive response bytes → decode UTF-8 → parse with `MicronParser`.
/// 6. Push URL onto history.
///
/// The transport-level I/O (`Link`, `Transport`) is injected via the
/// `navigateAsync` callback so that unit tests can exercise all the
/// non-network logic without hardware.
open class NomadNetBrowser: @unchecked Sendable {

    // MARK: - Constants

    /// Default request path on a NomadNet node. Mirrors `Browser.DEFAULT_PATH`.
    public static let defaultPath: String = NomadNetURL.defaultPath

    /// Default request timeout in seconds. Mirrors `Browser.DEFAULT_TIMEOUT = 10`.
    public static let defaultTimeout: TimeInterval = 10

    // MARK: - Properties

    /// Navigation history.
    public let history: PageHistory

    /// Timeout for link establishment and page response (seconds).
    public var timeout: TimeInterval

    /// Called when a page has been successfully loaded and parsed.
    /// Parameters: parsed Micron AST, the URL that was loaded.
    public var onPageLoaded: (([MicronNode], NomadNetURL) -> Void)?

    /// Called when a request fails (link timeout, request failure, etc.).
    /// Parameters: error description, the URL that failed.
    public var onError: ((String, NomadNetURL) -> Void)?

    // MARK: - Initialiser

    /// Creates a browser with no transport attached.
    ///
    /// For production use, supply navigation by setting `onPageLoaded` and
    /// calling `navigate(to:fields:)` after providing a transport.
    /// For unit-testing, create an instance, manipulate `history` directly,
    /// and invoke `goBack()` / `goForward()` to exercise navigation logic.
    public init(timeout: TimeInterval = defaultTimeout) {
        self.history = PageHistory()
        self.timeout = timeout
    }

    // MARK: - Navigation

    /// Navigate to a NomadNet URL.
    ///
    /// - Parameters:
    ///   - url: The target page URL.
    ///   - fields: Optional form field values (keyed by field name, without prefix).
    ///
    /// This method pushes the URL onto history immediately. The actual network
    /// I/O must be driven by the caller (or a subclass) via overriding
    /// `performRequest(_:fields:)`.
    public func navigate(to url: NomadNetURL, fields: [String: String] = [:]) {
        history.push(url)
        performRequest(url, fields: fields)
    }

    /// Navigate back one entry in the history.
    public func goBack() {
        guard let url = history.back() else { return }
        performRequest(url, fields: [:])
    }

    /// Navigate forward one entry in the history.
    public func goForward() {
        guard let url = history.forward() else { return }
        performRequest(url, fields: [:])
    }

    /// Reload the current page (removes from cache in the Python implementation).
    public func reload() {
        guard let url = history.current else { return }
        performRequest(url, fields: [:])
    }

    // MARK: - Request dispatch (override point)

    /// Perform the actual page request.
    ///
    /// The base implementation does nothing — it is an override point for
    /// production subclasses that wire in real `Link` + `Transport`.
    /// Unit tests exercise all surrounding logic without overriding this.
    ///
    /// URL variables (the `` `a=1|b=2 `` link-target tail) travel on `url`;
    /// combine them with the form `fields` when building the request body.
    open func performRequest(_ url: NomadNetURL, fields: [String: String]) {
        // No-op in the base class. Production subclasses call:
        //   let data = NomadNetBrowser.encode(fields: fields, variables: url.variables)
        //   link.request(path: url.path, data: data, responseCallback: …)
    }

    // MARK: - Response handling

    /// Process raw response bytes received from a `link.request()` call.
    ///
    /// - Parameters:
    ///   - data: Raw bytes from the RNS resource response.
    ///   - url:  The URL that was requested.
    ///
    /// If the data is valid UTF-8 page content it is parsed with `MicronParser`
    /// and `onPageLoaded` is called. Otherwise `onError` is called.
    public func handleResponse(_ data: Data, url: NomadNetURL) {
        guard Self.isPageContent(data: data) else {
            onError?("Response is binary (not a Micron page)", url)
            return
        }
        let markup = String(data: data, encoding: .utf8) ?? ""
        let nodes = MicronParser.parse(markup)
        onPageLoaded?(nodes, url)
    }

    // MARK: - Static utilities

    /// Encode form fields and URL variables into the msgpack format expected by
    /// a NomadNet node.
    ///
    /// The Python browser sends a `dict` (its `request_data`) with keys prefixed:
    /// - `field_<name>` — for widget/form field values
    /// - `var_<name>`   — for URL variable substitutions (the `` `a=1|b=2 `` tail)
    ///
    /// Keys are emitted in a deterministic order (fields then variables, each
    /// sorted by name). Pass two empty maps to get `nil` back (signals "no
    /// request body").
    ///
    /// - Returns: msgpack-encoded `Data`, or `nil` if both maps are empty.
    public static func encode(fields: [String: String], variables: [String: String]) -> Data? {
        guard !fields.isEmpty || !variables.isEmpty else { return nil }

        var pairs: [(MsgPack.Value, MsgPack.Value)] = []
        for (key, value) in fields.sorted(by: { $0.key < $1.key }) {
            pairs.append((.string("field_\(key)"), .string(value)))
        }
        for (key, value) in variables.sorted(by: { $0.key < $1.key }) {
            pairs.append((.string("var_\(key)"), .string(value)))
        }
        return MsgPack.encode(.map(pairs))
    }

    /// Encode form fields only (no URL variables) into the node's msgpack format.
    ///
    /// Convenience over ``encode(fields:variables:)`` for the common form-only
    /// path. Pass `[:]` to get `nil` back (signals "no request body").
    ///
    /// - Returns: msgpack-encoded `Data`, or `nil` if `fields` is empty.
    public static func encodeFields(_ fields: [String: String]) -> Data? {
        return encode(fields: fields, variables: [:])
    }

    /// Build the request data as an INLINE msgpack map (`field_*`/`var_*` → value),
    /// for submission via `Link.request(path:, nativeValue:)`.
    ///
    /// This is the **correct** way to submit form fields / URL variables to a
    /// NomadNet node. `Link.request` packs the request as
    /// `msgpack([timestamp, pathHash, data])`, embedding `nativeValue` *inline* —
    /// so a Python node (the reference `Node.py`) reads it as a `dict` and processes
    /// the `field_*`/`var_*` keys.
    ///
    /// Do NOT use ``encode(fields:variables:)`` + `Link.request(path:, data:)` for
    /// this: `encode` returns *already-msgpacked* `Data`, and the `data:` overload
    /// re-wraps it as a msgpack `.bytes` value — double-packing it, so a Python node
    /// sees `bytes` instead of a `dict` and silently drops every field. (See
    /// swift_devel/bugs/008.) The `encode`/`encodeFields` `Data` APIs are retained
    /// only for callers talking to a custom host that expects a pre-packed blob.
    ///
    /// Keys are emitted deterministically (fields then variables, each sorted).
    ///
    /// - Returns: a `.map` `MsgPack.Value`, or `nil` if both maps are empty
    ///   (signalling "no request body" — pass `.nil` / omit data for a plain GET).
    public static func encodeValue(fields: [String: String],
                                   variables: [String: String]) -> MsgPack.Value? {
        guard !fields.isEmpty || !variables.isEmpty else { return nil }

        var pairs: [(MsgPack.Value, MsgPack.Value)] = []
        for (key, value) in fields.sorted(by: { $0.key < $1.key }) {
            pairs.append((.string("field_\(key)"), .string(value)))
        }
        for (key, value) in variables.sorted(by: { $0.key < $1.key }) {
            pairs.append((.string("var_\(key)"), .string(value)))
        }
        return .map(pairs)
    }

    /// Detect whether response bytes are page content (valid UTF-8 / Micron)
    /// rather than raw binary (file download, image, etc.).
    ///
    /// The Python browser simply calls `.decode("utf-8")` on the response
    /// and renders it; if decoding fails it falls through to file handling.
    /// We mirror that: valid UTF-8 → page content; invalid → binary.
    ///
    /// - Parameter data: Raw response bytes.
    /// - Returns: `true` if the data appears to be UTF-8 page content.
    public static func isPageContent(data: Data) -> Bool {
        if data.isEmpty { return true }
        return String(data: data, encoding: .utf8) != nil
    }
}
