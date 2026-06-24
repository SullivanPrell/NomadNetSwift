# NomadNetSwift

A Swift port of [NomadNet](https://github.com/markqvist/NomadNet) (Nomad Network)
— decentralized, encrypted pages and services over Reticulum.

[![Platforms](https://img.shields.io/badge/platforms-iOS%2016%2B%20%7C%20macOS%2013%2B-blue)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange)](https://swift.org)
[![Tests](https://img.shields.io/badge/tests-470%20passing-brightgreen)](#testing)
[![License](https://img.shields.io/badge/license-Reticulum-lightgrey)](LICENSE)

Nomad Network is a resilient, server-optional "web" that runs entirely over
Reticulum: nodes host pages written in **Micron** markup and serve files; clients
browse them by cryptographic address. It works over any Reticulum interface —
including LoRa and packet radio — with no DNS, no central servers, and end-to-end
encryption throughout.

**NomadNetSwift** brings that to Swift: a Micron parser, a page/file-serving
node, a browser, RRC (Remote Resource Calls), and a node directory — all
wire-compatible with the Python reference, so a Swift client can browse a Python
node and vice versa.

This is part of the [ReticulumSwift stack](https://github.com/SullivanPrell/ReticulumSwift#the-reticulumswift-stack).

## Status

**At parity with Python NomadNet.** Micron markup, Browser, node (`NNNode`),
RRC, and the node directory (`NNDirectory`). **470 unit tests, 0 failures.**

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

- [docs/USAGE.md](docs/USAGE.md) — Micron, nodes, browser, RRC, directory
- [CONTRIBUTING.md](CONTRIBUTING.md) — dev workflow and conventions

## Testing

```sh
swift test
RETICULUM_LOCAL_DEPS=1 swift test     # develop against a sibling ReticulumSwift checkout
```

## License

Released under the **Reticulum License** (no harm-capable systems; no AI/ML
training datasets). See [LICENSE](LICENSE). NomadNetSwift is a derivative work of
[NomadNet](https://github.com/markqvist/NomadNet) by Mark Qvist; see [NOTICE](NOTICE).
