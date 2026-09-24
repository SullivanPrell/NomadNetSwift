# Onboarding Guide: NomadNetSwift

## Overview
NomadNetSwift is a Swift translation of the Python **Nomad Network** implementation, running over **Reticulum**. It builds and browses pages and services over the mesh, with end-to-end encryption and no central server. It isn't a clean-room implementation: the code follows the Python source closely and cites it throughout, and the Python implementation is the authority on protocol behavior.

## Tech stack
| Layer | Technology | Version |
|-------|-----------|---------|
| Language | Swift | 5.9+ |
| Platforms | iOS / macOS | iOS 16+ / macOS 13+ |
| Protocol | Reticulum | via ReticulumSwift |
| Markup | Micron | Native Parser |

## Architecture
The project is structured as a Swift Package with two main responsibilities:

### 1. Node (Server) logic - `NNNode.swift`
Handles serving Micron pages and binary files. It manages request routing, handlers, and follows the Python reference implementation for job intervals and announces.

### 2. Browser (Client) logic - `NomadNetBrowser.swift`
Handles requesting content from nodes, managing page history, and resolving URLs via `NomadNetURL`.

### Core components
- **MicronParser**: a complex state machine that converts Micron markup text into an AST of `MicronNode` and `MicronSpan` elements.
- **NomadNetURL**: parses the `<destination_hash>:<path>` format used in Nomad Network.
- **RRC (Reticulum Relay Chat)**: the client for real-time chat rooms hosted on RRC hubs.

## Key entry points
- **Sources/NomadNet/NNNode.swift**: start here to understand how to host a NomadNet site.
- **Sources/NomadNet/NomadNetBrowser.swift**: start here to understand how to fetch and navigate content.
- **Sources/NomadNet/MicronParser.swift**: the engine behind rendering NomadNet pages.

## Directory map
- `Sources/NomadNet/` → Core protocol and parsing logic.
- `Tests/NomadNetTests/` → Unit tests for all components.

## Conventions
- **Python parity**: doc comments name the Python file and function each part translates (for example, `Node.py` or `MicronParser.py`). New code does the same.
- **Naming**: standard Swift PascalCase for types and camelCase for members.
- **Testing**: every major component has a corresponding `[Component]Tests.swift` file. Use `swift test` to run the suite.

## Common tasks
- **Run tests**: `swift test`
- **Build package**: `swift build`
- **Add a new feature**: ensure it aligns with the Python reference logic and add corresponding tests in `Tests/NomadNetTests/`.

## Where to look
| Goal | Look at |
|--------------|-----------|
| Change how URLs are parsed | `Sources/NomadNet/NomadNetURL.swift` |
| Add a new Micron markup tag | `Sources/NomadNet/MicronParser.swift` |
| Modify server announce logic | `Sources/NomadNet/NNNode.swift` |
| Fix browser history issues | `Sources/NomadNet/PageHistory.swift` |
