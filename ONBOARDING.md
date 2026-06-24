# Onboarding Guide: NomadNetSwift

## Overview
NomadNetSwift is a pure-Swift implementation of the **Nomad Network** protocol, designed to run over **Reticulum**. It enables building and browsing decentralized, encrypted pages and services. This project is a port of the original Python NomadNet implementation, maintaining protocol compatibility while providing a native Swift API for iOS and macOS.

## Tech Stack
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

### Core Components
- **MicronParser**: A complex state machine that converts Micron markup text into an AST of `MicronNode` and `MicronSpan` elements.
- **NomadNetURL**: Parses the `<destination_hash>:<path>` format used in Nomad Network.
- **RRC (Remote Resource Calls)**: Implements the protocol for calling remote functions/services.

## Key Entry Points
- **Sources/NomadNet/NNNode.swift**: Start here to understand how to host a NomadNet site.
- **Sources/NomadNet/NomadNetBrowser.swift**: Start here to understand how to fetch and navigate content.
- **Sources/NomadNet/MicronParser.swift**: The engine behind rendering NomadNet pages.

## Directory Map
- `Sources/NomadNet/` → Core protocol and parsing logic.
- `Tests/NomadNetTests/` → Exhaustive unit tests for all components.

## Conventions
- **Python Parity**: Comments often reference specific Python files (e.g., `Node.py` or `MicronParser.py`) to ensure logic parity.
- **Naming**: Standard Swift PascalCase for types and camelCase for members.
- **Testing**: Every major component has a corresponding `[Component]Tests.swift` file. Use `swift test` to run the suite.

## Common Tasks
- **Run tests**: `swift test`
- **Build package**: `swift build`
- **Add a new feature**: Ensure it aligns with the Python reference logic and add corresponding tests in `Tests/NomadNetTests/`.

## Where to Look
| I want to... | Look at... |
|--------------|-----------|
| Change how URLs are parsed | `Sources/NomadNet/NomadNetURL.swift` |
| Add a new Micron markup tag | `Sources/NomadNet/MicronParser.swift` |
| Modify server announce logic | `Sources/NomadNet/NNNode.swift` |
| Fix browser history issues | `Sources/NomadNet/PageHistory.swift` |
