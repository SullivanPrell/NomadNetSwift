# NomadNetSwift

> **Reticulum and Nomad Network are the work of [Mark Qvist](https://github.com/markqvist).** NomadNetSwift
> is a community translation of his Python NomadNet implementation into Swift. It's
> **not an official Reticulum project** and **not a clean-room implementation**. The
> canonical project and reference implementation live at
> **[github.com/markqvist/NomadNet](https://github.com/markqvist/NomadNet)**, part of the broader
> **[Reticulum](https://github.com/markqvist/Reticulum)** network created by Mark Qvist;
> start there to understand the protocol itself. See [Provenance](#provenance).

A Swift port of [NomadNet](https://github.com/markqvist/NomadNet) (Nomad Network): pages and services carried over Reticulum, with end-to-end encryption and no central server.

[![Platforms](https://img.shields.io/badge/platforms-iOS%2016%2B%20%7C%20macOS%2013%2B-blue)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange)](https://swift.org)
[![CI](https://github.com/SullivanPrell/NomadNetSwift/actions/workflows/ci.yml/badge.svg)](https://github.com/SullivanPrell/NomadNetSwift/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/badge/coverage-83%25-brightgreen)](#testing)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)

Nomad Network is a resilient, server-optional "web" that runs entirely over
Reticulum: nodes host pages written in **Micron** markup and serve files; clients
browse them by cryptographic address. It works over any Reticulum interface—including
LoRa and packet radio—with no DNS, no central servers, and end-to-end
encryption throughout.

**NomadNetSwift** translates that into Swift: a Micron parser, a node that serves
pages and files, a browser, an RRC (Reticulum Relay Chat) client, and a node directory. In the
interoperability suite, a Swift client browses a Python node and the reverse.

This is part of the [ReticulumSwift stack](https://github.com/SullivanPrell/ReticulumSwift#the-reticulumswift-stack).

## Status

NomadNetSwift is **experimental**. It covers Micron markup, the browser, the node
(`NNNode`), the RRC client, and the node directory (`NNDirectory`). The Python
implementation is the authority on how NomadNet behaves. Where this port differs from
it, the port is wrong. Unit tests cover about 83% of lines.

## Requirements

- Swift 5.9+, iOS 16+ / macOS 13+
- Depends on [ReticulumSwift](https://github.com/SullivanPrell/ReticulumSwift) 1.0.0+

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/SullivanPrell/NomadNetSwift.git", from: "1.0.0")
],
targets: [
    .target(name: "MyApp", dependencies: [.product(name: "NomadNet", package: "NomadNetSwift")])
]
```

## Quick start

### Host a page

```swift
import NomadNet

let node = NNNode(name: "My Node")
node.registerPage("/page/index.mu") { _ in
    // Micron markup: `F00f sets a foreground colour, `! toggles bold, `` resets.
    Data("""
    `F00f`!Welcome``
    This page is served over Reticulum.
    """.utf8)
}
```

### Browse a page

```swift
let browser = NomadNetBrowser()
browser.onPageLoaded = { nodes, url in
    // `nodes` is the parsed Micron AST, ready to render
}
browser.onError = { message, url in /* handle failure */ }

let url = NomadNetURL("<destination_hash>:/page/index.mu")
browser.navigate(to: url)            // goBack() / goForward() / reload() also available
```

### Parse Micron directly

```swift
let ast = MicronParser.parse("`!bold`f normal `*italic`f")
```

See [docs/USAGE.md](docs/USAGE.md) for Micron markup, serving files, RRC, and the
node directory.

## Documentation

- [docs/USAGE.md](docs/USAGE.md)—Micron, nodes, browser, RRC, directory
- [CONTRIBUTING.md](CONTRIBUTING.md)—dev workflow and conventions

## Testing

```sh
swift test
RETICULUM_LOCAL_DEPS=1 swift test     # develop against a sibling ReticulumSwift checkout
```

## Provenance

NomadNetSwift is a translation of the Python NomadNet implementation, not an independent or
clean-room implementation of the protocol. Its authors wrote it from the Python source,
and the code follows that source closely: types, functions, constants, and control flow
mirror their Python counterparts, and doc comments in 10 of 11 of the files in `Sources/`
cite the Python file, function, or line that each part translates. That makes it a
derivative work of NomadNet. See [NOTICE](NOTICE).

Its authors wrote most of the code with machine assistance (Claude Code). Commits made
that way carry a `Co-Authored-By: Claude` trailer.

## License

NomadNet itself is **GPL-3.0**, not the Reticulum License used by RNS and LXMF.
As a derivative work, NomadNetSwift is released under the same license: the
**GNU General Public License, version 3**. See [LICENSE](LICENSE). NomadNetSwift
is a derivative work of [NomadNet](https://github.com/markqvist/NomadNet) by
Mark Qvist, as [Provenance](#provenance) describes. See [NOTICE](NOTICE).
