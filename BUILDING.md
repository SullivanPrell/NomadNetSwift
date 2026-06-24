# Building NomadNetSwift

This project is a standard Swift Package. You can build and test it using the Swift Package Manager (SwiftPM) from your terminal.

## Prerequisites

- **Swift 5.9 or later**
- **macOS** (for full platform support)

## Build Commands

To build the library:

```bash
swift build
```

To build for release with optimizations:

```bash
swift build -c release
```

## Running Tests

The project includes an extensive unit test suite. To run all tests:

```bash
swift test
```

To run a specific test target:

```bash
swift test --filter NomadNetTests
```

## Project Cleanup

If you need to clear the build artifacts and start fresh:

```bash
swift package clean
swift package reset
```

## Dependencies

This package depends on `ReticulumSwift`. Ensure that the dependency path in `Package.swift` is valid for your local environment. By default, it looks for it in the sibling directory:

```swift
dependencies: [
    .package(path: "../ReticulumSwift"),
]
```

## Integration

To use NomadNetSwift in another Swift project, add it to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(path: "path/to/NomadNetSwift")
]
```
