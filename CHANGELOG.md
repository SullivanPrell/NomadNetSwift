# Changelog

All notable changes to NomadNetSwift are documented here. This project follows
[Semantic Versioning](https://semver.org).

## [Unreleased]

## [1.6.0]—RRC on low-MTU links, three Micron features, and NNDirectory parity

### Source-breaking

- `MicronNode` has a new `.image(MicronImage, depth:)` case. A `switch` over `MicronNode`
  with no `default` arm needs one for it. RetiOS's `MicronView` and reticulum-interop's
  `MicronTestNode` have such a switch.

### NomadNet parity

- RRC handles `/list` and `/who` replies on low-MTU links as NomadNet 1.4.3 does (commit
  652a625). Python's 1.4.3 change was never ported, although this package claimed 1.4.4
  parity:
  - A `/list` reply that arrives one line per packet is merged into `availableRooms` for 60 s
    after its header (`LIST_FRAGMENT_WINDOW`).
  - A `/who` reply matches a 64-hex un-nicked member, not a 32-hex one.
  - A nicked member whose full hash is unknown is kept by its 12-hex prefix. `getMembers`
    lists it until room traffic or a `JOINED` reveals the full hash.
  - A room-less `/list` or `/who` reply no longer becomes the MOTD, and no longer goes to the
    notice log.
- RRC strips modifier and bidi characters with `strip_modifiers` from:
  - message text (`RRC.py:206`);
  - the hub name (`:1006`);
  - room names and topics (`:890`);
  - the MOTD (`:1263`, `:1402`).

  Before this, a U+202E in a message reversed the text that followed it.
- An RRC hub's default name is `RNSUtilities.prettyhexrep(hash)`, as in `RRC.py:224`.
- Micron gains three features:
  - **Collapsible headings** (`` `+> `` and `` `-> ``) and the `#!fold` directive, from
    NomadNet 1.3.0. `MicronPage.collapsibles` maps each collapsible heading's node index to
    its initial state, and `foldOpenGlyph` and `foldClosedGlyph` hold the glyphs.
  - **Inline images** (`` `( ``), from NomadNet 1.4.0, as `MicronNode.image`.
    A line starting with `` `( `` that isn't a valid image now gives no output, as in
    Python. Before, it showed as text.
  - **Multi-row fields** (`` `<30x5|name`> ``), from NomadNet 1.3.0, as `MicronField.rows`.
- Micron link parsing now matches Python in two cases (`MicronParser.py:1056-1074`):
  - **More than three parts:** the link is consumed and gives no output.
  - **Empty URL:** the link is consumed and gives no output. Before, it showed as text.
- `NNDirectory` now matches Python's `Directory.py`:
  - It ignores a node or peer announce that has no app data.
  - It no longer adds a trusted entry for a trusted peer's node. Python has that code
    commented out.
  - It saves and loads `announce_stream`.
  - It loads a missing name as `"Undefined"`.
  - `remember` copies a peer's trust to the node its identity hosts.
  - `knownNodes` sorts like Python: an unranked node at Python's `2^32`, which is 34, and a
    missing name as `"_"`.

### Micron reads numbers and structure as NomadNet 1.5.1 does

A page that NomadNet parses one way no longer parses another way here. Each change is pinned by
a vector that `scripts/micron-reference-vectors.py` prints from NomadNet itself; 73 vectors
joined the suite, and 42 of them failed before this change.

- **Numbers.** Python reads a table width, a field's width and rows and a partial's refresh
  with `int()` and `float()`, and a color one code point at a time with `int(c, 16)` and
  `int(c)`. Those accept a digit of any script, a padded value and an underscore, and reject a
  sign in a color. The port read ASCII only. `NomadNetUtil+PythonNumbers.swift` now follows
  Python's grammar for each reader (`MicronParser.py:188-192`, `:522`, `:796-845`, `:984-995`).
  `PythonDecimalDigits.swift` lists the digits Python's Unicode 16.0.0 knows, because the
  OS's Unicode version can differ; `scripts/generate-decimal-digits.py` regenerates it.
- **Partials.** A refresh that `float()` rejects drops the partial, and so do four or more
  parts (`:188-197`, `:219`). An empty field list is empty (`:209`).
- **Fields.** Only a text or masked field stores a width and rows (`:984-995`).
- **Line prefixes.** A heading line with a field loses its `>` before the escape and comment
  checks, so `>#` before a field is a comment (`:497-513`).
- **Tables.** A table renders only when its closing `` `t `` arrives and it has two rows or
  more, so an unclosed table at the end of a page and a one-row table produce nothing
  (`:131-159`, `:291-292`, `:516-531`).
- **Headings.** A heading starts from the theme style with bold, underline, italic, and the
  page colors off, and the page style comes back after it (`:21-26`, `:572-578`).

### Not ported: a color reset inside a heading

A `` `f `` or `` `b `` inside a heading returns to the page's default color in NomadNet, which
for `` >`Ff00a`fb `` is the theme's plain foreground (`MicronParser.py:15`). The port keeps
`.default`. Holding the difference needs a new `MicronColor` case, which would break exhaustive
switches in apps.

### Fixed

- An RRC hub that never answered HELLO hung its thread for good. On WELCOME timeout the hub
  tore its link down while holding its own lock. Teardown runs `onClosed`, which waits for
  that same lock. The link is now torn down outside the lock.
- An RRC hub under a custom destination name could never connect. The client built the
  destination as `rrc.hub` whatever `destName` said, so the hash check always failed.
- A failed link identify tears the RRC link down, as `RRC.py:449-454` does. Before, the
  client sent HELLO unidentified and ended in a WELCOME timeout.
- A history file whose last record was cut off loaded as empty, losing the whole room.
  `loadHistory` keeps every record before the bad one (`RRC.py:776-799`), through the new
  `CBOR.decodeValidPrefix`.
- A full disk no longer crashes the app while it appends RRC history. The append used
  `FileHandle.write(_:)`, which raises an Objective-C exception that `catch` can't handle.
- `NNDirectory` lost every sort rank on load: msgpack writes a non-negative rank as an
  unsigned int, and `load` read only signed ones.
- A data race on `RRCHub` state. The hub wrote its status, rooms, unread and mention sets,
  notices, MOTD and hub limits under its lock on network threads, while an app read the public
  properties bare. Each public property now takes the lock. Under ThreadSanitizer, the new
  `RRCHubConcurrencyTests` stress test reported a race on 3 of 3 runs before the fix and on
  0 of 3 after it.
- `RRCManager.hasUnread` no longer reads hub state while it holds the manager's lock. A hub
  calls into the manager while it holds its own lock, so reading in the opposite order could
  deadlock.

### Deprecated

- `NomadNetBrowser.encode(fields:variables:)` and `encodeFields(_:)`. Passing their `Data` to
  `Link.request(data:)` double-packs it (bugs/008). Use `encodeValue(fields:variables:)`.
- `NNDirectory.addNodeAnnounce`, `addPeerAnnounce` and `addPNAnnounce`. They had no callers
  and no Python counterpart. Use the `*AnnounceReceived` methods.


## [1.5.2]—NomadNet 1.5.1: a custom RRC hub name is a wanted type

### NomadNet 1.5.1 parity

NomadNetSwift now tracks NomadNet 1.5.1, up from 1.4.4, and requires ReticulumSwift 1.28.0
for `Reticulum.wantsDestinationType(_:requester:)`.

- An RRC hub under a destination name other than `rrc.hub` asks the host's Reticulum instance
  for that destination type (`RRC.py:226-227`).

### Not ported from NomadNet 1.5.1

- `NomadNetworkApp` settings: the node's `link_cost` (default 17.8) and `stamp_value`, the
  client's LXMF `stamp_value`, and the wanted `nomadnetwork.node` and `rrc.hub` types at
  startup (`NomadNetworkApp.py:39-40`, `:109-111`, `:874-877`, `:1157-1165`, `Node.py:24-25`).
  This package has no port of `NomadNetworkApp`, and `NNNode` doesn't create its destination,
  so they belong to the host app.
- The stamp costs and values in the text UI's announce stream (`ui/textui/Network.py`), and
  the guide's text for the new settings (`ui/textui/Guide.py`).

## [1.5.1]—RRC integers past Int.max are skipped

NomadNetSwift requires ReticulumSwift 1.26.0, which refuses a resource advertisement with a data
size past `Int.max`. The RRC hub converts that size with `Int(_:)`
(`Sources/NomadNet/RRC.swift:658`).

### Fixed

- An RRC packet carrying an integer past `Int.max` no longer stops the process. The hub's packet
  handler skips such a key, drops a packet whose type or resource size is out of range, and
  ignores such a capability or limit. Python's CBOR decoder reads any integer as an unbounded
  `int` (`RRC.py:964-975`, `:1013-1021`), so one hub packet could end the app.

## [1.5.0]—Micron by code point, and bounded CBOR nesting

### The Micron parser reads a line by code point

NomadNet indexes a Micron line by code point (`MicronParser.py:476-694`, `:871-1141`).
`MicronParser` read graphemes, so a combining mark, a regional-indicator pair, a Hangul jamo
sequence, or a prepended letter such as U+0D4E joined the character beside it. It reads code
points throughout:

- `parsePage` splits a page on the `"\n"` code point (`MicronParser.py:117`), so `"\r\n"` ends
  a line and leaves `"\r"` on it. `NomadNetBrowser` already broke lines there, because
  `stripModifiers` rewrites `"\r\n"` as `"\n"` (`util.py:123`).
- The `#`, `\`, `<`, and `>` line prefixes, the `` `t `` and `` `{ `` prefixes, and the `` `< ``
  check that removes a heading's `>` compare one code point (`MicronParser.py:479-559`).
- Inline tag characters, the `` `F `` and `` `B `` color values, and the link, field, and
  partial delimiters compare and count code points (`MicronParser.py:883-1132`).
- An anchor name runs while Python's `str.isalnum()` accepts the code point
  (`MicronParser.py:939`). `Character.isLetter` also accepted symbols such as `Ⓐ` (U+24B6).
- `pageColorDirective` finds `#!fg=` and `#!bg=` by code point (`Browser.py:1824-1844`), so a
  combining mark after the first directive no longer hides it.

`scripts/micron-reference-vectors.py` prints the expected values in `MicronCodePointTests` from
NomadNet 1.4.4.

### Fixed

- `CBOR.decode` and `CBOR.decodeAll` throw `CBORError.nestingTooDeep` for an array or map
  nested more than 100 levels deep. NomadNet drops an RRC packet that fails to decode
  (`RRC.py:965-969`). The port's decoder recursed once per level with no limit, so one hub
  packet of 16,000 nested `0x81` bytes overflowed the stack and crashed the app. NomadNet's
  vendored decoder sets `_MAX_DEPTH = 100` (`cbor.py:226`) but counts only tag nesting against
  it (`cbor.py:311-312`, `:364`), so Python accepts array and map nesting up to its recursion
  limit, near 330 levels. No RRC envelope nests more than three.

## [1.4.0]—NomadNet 1.4.4 parity

NomadNetSwift tracks Python NomadNet 1.4.4, and requires ReticulumSwift 1.23.0, which ports
the RNS 1.5.5 that NomadNet 1.4.4 requires.

### A divider draws ─ when its fill character doesn't fit one cell

NomadNet 1.4.4 keeps a divider's fill character only when urwid renders it in one terminal
cell (`MicronParser.py:603-613`). A wide character such as `漢` or an emoji, a combining mark,
or a zero-width character falls back to `─`. `MicronCellWidth` holds the code points whose
width isn't 1. `scripts/generate-cell-width.py` writes it from wcwidth 0.9.1 (Unicode 18.0),
which urwid 4.2.4 measures with.

The divider reads its line by code point, as Python does, so `-` followed by a combining mark
is a divider rather than a line of text.

### A page loses the characters Python strips before rendering

These close gaps against NomadNet 1.4.3 that change what a divider, and every other line,
contains:

- `parsePage` removes the control, zero-width, and bidi characters that `STRIP_CONTROL_RE`
  matches before it splits the page into lines (`MicronParser.py:107`).
- `NomadNetBrowser.handleResponse` parses the page after `stripModifiers`, and reads the page
  colors from the markup as sent (`Browser.py:1824-1846`).
- `stripModifiers` removes the `STRIP_CONTROL_RE` characters and trims leading and trailing
  whitespace as `str.strip()` does, newlines included (`util.py:92-126`). It trimmed spaces
  and tabs only, so a page kept its trailing empty lines and a name kept its control
  characters.

### Not ported

- The propagation node announce log names the node's implementation and version
  (`Directory.py:24-27`). NomadNetSwift has no propagation node announce handler, and nothing
  calls `NNDirectory.pnAnnounceReceived`.
- `_termlib` loads without `termios` on platforms that lack it. NomadNetSwift doesn't render
  images in a terminal.

### CI

The tests use Swift Testing, which needs Xcode 16 or later. Build & test runs on macos-15 with
Xcode 26.3 pinned, and a Build (Swift 5.10) job builds the library on macos-14.

## [1.3.0]—relicensed to match upstream NomadNet

### Changed

- Licensed under GPL-3.0-only, the license of upstream
  [NomadNet](https://github.com/markqvist/NomadNet), which this package translates.
  `LICENSE` carries the unmodified GPLv3 text, and every source file's header carries
  `SPDX-License-Identifier: GPL-3.0-only`. Releases through 1.2.0 carried the Reticulum
  License.
- README and CONTRIBUTING state that the package is a translation of the Python
  reference, not an independent implementation.

### Deprecated

- `RRCHub._onPacket(_:)`, `RRCHub._msgFromEntry(room:entry:)` and
  `RRCHub._persistableRoom(_:)`—use `onPacket(_:)`, `msgFromEntry(room:entry:)`
  and `persistableRoom(_:)`. The 1.2.0 names remain as forwarding aliases marked
  `@available(*, deprecated, renamed:)` until 2.0.0.
  `swift package diagnose-api-breaking-changes 1.2.0` reports no breaking changes.

## [1.2.0]

### Added

- `MicronParser.parsePage(_:)` returning `MicronPage`—the page-level parse
  result carrying the node tree, the anchors map (name → node index, bound the
  way `markup_to_attrmaps` binds `pending_anchors` to rows), and the `#!fg=` /
  `#!bg=` page colors extracted the way the Python browser does
  (Browser.py:1247-1267). Page colors also seed the parser's default
  foreground/background, so plain text inherits them and `` `f ``/`` `b ``
  reset to them.
- `MicronNode.anchor` marker nodes are now emitted into the tree ahead of each
  row bound by an explicit `` `:name `` declaration (previously the parsed
  anchor name was discarded); heading slugs bind to the `.heading` node itself.
- `NomadNetBrowser.onPageParsed` callback and `NomadNetBrowser.currentPage`,
  exposing the page-level result (colors + anchors) to consumers—the Swift
  equivalent of the Python browser's `page_background_color` /
  `page_foreground_color` and `attr_maps.anchors` state.

### Fixed

- Horizontal-rule fill characters outside ASCII (`-═`, `-•`, `-★`, …) are now
  kept, matching the Python parser, which accepts any fill char with
  `ord >= 32` (MicronParser.py:325-336). Previously the `asciiValue` check
  collapsed every non-ASCII fill to the default `─`.

### Deprecated

- `MicronParser.parse(_:)`—use `parsePage(_:)`; the nodes-only result
  discards page colors and anchors.

## [1.0.0]—initial public release

First public release of NomadNetSwift—a Swift port of
[NomadNet](https://github.com/markqvist/NomadNet) (Nomad Network), wire-compatible
with the Python reference.

### Highlights

- **Micron** markup parser → renderable AST (`MicronNode` / `MicronSpan`), with
  helpers for stripping codes and slugifying.
- **NNNode**—host Micron pages and downloadable files with on-demand generators,
  announce data, and link-peer tracking.
- **NomadNetBrowser**—fetch and navigate content with page history
  (back / forward / reload) and `NomadNetURL` address parsing.
- **RRC**—Remote Resource Calls for invoking remote services.
- **NNDirectory**—a directory of known nodes learned from announces.

Covered by 470 unit tests (~83% line coverage). Built on ReticulumSwift 1.0.0.
