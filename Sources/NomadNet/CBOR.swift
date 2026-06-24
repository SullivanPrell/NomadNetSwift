import Foundation

// MARK: - CBOR

/// Minimal CBOR (RFC 7049) encoder and decoder for the types used by the RRC protocol.
///
/// Supported types:
/// - `uint`  — unsigned integer (0 … UInt64.max)
/// - `bytes` — byte string
/// - `text`  — UTF-8 text string
/// - `array` — heterogeneous array
/// - `map`   — ordered map of (Value, Value) pairs
/// - `bool`  — true / false
/// - `null`  — null
///
/// Corresponds to the `cbor_py` library used by NomadNet (`nomadnet/vendor/cbor.py`).
public enum CBOR {

    // MARK: – Value type

    public indirect enum Value: Equatable {
        case uint(UInt64)
        case int(Int64)     // negative integers
        case bytes(Data)
        case text(String)
        case array([Value])
        case map([(Value, Value)])
        case bool(Bool)
        case null

        // Convenience integer initialiser from Int
        public static func uint(_ n: Int) -> Value { .uint(UInt64(n)) }

        // Equatable conformance for map (ordered comparison)
        public static func == (lhs: Value, rhs: Value) -> Bool {
            switch (lhs, rhs) {
            case (.uint(let a),  .uint(let b)):  return a == b
            case (.int(let a),   .int(let b)):   return a == b
            case (.bytes(let a), .bytes(let b)): return a == b
            case (.text(let a),  .text(let b)):  return a == b
            case (.bool(let a),  .bool(let b)):  return a == b
            case (.null, .null):                 return true
            case (.array(let a), .array(let b)):
                return a == b
            case (.map(let a), .map(let b)):
                guard a.count == b.count else { return false }
                return zip(a, b).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
            default: return false
            }
        }
    }

    // MARK: – Errors

    public enum CBORError: Error {
        case unexpectedEndOfData
        case unsupportedType(UInt8)
        case invalidUTF8
        case trailingData
    }

    // MARK: – Encode

    /// Encode a `Value` to CBOR bytes.
    public static func encode(_ value: Value) -> Data {
        var out = Data()
        encode(value, into: &out)
        return out
    }

    private static func encode(_ value: Value, into out: inout Data) {
        switch value {
        case .uint(let n):
            writeHead(major: 0, value: n, into: &out)

        case .int(let n):
            if n >= 0 {
                writeHead(major: 0, value: UInt64(n), into: &out)
            } else {
                writeHead(major: 1, value: UInt64(-1 - n), into: &out)
            }

        case .bytes(let data):
            writeHead(major: 2, value: UInt64(data.count), into: &out)
            out.append(data)

        case .text(let str):
            let utf8 = Data(str.utf8)
            writeHead(major: 3, value: UInt64(utf8.count), into: &out)
            out.append(utf8)

        case .array(let items):
            writeHead(major: 4, value: UInt64(items.count), into: &out)
            for item in items { encode(item, into: &out) }

        case .map(let pairs):
            writeHead(major: 5, value: UInt64(pairs.count), into: &out)
            for (k, v) in pairs {
                encode(k, into: &out)
                encode(v, into: &out)
            }

        case .bool(let b):
            out.append(b ? 0xF5 : 0xF4)

        case .null:
            out.append(0xF6)
        }
    }

    // MARK: – Decode

    /// Decode CBOR bytes to a `Value`.
    /// - Throws: `CBORError` if the data is malformed or unsupported.
    public static func decode(_ data: Data) throws -> Value {
        var cursor = data.startIndex
        let value = try decode(data: data, cursor: &cursor)
        // Allow trailing zeros (some implementations add them) but not meaningful data
        while cursor < data.endIndex, data[cursor] == 0 { cursor = data.index(after: cursor) }
        return value
    }

    private static func decode(data: Data, cursor: inout Data.Index) throws -> Value {
        guard cursor < data.endIndex else { throw CBORError.unexpectedEndOfData }

        let byte = data[cursor]
        cursor = data.index(after: cursor)

        let major = byte >> 5
        let info  = byte & 0x1F

        switch major {
        case 0: // uint
            let n = try readUInt(info: info, data: data, cursor: &cursor)
            return .uint(n)

        case 1: // negint
            let n = try readUInt(info: info, data: data, cursor: &cursor)
            return .int(-1 - Int64(bitPattern: n))

        case 2: // byte string
            let len = try readUInt(info: info, data: data, cursor: &cursor)
            guard let end = data.index(cursor, offsetBy: Int(len), limitedBy: data.endIndex)
            else { throw CBORError.unexpectedEndOfData }
            let bytes = Data(data[cursor ..< end])
            cursor = end
            return .bytes(bytes)

        case 3: // text string
            let len = try readUInt(info: info, data: data, cursor: &cursor)
            guard let end = data.index(cursor, offsetBy: Int(len), limitedBy: data.endIndex)
            else { throw CBORError.unexpectedEndOfData }
            let utf8 = Data(data[cursor ..< end])
            cursor = end
            guard let str = String(data: utf8, encoding: .utf8) else { throw CBORError.invalidUTF8 }
            return .text(str)

        case 4: // array
            let count = try readUInt(info: info, data: data, cursor: &cursor)
            var items = [Value]()
            for _ in 0 ..< count {
                items.append(try decode(data: data, cursor: &cursor))
            }
            return .array(items)

        case 5: // map
            let count = try readUInt(info: info, data: data, cursor: &cursor)
            var pairs = [(Value, Value)]()
            for _ in 0 ..< count {
                let k = try decode(data: data, cursor: &cursor)
                let v = try decode(data: data, cursor: &cursor)
                pairs.append((k, v))
            }
            return .map(pairs)

        case 7: // float / bool / null / break
            switch info {
            case 20: return .bool(false)  // 0xF4
            case 21: return .bool(true)   // 0xF5
            case 22: return .null         // 0xF6
            default: throw CBORError.unsupportedType(byte)
            }

        default:
            throw CBORError.unsupportedType(byte)
        }
    }

    // MARK: – Private helpers

    private static func writeHead(major: UInt8, value: UInt64, into out: inout Data) {
        let mt = major << 5
        if value <= 23 {
            out.append(mt | UInt8(value))
        } else if value <= 0xFF {
            out.append(mt | 24)
            out.append(UInt8(value))
        } else if value <= 0xFFFF {
            out.append(mt | 25)
            out.append(UInt8(value >> 8))
            out.append(UInt8(value & 0xFF))
        } else if value <= 0xFFFF_FFFF {
            out.append(mt | 26)
            out.append(UInt8((value >> 24) & 0xFF))
            out.append(UInt8((value >> 16) & 0xFF))
            out.append(UInt8((value >>  8) & 0xFF))
            out.append(UInt8( value        & 0xFF))
        } else {
            out.append(mt | 27)
            out.append(UInt8((value >> 56) & 0xFF))
            out.append(UInt8((value >> 48) & 0xFF))
            out.append(UInt8((value >> 40) & 0xFF))
            out.append(UInt8((value >> 32) & 0xFF))
            out.append(UInt8((value >> 24) & 0xFF))
            out.append(UInt8((value >> 16) & 0xFF))
            out.append(UInt8((value >>  8) & 0xFF))
            out.append(UInt8( value        & 0xFF))
        }
    }

    // MARK: – Multi-item decode

    /// Decode every consecutive CBOR value in `data` and return them as an array.
    /// Used by history loading, where each log entry is an independently encoded CBOR item
    /// appended to a flat file (same layout as Python `cbor.encode` / `cbor.load` streams).
    public static func decodeAll(_ data: Data) throws -> [Value] {
        var results: [Value] = []
        var cursor = data.startIndex
        while cursor < data.endIndex {
            // Skip null-padding bytes that some encoders append
            while cursor < data.endIndex && data[cursor] == 0 {
                cursor = data.index(after: cursor)
            }
            if cursor >= data.endIndex { break }
            let value = try decode(data: data, cursor: &cursor)
            results.append(value)
        }
        return results
    }

    private static func readUInt(info: UInt8, data: Data, cursor: inout Data.Index) throws -> UInt64 {
        switch info {
        case 0...23:
            return UInt64(info)
        case 24:
            guard cursor < data.endIndex else { throw CBORError.unexpectedEndOfData }
            let v = UInt64(data[cursor]); cursor = data.index(after: cursor)
            return v
        case 25:
            guard let end = data.index(cursor, offsetBy: 2, limitedBy: data.endIndex)
            else { throw CBORError.unexpectedEndOfData }
            let v = (UInt64(data[cursor]) << 8) | UInt64(data[data.index(after: cursor)])
            cursor = end; return v
        case 26:
            guard let end = data.index(cursor, offsetBy: 4, limitedBy: data.endIndex)
            else { throw CBORError.unexpectedEndOfData }
            var v: UInt64 = 0
            for i in 0..<4 {
                v = (v << 8) | UInt64(data[data.index(cursor, offsetBy: i)])
            }
            cursor = end; return v
        case 27:
            guard let end = data.index(cursor, offsetBy: 8, limitedBy: data.endIndex)
            else { throw CBORError.unexpectedEndOfData }
            var v: UInt64 = 0
            for i in 0..<8 {
                v = (v << 8) | UInt64(data[data.index(cursor, offsetBy: i)])
            }
            cursor = end; return v
        default:
            throw CBORError.unsupportedType(info)
        }
    }
}
