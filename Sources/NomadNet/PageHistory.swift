import Foundation

/// Manages back/forward navigation history for the NomadNet browser.
///
/// Mirrors the Python `Browser` history list and `history_ptr` logic
/// from `Browser.py` (`write_history`, `back`, `forward`).
///
/// # Invariants
/// - `entries` holds all visited URLs in chronological order up to `position`.
/// - `position` is the index of the currently visible entry, or `-1` when empty.
/// - Pushing a new URL while positioned in the middle of the list truncates
///   the forward portion (consistent with the Python implementation).
public final class PageHistory {

    // MARK: - Stored properties

    /// All history entries. Index 0 is the oldest entry.
    public private(set) var entries: [NomadNetURL]

    /// Index of the currently displayed entry, or `-1` when empty.
    public private(set) var position: Int

    // MARK: - Initialiser

    public init() {
        entries = []
        position = -1
    }

    // MARK: - Current entry

    /// The URL at the current position, or `nil` when history is empty.
    public var current: NomadNetURL? {
        guard position >= 0, position < entries.count else { return nil }
        return entries[position]
    }

    // MARK: - Navigation predicates

    /// Whether a `back()` call would move to a previous entry.
    public var canGoBack: Bool { position > 0 }

    /// Whether a `forward()` call would move to a later entry.
    public var canGoForward: Bool { position < entries.count - 1 }

    // MARK: - Mutation

    /// Push a new URL onto the history stack.
    ///
    /// If the current position is not at the end of the list, all entries
    /// after the current position are discarded (matching browser conventions
    /// and the Python `write_history` truncation behaviour).
    public func push(_ url: NomadNetURL) {
        // Truncate forward history
        if position < entries.count - 1 {
            entries = Array(entries[0...position])
        }
        entries.append(url)
        position = entries.count - 1
    }

    /// Move back one entry and return the URL, or `nil` if already at the start.
    @discardableResult
    public func back() -> NomadNetURL? {
        guard position > 0 else { return nil }
        position -= 1
        return entries[position]
    }

    /// Move forward one entry and return the URL, or `nil` if already at the end.
    @discardableResult
    public func forward() -> NomadNetURL? {
        guard position < entries.count - 1 else { return nil }
        position += 1
        return entries[position]
    }
}
