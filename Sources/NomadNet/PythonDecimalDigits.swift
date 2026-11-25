//===----------------------------------------------------------------------===//
// Copyright (c) 2026 NomadNetSwift contributors.
//
// Licensed under the GNU General Public License, version 3 (GPL-3.0). See
// LICENSE in the repository root for the full license text, and NOTICE for
// attribution of the upstream project this file is derived from.
//
// SPDX-License-Identifier: GPL-3.0-only
//===----------------------------------------------------------------------===//

/// The value of a code point that Python reads as one decimal digit.
///
/// NomadNet reads the width, rows, color and refresh of a Micron tag with `int()` and `float()`
/// (`MicronParser.py:984-995`, `:188-192`). `int()` accepts a digit of any script, which is
/// every code point of general category `Nd`. `Unicode.Scalar.Properties` answers from the
/// Unicode version of the OS that runs the code, so it disagrees with Python wherever the two
/// versions differ: Unicode 17 added the Tolong Siki digits, U+11DE0 to U+11DE9.
///
/// `scripts/generate-decimal-digits.py` wrote this file from Python 3.14.5
/// (Unicode 16.0.0).
enum PythonDecimalDigits {

  /// The value of `scalar` as one decimal digit, or `nil` when Python doesn't read it as one.
  static func value(_ scalar: Unicode.Scalar) -> Int? {
    let code = scalar.value
    var low = 0
    var high = blocks.count
    while low < high {
      let middle = (low + high) / 2
      if blocks[middle] <= code { low = middle + 1 } else { high = middle }
    }
    guard low > 0 else { return nil }
    let offset = code - blocks[low - 1]
    return offset < 10 ? Int(offset) : nil
  }

  /// The first code point of every run of ten digits, 0 to 9, in ascending order.
  static let blocks: [UInt32] = [
    0x30, 0x660, 0x6F0, 0x7C0, 0x966, 0x9E6,
    0xA66, 0xAE6, 0xB66, 0xBE6, 0xC66, 0xCE6,
    0xD66, 0xDE6, 0xE50, 0xED0, 0xF20, 0x1040,
    0x1090, 0x17E0, 0x1810, 0x1946, 0x19D0, 0x1A80,
    0x1A90, 0x1B50, 0x1BB0, 0x1C40, 0x1C50, 0xA620,
    0xA8D0, 0xA900, 0xA9D0, 0xA9F0, 0xAA50, 0xABF0,
    0xFF10, 0x104A0, 0x10D30, 0x10D40, 0x11066, 0x110F0,
    0x11136, 0x111D0, 0x112F0, 0x11450, 0x114D0, 0x11650,
    0x116C0, 0x116D0, 0x116DA, 0x11730, 0x118E0, 0x11950,
    0x11BF0, 0x11C50, 0x11D50, 0x11DA0, 0x11F50, 0x16130,
    0x16A60, 0x16AC0, 0x16B50, 0x16D70, 0x1CCF0, 0x1D7CE,
    0x1D7D8, 0x1D7E2, 0x1D7EC, 0x1D7F6, 0x1E140, 0x1E2F0,
    0x1E4F0, 0x1E5F1, 0x1E950, 0x1FBF0,
  ]
}
