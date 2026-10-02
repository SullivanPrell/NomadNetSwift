#!/usr/bin/env python3
"""Write Sources/NomadNet/MicronCellWidth.swift from wcwidth.

NomadNet keeps a Micron divider's fill character only when urwid renders it in one
terminal cell (MicronParser.py:603-613). urwid measures a character with wcwidth, so
the Swift table lists every code point from U+0020 up whose wcwidth isn't 1.

Run it with reticulum-interop's venv after `make deps`, which installs the urwid and
wcwidth that NomadNet resolves to, and regenerate when either changes:

    ../../reticulum-interop/.venv/bin/python scripts/generate-cell-width.py
"""
import os
import sys

import urwid
import wcwidth

HEADER_PATH = os.path.join(os.path.dirname(__file__), "license-header.txt")
OUTPUT_PATH = os.path.join(
    os.path.dirname(__file__), "..", "Sources", "NomadNet", "MicronCellWidth.swift")
RANGES_PER_LINE = 4


def not_single_cell_ranges():
    ranges = []
    start = None
    for value in range(0x20, 0x110000):
        surrogate = 0xD800 <= value <= 0xDFFF
        wide_or_zero = not surrogate and wcwidth.wcwidth(chr(value)) != 1
        if wide_or_zero and start is None:
            start = value
        elif not wide_or_zero and start is not None:
            ranges.append((start, value - 1))
            start = None
    if start is not None:
        ranges.append((start, 0x10FFFF))
    return ranges


def main():
    with open(HEADER_PATH) as header_file:
        header = header_file.read().replace("${year}", "2026")
    ranges = not_single_cell_ranges()
    lines = []
    for index in range(0, len(ranges), RANGES_PER_LINE):
        chunk = ranges[index:index + RANGES_PER_LINE]
        lines.append("    " + " ".join(f"0x{low:05X}...0x{high:05X}," for low, high in chunk))
    unicode_version = wcwidth.list_versions()[-1]
    body = f"""
/// The terminal cell width of a code point, as urwid measures it.
///
/// NomadNet keeps a divider's fill character only when urwid renders it in one cell
/// (`MicronParser.py:603-613`). urwid measures a character with wcwidth, so a fill renders
/// when `wcwidth` returns 1.
///
/// `scripts/generate-cell-width.py` wrote this file from wcwidth {wcwidth.__version__}
/// (Unicode {unicode_version}), as urwid {urwid.__version__} uses it.
enum MicronCellWidth {{

  /// Whether urwid draws `scalar` in exactly one terminal cell.
  static func isSingleCell(_ scalar: Unicode.Scalar) -> Bool {{
    let value = scalar.value
    if value < 0x20 {{ return false }}
    var low = 0
    var high = notSingleCell.count - 1
    while low <= high {{
      let middle = (low + high) / 2
      let range = notSingleCell[middle]
      if value < range.lowerBound {{
        high = middle - 1
      }} else if value > range.upperBound {{
        low = middle + 1
      }} else {{
        return false
      }}
    }}
    return true
  }}

  /// Every code point from U+0020 up whose width isn't 1, in ascending order.
  static let notSingleCell: [ClosedRange<UInt32>] = [
{chr(10).join(lines)}
  ]
}}
"""
    with open(OUTPUT_PATH, "w") as output:
        output.write(header.rstrip("\n") + "\n\n" + body.lstrip("\n"))
    print(f"wrote {len(ranges)} ranges to {os.path.normpath(OUTPUT_PATH)}", file=sys.stderr)


if __name__ == "__main__":
    main()
