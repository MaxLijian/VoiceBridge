import Foundation

// MARK: - 最小化 Protobuf 编解码，仅支持飞书 WebSocket 的 Frame 和 Header

struct PBHeader {
    var key: String = ""
    var value: String = ""
}

struct PBFrame {
    var seqID: UInt64 = 0
    var logID: UInt64 = 0
    var service: Int32 = 0
    var method: Int32 = 0
    var headers: [PBHeader] = []
    var payloadEncoding: String = ""
    var payloadType: String = ""
    var payload: Data = Data()
    var logIDNew: String = ""

    func headerValue(for key: String) -> String? {
        headers.first(where: { $0.key == key })?.value
    }
}

// MARK: - Decoder

enum PBDecoder {

    static func decodeFrame(from data: Data) throws -> PBFrame {
        var frame = PBFrame()
        var offset = 0

        while offset < data.count {
            let (tag, newOffset) = try readVarint(data, offset: offset)
            offset = newOffset

            let fieldNumber = Int(tag >> 3)
            let wireType = Int(tag & 0x07)

            switch fieldNumber {
            case 1: // seq_id (varint)
                let (val, o) = try readVarint(data, offset: offset)
                frame.seqID = val
                offset = o
            case 2: // log_id (varint)
                let (val, o) = try readVarint(data, offset: offset)
                frame.logID = val
                offset = o
            case 3: // service (varint)
                let (val, o) = try readVarint(data, offset: offset)
                frame.service = Int32(val)
                offset = o
            case 4: // method (varint)
                let (val, o) = try readVarint(data, offset: offset)
                frame.method = Int32(val)
                offset = o
            case 5: // headers (length-delimited, repeated)
                let (bytes, o) = try readLengthDelimited(data, offset: offset)
                frame.headers.append(try decodeHeader(from: bytes))
                offset = o
            case 6: // payload_encoding (length-delimited)
                let (bytes, o) = try readLengthDelimited(data, offset: offset)
                frame.payloadEncoding = String(data: bytes, encoding: .utf8) ?? ""
                offset = o
            case 7: // payload_type (length-delimited)
                let (bytes, o) = try readLengthDelimited(data, offset: offset)
                frame.payloadType = String(data: bytes, encoding: .utf8) ?? ""
                offset = o
            case 8: // payload (length-delimited)
                let (bytes, o) = try readLengthDelimited(data, offset: offset)
                frame.payload = bytes
                offset = o
            case 9: // log_id_new (length-delimited)
                let (bytes, o) = try readLengthDelimited(data, offset: offset)
                frame.logIDNew = String(data: bytes, encoding: .utf8) ?? ""
                offset = o
            default:
                offset = try skipField(data, offset: offset, wireType: wireType)
            }
        }

        return frame
    }

    private static func decodeHeader(from data: Data) throws -> PBHeader {
        var header = PBHeader()
        var offset = 0

        while offset < data.count {
            let (tag, newOffset) = try readVarint(data, offset: offset)
            offset = newOffset

            let fieldNumber = Int(tag >> 3)
            let wireType = Int(tag & 0x07)

            switch fieldNumber {
            case 1: // key
                let (bytes, o) = try readLengthDelimited(data, offset: offset)
                header.key = String(data: bytes, encoding: .utf8) ?? ""
                offset = o
            case 2: // value
                let (bytes, o) = try readLengthDelimited(data, offset: offset)
                header.value = String(data: bytes, encoding: .utf8) ?? ""
                offset = o
            default:
                offset = try skipField(data, offset: offset, wireType: wireType)
            }
        }

        return header
    }

    private static func readVarint(_ data: Data, offset: Int) throws -> (UInt64, Int) {
        var result: UInt64 = 0
        var shift = 0
        var pos = offset

        while pos < data.count {
            let byte = data[pos]
            result |= UInt64(byte & 0x7F) << shift
            pos += 1
            if byte & 0x80 == 0 { return (result, pos) }
            shift += 7
            if shift >= 64 { throw PBError.malformedVarint }
        }

        throw PBError.unexpectedEnd
    }

    private static func readLengthDelimited(_ data: Data, offset: Int) throws -> (Data, Int) {
        let (length, pos) = try readVarint(data, offset: offset)
        let len = Int(length)
        guard pos + len <= data.count else { throw PBError.unexpectedEnd }
        return (Data(data[pos..<(pos + len)]), pos + len)
    }

    private static func skipField(_ data: Data, offset: Int, wireType: Int) throws -> Int {
        switch wireType {
        case 0: // varint
            let (_, o) = try readVarint(data, offset: offset)
            return o
        case 1: // 64-bit
            return offset + 8
        case 2: // length-delimited
            let (_, o) = try readLengthDelimited(data, offset: offset)
            return o
        case 5: // 32-bit
            return offset + 4
        default:
            throw PBError.unknownWireType(wireType)
        }
    }
}

// MARK: - Encoder

enum PBEncoder {

    static func encodeFrame(_ frame: PBFrame) -> Data {
        var data = Data()

        if frame.seqID != 0 { appendVarintField(&data, fieldNumber: 1, value: frame.seqID) }
        if frame.logID != 0 { appendVarintField(&data, fieldNumber: 2, value: frame.logID) }
        if frame.service != 0 { appendVarintField(&data, fieldNumber: 3, value: UInt64(bitPattern: Int64(frame.service))) }
        appendVarintField(&data, fieldNumber: 4, value: UInt64(bitPattern: Int64(frame.method)))

        for header in frame.headers {
            let headerData = encodeHeader(header)
            appendLengthDelimitedField(&data, fieldNumber: 5, bytes: headerData)
        }

        if !frame.payloadEncoding.isEmpty {
            appendLengthDelimitedField(&data, fieldNumber: 6, bytes: Data(frame.payloadEncoding.utf8))
        }
        if !frame.payloadType.isEmpty {
            appendLengthDelimitedField(&data, fieldNumber: 7, bytes: Data(frame.payloadType.utf8))
        }
        if !frame.payload.isEmpty {
            appendLengthDelimitedField(&data, fieldNumber: 8, bytes: frame.payload)
        }
        if !frame.logIDNew.isEmpty {
            appendLengthDelimitedField(&data, fieldNumber: 9, bytes: Data(frame.logIDNew.utf8))
        }

        return data
    }

    private static func encodeHeader(_ header: PBHeader) -> Data {
        var data = Data()
        if !header.key.isEmpty {
            appendLengthDelimitedField(&data, fieldNumber: 1, bytes: Data(header.key.utf8))
        }
        if !header.value.isEmpty {
            appendLengthDelimitedField(&data, fieldNumber: 2, bytes: Data(header.value.utf8))
        }
        return data
    }

    private static func appendVarintField(_ data: inout Data, fieldNumber: Int, value: UInt64) {
        let tag = UInt64(fieldNumber << 3 | 0) // wire type 0
        appendVarint(&data, tag)
        appendVarint(&data, value)
    }

    private static func appendLengthDelimitedField(_ data: inout Data, fieldNumber: Int, bytes: Data) {
        let tag = UInt64(fieldNumber << 3 | 2) // wire type 2
        appendVarint(&data, tag)
        appendVarint(&data, UInt64(bytes.count))
        data.append(bytes)
    }

    private static func appendVarint(_ data: inout Data, _ value: UInt64) {
        var v = value
        while v > 0x7F {
            data.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        data.append(UInt8(v))
    }
}

// MARK: - Errors

enum PBError: Error {
    case malformedVarint
    case unexpectedEnd
    case unknownWireType(Int)
}
