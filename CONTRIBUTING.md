# Contributing to NomadNetSwift

NomadNetSwift targets **protocol parity with Python NomadNet**
(<https://github.com/markqvist/NomadNet>) — Micron rendering, node serving, and
browsing must match the reference.

## Ground rules

- **Test-driven**: failing test first, implement to green, commit. Keep the full
  `swift test` suite green (no regressions).
- **Parity**: source comments reference the corresponding Python files
  (`Node.py`, `MicronParser.py`, `Browser.py`, `RRC.py`) — keep logic aligned.

## Setup

```sh
git clone https://github.com/SullivanPrell/NomadNetSwift.git
cd NomadNetSwift
swift test
```

By default the package resolves ReticulumSwift from its published release. To
develop both at once, check out ReticulumSwift as a sibling directory and set:

```sh
RETICULUM_LOCAL_DEPS=1 swift test
```

## Where things live

| Component | File |
|-----------|------|
| Micron markup engine | `Sources/NomadNet/MicronParser.swift` |
| Node (server) | `Sources/NomadNet/NNNode.swift` |
| Browser (client) | `Sources/NomadNet/NomadNetBrowser.swift` |
| URL parsing | `Sources/NomadNet/NomadNetURL.swift` |
| Page history | `Sources/NomadNet/PageHistory.swift` |

## Conventions

- Standard Swift PascalCase for types, camelCase for members.
- Every major component has a `[Component]Tests.swift`.
- New behavior must align with the Python reference and ship with tests.

## Submitting changes

Branch from `main`, keep commits focused, ensure `swift test` is green, note any
interop implications. Contributions are licensed under the [Reticulum License](LICENSE).
