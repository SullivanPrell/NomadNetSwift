//===----------------------------------------------------------------------===//
// Copyright (c) 2026 NomadNetSwift contributors.
//
// Licensed under the GNU General Public License, version 3 (GPL-3.0). See
// LICENSE in the repository root for the full license text, and NOTICE for
// attribution of the upstream project this file is derived from.
//
// SPDX-License-Identifier: GPL-3.0-only
//===----------------------------------------------------------------------===//

import Foundation

extension NomadNetUtil {

  // MARK: - Python number grammar

  /// The value of `scalar` as one decimal digit, as Python's `int(scalar)` reads it, or `nil`.
  ///
  /// Python accepts a digit of any script, which is every code point of general category `Nd`.
  /// A sign, an underscore, a space and a superscript digit aren't digits.
  static func pythonDecimalDigit(_ scalar: Unicode.Scalar) -> Int? {
    PythonDecimalDigits.value(scalar)
  }

  /// The value of `scalar` as one hexadecimal digit, as Python's `int(scalar, 16)` reads it, or
  /// `nil`.
  ///
  /// Python accepts a decimal digit of any script and the ASCII letters `a` to `f` in either
  /// case. A fullwidth `A` isn't a digit.
  static func pythonHexDigit(_ scalar: Unicode.Scalar) -> Int? {
    if let value = PythonDecimalDigits.value(scalar) { return value }
    switch scalar.value {
    case 0x61...0x66: return Int(scalar.value) - 0x61 + 10
    case 0x41...0x46: return Int(scalar.value) - 0x41 + 10
    default: return nil
    }
  }

  /// Python's `int(text)`, or `nil` where Python raises `ValueError`.
  ///
  /// Python trims surrounding whitespace and accepts one sign, decimal digits of any script and
  /// single underscores between digits. A value beyond `Int` saturates. A caller that clamps, as
  /// `min(int(x), 256)` does, can't tell that from Python's arbitrary precision.
  static func pythonInt<S: Sequence>(_ text: S) -> Int? where S.Element == Unicode.Scalar {
    let scalars = trimmedNumberScalars(text)
    var index = 0
    var negative = false
    if index < scalars.count, scalars[index] == "+" || scalars[index] == "-" {
      negative = scalars[index] == "-"
      index += 1
    }
    guard let digits = pythonDigitRun(scalars, from: &index), index == scalars.count else {
      return nil
    }
    var result = 0
    for digit in digits {
      let (scaled, scaleOverflow) = result.multipliedReportingOverflow(by: 10)
      let (sum, sumOverflow) = scaled.addingReportingOverflow(digit)
      if scaleOverflow || sumOverflow { return negative ? Int.min : Int.max }
      result = sum
    }
    return negative ? -result : result
  }

  /// Python's `float(text)`, or `nil` where Python raises `ValueError`.
  ///
  /// Python trims surrounding whitespace and accepts one sign, digits with single underscores
  /// between them in the integer, fraction and exponent parts, `5.` and `.5`, and the words
  /// `inf`, `infinity` and `nan` in any case. It rejects a hexadecimal float, a `nan(1)` payload
  /// and a lone `.`.
  static func pythonFloat<S: Sequence>(_ text: S) -> Double? where S.Element == Unicode.Scalar {
    let scalars = trimmedNumberScalars(text)
    var index = 0
    var sign = 1.0
    if index < scalars.count, scalars[index] == "+" || scalars[index] == "-" {
      if scalars[index] == "-" { sign = -1.0 }
      index += 1
    }
    let word = String(
      String.UnicodeScalarView(
        scalars[index...].map { scalar in
          (0x41...0x5A).contains(scalar.value) ? Unicode.Scalar(UInt8(scalar.value + 0x20)) : scalar
        }))
    if word == "inf" || word == "infinity" { return sign * Double.infinity }
    if word == "nan" { return Double.nan }

    var integer: [Int] = []
    var fraction: [Int] = []
    var exponent: [Int] = []
    var exponentNegative = false
    if let run = pythonDigitRun(scalars, from: &index) { integer = run }
    if index < scalars.count, scalars[index] == "." {
      index += 1
      if let run = pythonDigitRun(scalars, from: &index) { fraction = run }
    }
    guard !integer.isEmpty || !fraction.isEmpty else { return nil }
    var hasExponent = false
    if index < scalars.count, scalars[index] == "e" || scalars[index] == "E" {
      hasExponent = true
      index += 1
      if index < scalars.count, scalars[index] == "+" || scalars[index] == "-" {
        exponentNegative = scalars[index] == "-"
        index += 1
      }
      guard let run = pythonDigitRun(scalars, from: &index) else { return nil }
      exponent = run
    }
    guard index == scalars.count else { return nil }
    // Swift reads the ASCII form of the same number, which it parses as IEEE 754 does.
    let ascii = { (digits: [Int]) in digits.map { String($0) }.joined() }
    let literal =
      (integer.isEmpty ? "0" : ascii(integer)) + "." + (fraction.isEmpty ? "0" : ascii(fraction))
      + (hasExponent ? "e" + (exponentNegative ? "-" : "") + ascii(exponent) : "")
    return Double(literal).map { sign * $0 }
  }

  /// The digit values of one run of digits and single underscores between digits, starting at
  /// `index`, or `nil` when the run is empty. `index` moves past the run.
  ///
  /// Python allows `1_0` and not `1__0`, `_1` or `1_`.
  private static func pythonDigitRun(_ scalars: [Unicode.Scalar], from index: inout Int) -> [Int]? {
    var digits: [Int] = []
    var cursor = index
    while cursor < scalars.count {
      let scalar = scalars[cursor]
      if let value = pythonDecimalDigit(scalar) {
        digits.append(value)
      } else {
        // An underscore needs a digit on each side.
        let joinsDigits =
          scalar == "_" && !digits.isEmpty && cursor + 1 < scalars.count
          && pythonDecimalDigit(scalars[cursor + 1]) != nil
        if !joinsDigits { break }
      }
      cursor += 1
    }
    guard !digits.isEmpty else { return nil }
    index = cursor
    return digits
  }

  /// Whether `int()` and `float()` strip the code point `value` from the ends of a string.
  ///
  /// CPython turns each non-ASCII `isspace()` code point into a space, then strips ASCII
  /// whitespace, which is U+0009 to U+000D and U+0020. `isPythonWhitespace` also accepts
  /// U+001C to U+001F, so it can't trim a number.
  private static func isPythonNumberSpace(_ value: UInt32) -> Bool {
    isPythonWhitespace(value) && !(0x1C...0x1F).contains(value)
  }

  private static func trimmedNumberScalars<S: Sequence>(_ text: S) -> [Unicode.Scalar]
  where S.Element == Unicode.Scalar {
    var scalars = Array(text)
    while let last = scalars.last, isPythonNumberSpace(last.value) { scalars.removeLast() }
    while let first = scalars.first, isPythonNumberSpace(first.value) { scalars.removeFirst() }
    return scalars
  }
}
