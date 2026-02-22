import Foundation

struct ProtoField {
    let number: Int
    let wireType: Int
    let value: Value

    enum Value {
        case varint(UInt64)
        case fixed64(UInt64)
        case lengthDelimited(Data)
        case fixed32(UInt32)
    }
}

struct ProtoReader {
    private let bytes: [UInt8]
    private var index: Int = 0

    init(data: Data) {
        bytes = Array(data)
    }

    mutating func nextField() -> ProtoField? {
        guard index < bytes.count, let key = readVarint() else { return nil }
        let wireType = Int(key & 0x7)
        let number = Int(key >> 3)
        switch wireType {
        case 0:
            guard let v = readVarint() else { return nil }
            return .init(number: number, wireType: wireType, value: .varint(v))
        case 1:
            guard let v = readFixed64() else { return nil }
            return .init(number: number, wireType: wireType, value: .fixed64(v))
        case 2:
            guard let d = readLengthDelimited() else { return nil }
            return .init(number: number, wireType: wireType, value: .lengthDelimited(d))
        case 5:
            guard let v = readFixed32() else { return nil }
            return .init(number: number, wireType: wireType, value: .fixed32(v))
        default:
            return nil
        }
    }

    private mutating func readVarint() -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < bytes.count {
            let b = bytes[index]
            index += 1
            result |= UInt64(b & 0x7f) << shift
            if (b & 0x80) == 0 { return result }
            shift += 7
            if shift >= 64 { return nil }
        }
        return nil
    }

    private mutating func readFixed64() -> UInt64? {
        guard index + 8 <= bytes.count else { return nil }
        defer { index += 8 }
        return bytes[index..<(index + 8)].enumerated().reduce(UInt64(0)) { partial, pair in
            partial | (UInt64(pair.element) << (8 * UInt64(pair.offset)))
        }
    }

    private mutating func readFixed32() -> UInt32? {
        guard index + 4 <= bytes.count else { return nil }
        defer { index += 4 }
        return bytes[index..<(index + 4)].enumerated().reduce(UInt32(0)) { partial, pair in
            partial | (UInt32(pair.element) << (8 * UInt32(pair.offset)))
        }
    }

    private mutating func readLengthDelimited() -> Data? {
        guard let len = readVarint() else { return nil }
        let count = Int(len)
        guard index + count <= bytes.count else { return nil }
        defer { index += count }
        return Data(bytes[index..<(index + count)])
    }
}

@inline(__always)
func floatFromBits(_ bits: UInt32) -> Float {
    Float(bitPattern: bits)
}

@inline(__always)
func doubleFromBits(_ bits: UInt64) -> Double {
    Double(bitPattern: bits)
}
