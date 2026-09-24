# Changelog

All notable changes to NomadNetSwift are documented here. This project follows
[Semantic Versioning](https://semver.org).

## [Unreleased]

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
