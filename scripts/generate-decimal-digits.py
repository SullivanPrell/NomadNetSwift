#!/usr/bin/env python3
"""Write Sources/NomadNet/PythonDecimalDigits.swift from unicodedata.

Python's int() reads a code point as one decimal digit when the code point is in general
category Nd, and NomadNet reads the width, rows, color and refresh of a Micron tag with int()
and float() (MicronParser.py:984-995, :188-192). Swift's Unicode.Scalar.Properties answer from
the Unicode version of the OS that runs the code, so they disagree with Python wherever the two
versions differ. On 2026-10-07, macOS 26.6.2 with Swift 6.4 called U+11DE0 to U+11DE9 digits
(Unicode 17 added them) and Python 3.14.5, which has Unicode 16.0.0, did not. This script lists
the runs of ten digits that the Python in reticulum-interop's venv knows instead.

Copy this file to scripts/generate-decimal-digits.py in NomadNetSwift, then run it with
reticulum-interop's venv from the NomadNetSwift root, and regenerate when that venv's Python
moves to a new Unicode version:

    ../reticulum-interop/.venv/bin/python scripts/generate-decimal-digits.py

The script stops with an assertion when a fact that the Swift lookup depends on stops holding:

- int() accepts a code point as a digit exactly when its category is Nd.
- int() and unicodedata.decimal() agree on the value of every such code point.
- The digits come in runs of ten consecutive code points with the values 0 to 9, so one
  starting code point per run is enough.

Pass a path as the first argument to also write "<hex code point> <value>" for every digit,
one per line. The Swift check in NN-01 reads that file.
"""
import os
import sys
import unicodedata

HEADER_PATH = os.path.join(os.path.dirname(__file__), "license-header.txt")
OUTPUT_PATH = os.path.join(
    os.path.dirname(__file__), "..", "Sources", "NomadNet", "PythonDecimalDigits.swift")
BLOCKS_PER_LINE = 6


def scalar_values():
    return [value for value in range(0x110000) if not 0xD800 <= value <= 0xDFFF]


def decimal_digits():
    digits = []
    for value in scalar_values():
        character = chr(value)
        try:
            number = int(character)
        except ValueError:
            continue
        assert unicodedata.decimal(character, None) == number, hex(value)
        digits.append((value, number))
    category_nd = [
        value for value in scalar_values() if unicodedata.category(chr(value)) == "Nd"]
    assert category_nd == [value for value, _ in digits], "Nd and int() disagree"
    return digits


def block_starts(digits):
    starts = []
    for index in range(0, len(digits), 10):
        run = digits[index:index + 10]
        start = run[0][0]
        assert [number for _, number in run] == list(range(10)), hex(start)
        assert [value for value, _ in run] == list(range(start, start + 10)), hex(start)
        starts.append(start)
    return starts


def main():
    with open(HEADER_PATH) as header_file:
        header = header_file.read().replace("${year}", "2026")
    digits = decimal_digits()
    starts = block_starts(digits)
    lines = []
    for index in range(0, len(starts), BLOCKS_PER_LINE):
        chunk = starts[index:index + BLOCKS_PER_LINE]
        lines.append("    " + ", ".join(f"0x{start:X}" for start in chunk) + ",")
    python_version = sys.version.split()[0]
    body = f"""
/// The value of a code point that Python reads as one decimal digit.
///
/// NomadNet reads the width, rows, color and refresh of a Micron tag with `int()` and `float()`
/// (`MicronParser.py:984-995`, `:188-192`). `int()` accepts a digit of any script, which is
/// every code point of general category `Nd`. `Unicode.Scalar.Properties` answers from the
/// Unicode version of the OS that runs the code, so it disagrees with Python wherever the two
/// versions differ: Unicode 17 added the Tolong Siki digits, U+11DE0 to U+11DE9.
///
/// `scripts/generate-decimal-digits.py` wrote this file from Python {python_version}
/// (Unicode {unicodedata.unidata_version}).
enum PythonDecimalDigits {{

  /// The value of `scalar` as one decimal digit, or `nil` when Python doesn't read it as one.
  static func value(_ scalar: Unicode.Scalar) -> Int? {{
    let code = scalar.value
    var low = 0
    var high = blocks.count
    while low < high {{
      let middle = (low + high) / 2
      if blocks[middle] <= code {{ low = middle + 1 }} else {{ high = middle }}
    }}
    guard low > 0 else {{ return nil }}
    let offset = code - blocks[low - 1]
    return offset < 10 ? Int(offset) : nil
  }}

  /// The first code point of every run of ten digits, 0 to 9, in ascending order.
  static let blocks: [UInt32] = [
{chr(10).join(lines)}
  ]
}}
"""
    with open(OUTPUT_PATH, "w") as output:
        output.write(header.rstrip("\n") + "\n\n" + body.lstrip("\n"))
    print(
        f"wrote {len(digits)} digits in {len(starts)} blocks of ten to "
        f"{os.path.normpath(OUTPUT_PATH)}",
        file=sys.stderr)
    if len(sys.argv) > 1:
        with open(sys.argv[1], "w") as expected:
            for value, number in digits:
                expected.write(f"{value:X} {number}\n")


if __name__ == "__main__":
    main()

# The Swift check. It compares PythonDecimalDigits.value against the file that the script
# writes when you pass a path, for every scalar, and compares the standard library's answer for
# the same scalars so that a future Swift release that fixes the gap shows up. Save it as
# main.swift without the leading "# ", and compile:
#
#   swiftc -O -o digits-check Sources/NomadNet/PythonDecimalDigits.swift main.swift
#   ./digits-check expected.txt
#
# A run on 2026-10-07 checked 1,112,064 scalars against 760 digits: the table was wrong for none,
# and the standard library was wrong for U+11DE0 to U+11DE9.
#
# import Foundation
#
# var expected: [UInt32: Int] = [:]
# let text = try! String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
# for line in text.split(separator: "\n") {
#   let parts = line.split(separator: " ")
#   expected[UInt32(parts[0], radix: 16)!] = Int(parts[1])!
# }
# var standardLibraryWrong: [UInt32] = []
# var tableWrong: [UInt32] = []
# var checked = 0
# for value in UInt32(0)...0x10FFFF {
#   guard let scalar = Unicode.Scalar(value) else { continue }
#   checked += 1
#   let standard: Int? =
#     scalar.properties.generalCategory == .decimalNumber
#     ? scalar.properties.numericValue.map { Int($0) } : nil
#   if standard != expected[value] { standardLibraryWrong.append(value) }
#   if PythonDecimalDigits.value(scalar) != expected[value] { tableWrong.append(value) }
# }
# print("checked \(checked) scalars, \(expected.count) digits expected")
# print("standard library: \(standardLibraryWrong.count) wrong",
#   standardLibraryWrong.prefix(10).map { String($0, radix: 16) })
# print("generated table:  \(tableWrong.count) wrong", tableWrong.prefix(10).map { String($0, radix: 16) })
# exit(tableWrong.isEmpty ? 0 : 1)
