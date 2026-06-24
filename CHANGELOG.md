# Changelog

All notable changes to NomadNetSwift are documented here. This project follows
[Semantic Versioning](https://semver.org).

## [1.0.0] — Initial public release

First public release of NomadNetSwift — a Swift port of
[NomadNet](https://github.com/markqvist/NomadNet) (Nomad Network), wire-compatible
with the Python reference.

### Highlights

- **Micron** markup parser → renderable AST (`MicronNode` / `MicronSpan`), with
  helpers for stripping codes and slugifying.
- **NNNode** — host Micron pages and downloadable files with on-demand generators,
  announce data, and link-peer tracking.
- **NomadNetBrowser** — fetch and navigate content with page history
  (back / forward / reload) and `NomadNetURL` address parsing.
- **RRC** — Remote Resource Calls for invoking remote services.
- **NNDirectory** — a directory of known nodes learned from announces.

470 unit tests, 0 failures. Built on ReticulumSwift 1.0.0.
