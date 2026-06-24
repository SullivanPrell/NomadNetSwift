import Foundation

// MARK: - NNNode

/// NomadNet Node server.
///
/// Serves Micron pages and binary files over RNS Links.
/// Corresponds to Python `Node` in `nomadnet/Node.py`.
///
/// ## Usage
/// 1. Create with a display name.
/// 2. Register page/file handlers via `registerPage(_:generator:)` / `registerFile(_:generator:)`.
/// 3. In production, wire to a `Destination("nomadnetwork", "node")`:
///    - Set `destination.setLinkEstablishedCallback { [weak self] link in … }`.
///    - Install `handlePageRequest` / `handleFileRequest` as request-handler generators.
/// 4. Call `announceData()` as the `app_data` when announcing.
///
/// Unit-test friendly: all request routing is exercisable without a live transport.
public class NNNode {

    // MARK: – Constants (Python: Node.JOB_INTERVAL, START_ANNOUNCE_DELAY)

    /// Background job run interval in seconds. Python: `JOB_INTERVAL = 5`.
    public static let jobInterval: TimeInterval = 5

    /// Delay before the initial startup announce, in seconds.
    /// Python: `START_ANNOUNCE_DELAY = 6`.
    public static let startAnnounceDelay: TimeInterval = 6

    /// Combined aspect string for NomadNet node destinations.
    /// Python: `Destination(identity, IN, SINGLE, "nomadnetwork", "node")`.
    public static let aspectFilter: String = "nomadnetwork.node"

    /// The default index page path requested by browsers with no explicit path.
    public static let defaultPagePath: String = "/page/index.mu"

    // MARK: – Default page Micron content

    /// Auto-generated home page served when `/page/index.mu` is not registered.
    /// Python: `DEFAULT_INDEX`.
    public static let defaultIndexPage: String = """
        >Default Home Page

        This node is serving pages, but the home page file (index.mu) was not found in the page storage directory. This is an auto-generated placeholder.

        If you are the node operator, you can define your own home page by creating a file named `*index.mu`* in the page storage directory.
        """

    /// Page returned when the requester is not in the allowed-identity list.
    /// Python: `DEFAULT_NOTALLOWED`.
    public static let defaultNotAllowedPage: String = """
        >Request Not Allowed

        You are not authorised to carry out the request.
        """

    // MARK: – Properties

    /// Display name of this node.
    /// Used as `app_data` (UTF-8 encoded) in RNS announces.
    public let name: String

    // MARK: – Callbacks

    /// Invoked when a peer link is established. Parameter is a link identifier.
    /// Python: `peer_connected(link)`.
    public var onPeerConnected: ((Data) -> Void)?

    /// Invoked when a peer link is closed. Parameter is the same link identifier.
    /// Python: `peer_disconnected(link)`.
    public var onPeerDisconnected: ((Data) -> Void)?

    // MARK: – Private state

    /// Registered page request handlers, keyed by request path.
    private var pageHandlers: [String: (Data?) -> Data?] = [:]

    /// Registered file request handlers, keyed by request path.
    private var fileHandlers: [String: (Data?) -> Data?] = [:]

    // MARK: – Init

    /// Create a new node with the given display name.
    public init(name: String) {
        self.name = name
    }

    // MARK: – Page registration (Python: register_pages + destination.register_request_handler)

    /// Register a handler for page requests at `path`.
    ///
    /// - Parameters:
    ///   - path:      The request path, e.g. `"/page/welcome.mu"`.
    ///   - generator: Closure receiving optional request body; returns page bytes or `nil`.
    public func registerPage(_ path: String, generator: @escaping (Data?) -> Data?) {
        pageHandlers[path] = generator
    }

    /// Returns `true` if a handler is registered for `path`.
    public func isPageRegistered(_ path: String) -> Bool {
        pageHandlers[path] != nil
    }

    /// All registered page paths, sorted alphabetically.
    public func registeredPagePaths() -> [String] {
        pageHandlers.keys.sorted()
    }

    // MARK: – File registration (Python: register_files + destination.register_request_handler)

    /// Register a handler for file requests at `path`.
    public func registerFile(_ path: String, generator: @escaping (Data?) -> Data?) {
        fileHandlers[path] = generator
    }

    /// Returns `true` if a handler is registered for `path`.
    public func isFileRegistered(_ path: String) -> Bool {
        fileHandlers[path] != nil
    }

    /// All registered file paths, sorted alphabetically.
    public func registeredFilePaths() -> [String] {
        fileHandlers.keys.sorted()
    }

    // MARK: – Request dispatch (Python: serve_page / serve_file / serve_default_index)

    /// Handle an incoming page request.
    ///
    /// Dispatch order:
    /// 1. Registered handler for `path` → returns its output.
    /// 2. `path == defaultPagePath` and no handler → returns `defaultIndexPage` bytes.
    /// 3. Otherwise → `nil` (request not found / denied by caller).
    ///
    /// Python: `serve_page(path, data, request_id, link_id, remote_identity, requested_at)`
    public func handlePageRequest(path: String, requestData: Data?) -> Data? {
        if let h = pageHandlers[path] {
            return h(requestData)
        }
        if path == Self.defaultPagePath {
            return Self.defaultIndexPage.data(using: .utf8)
        }
        return nil
    }

    /// Handle an incoming file request.
    ///
    /// Python: `serve_file(path, data, request_id, remote_identity, requested_at)`
    public func handleFileRequest(path: String, requestData: Data?) -> Data? {
        return fileHandlers[path]?(requestData)
    }

    // MARK: – Announce (Python: Node.announce)

    /// Returns the `app_data` bytes to include in an RNS announce.
    ///
    /// Python: `self.app_data = self.name.encode("utf-8")`
    public func announceData() -> Data {
        name.data(using: .utf8) ?? Data()
    }

    // MARK: – Peer lifecycle (Python: peer_connected / peer_disconnected)

    /// Called when a peer link is established to this node.
    ///
    /// In production wire this to `destination.set_link_established_callback`.
    ///
    /// - Parameter linkID: An opaque identifier for the link.
    public func handleLinkEstablished(linkID: Data) {
        onPeerConnected?(linkID)
    }

    /// Called when a peer link is closed.
    ///
    /// - Parameter linkID: Same identifier passed to `handleLinkEstablished`.
    public func handleLinkClosed(linkID: Data) {
        onPeerDisconnected?(linkID)
    }
}
