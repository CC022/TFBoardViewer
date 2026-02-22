import Foundation

private struct TensorValue {
    var dtype: Int = 0
    var shape: [Int64] = []
    var floatVals: [Float] = []
    var doubleVals: [Double] = []
    var intVals: [Int64] = []
    var stringVals: [Data] = []
    var tensorContent: Data = .init()
}

private struct SummaryValue {
    var tag: String = ""
    var simpleValue: Double?
    var imageData: Data?
    var tensor: TensorValue?
    var pluginName: String?
}

private struct EventValue {
    var wallTime: TimeInterval = 0
    var step: Int64 = 0
    var values: [SummaryValue] = []
}

enum EventParser {
    static func parse(folderURL: URL) throws -> ParsedLog {
        var parsed = ParsedLog()
        let files = try collectEventFiles(in: folderURL)
        for file in files {
            try parseTFRecordFile(file) { event in
                absorb(event: event, into: &parsed)
            }
        }
        return parsed
    }

    private static func absorb(event: EventValue, into parsed: inout ParsedLog) {
        let date = Date(timeIntervalSince1970: event.wallTime)
        for value in event.values {
            guard !value.tag.isEmpty else { continue }

            if let s = value.simpleValue {
                parsed.pushScalar(tag: value.tag, step: event.step, wallTime: date, value: s)
                continue
            }

            if let image = value.imageData {
                parsed.pushImage(tag: value.tag, step: event.step, wallTime: date, data: image)
                continue
            }

            guard let tensor = value.tensor else { continue }

            if value.pluginName == "videos" {
                if let media = tensorMediaData(tensor) {
                    parsed.pushMedia(tag: value.tag, step: event.step, wallTime: date, data: media.0, kind: media.1)
                    continue
                }
                if let frames = tensorImageFrames(tensor), frames.count > 1 {
                    parsed.pushVideo(tag: value.tag, step: event.step, wallTime: date, frames: frames, fps: 8)
                    continue
                }
            }

            if let scalar = tensorScalar(tensor) {
                parsed.pushScalar(tag: value.tag, step: event.step, wallTime: date, value: scalar)
                continue
            }

            if let media = tensorMediaData(tensor) {
                parsed.pushMedia(tag: value.tag, step: event.step, wallTime: date, data: media.0, kind: media.1)
                continue
            }

            if let frames = tensorImageFrames(tensor), frames.count > 1 {
                parsed.pushVideo(tag: value.tag, step: event.step, wallTime: date, frames: frames, fps: 8)
                continue
            }

            if let d = tensorImageData(tensor) {
                parsed.pushImage(tag: value.tag, step: event.step, wallTime: date, data: d)
                continue
            }
        }
    }

    private static func tensorScalar(_ tensor: TensorValue) -> Double? {
        if let v = tensor.doubleVals.first { return v }
        if let v = tensor.floatVals.first { return Double(v) }
        if let v = tensor.intVals.first { return Double(v) }
        if tensor.tensorContent.count == 8 {
            let bits = tensor.tensorContent.prefix(8).enumerated().reduce(UInt64(0)) { acc, pair in
                acc | (UInt64(pair.element) << (UInt64(pair.offset) * 8))
            }
            return doubleFromBits(UInt64(littleEndian: bits))
        }
        if tensor.tensorContent.count == 4 {
            let bits = tensor.tensorContent.prefix(4).enumerated().reduce(UInt32(0)) { acc, pair in
                acc | (UInt32(pair.element) << (UInt32(pair.offset) * 8))
            }
            return Double(floatFromBits(UInt32(littleEndian: bits)))
        }
        return nil
    }

    private static func tensorImageData(_ tensor: TensorValue) -> Data? {
        for d in tensor.stringVals {
            if isImage(d) { return d }
        }
        if isImage(tensor.tensorContent) { return tensor.tensorContent }
        return nil
    }

    private static func tensorImageFrames(_ tensor: TensorValue) -> [Data]? {
        let frames = tensor.stringVals.filter { isImage($0) }
        return frames.isEmpty ? nil : frames
    }

    private static func tensorMediaData(_ tensor: TensorValue) -> (Data, MediaKind)? {
        for d in tensor.stringVals {
            let kind = detectMediaKind(d)
            if kind != .unknown { return (d, kind) }
        }
        let kind = detectMediaKind(tensor.tensorContent)
        if kind != .unknown { return (tensor.tensorContent, kind) }
        return nil
    }

    private static func collectEventFiles(in folder: URL) throws -> [URL] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey]
        let items = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)
        let files = items.filter {
            $0.lastPathComponent.contains("tfevents") && $0.pathExtension != "tmp"
        }
        if !files.isEmpty { return files.sorted { $0.lastPathComponent < $1.lastPathComponent } }

        return items.filter { url in
            (try? url.resourceValues(forKeys: Set(keys)).isDirectory) == true
        }
        .flatMap { dir in
            (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        }
        .filter { $0.lastPathComponent.contains("tfevents") }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func parseTFRecordFile(_ fileURL: URL, onEvent: (EventValue) -> Void) throws {
        let data = try Data(contentsOf: fileURL)
        var i = 0
        while i + 16 <= data.count {
            let length = readLEUInt64(from: data, at: i)
            i += 8
            i += 4
            let payloadLen = Int(length)
            guard i + payloadLen + 4 <= data.count else { break }
            let payload = data.subdata(in: i..<(i + payloadLen))
            i += payloadLen
            i += 4

            if let event = parseEvent(payload) {
                onEvent(event)
            }
        }
    }

    private static func parseEvent(_ data: Data) -> EventValue? {
        var reader = ProtoReader(data: data)
        var event = EventValue()
        while let f = reader.nextField() {
            switch (f.number, f.value) {
            case (1, .fixed64(let bits)):
                event.wallTime = doubleFromBits(bits)
            case (2, .varint(let v)):
                event.step = Int64(bitPattern: v)
            case (5, .lengthDelimited(let summaryData)):
                event.values = parseSummary(summaryData)
            default:
                continue
            }
        }
        return event.values.isEmpty ? nil : event
    }

    private static func parseSummary(_ data: Data) -> [SummaryValue] {
        var reader = ProtoReader(data: data)
        var out: [SummaryValue] = []
        while let f = reader.nextField() {
            if case (1, .lengthDelimited(let valueData)) = (f.number, f.value),
               let v = parseSummaryValue(valueData) {
                out.append(v)
            }
        }
        return out
    }

    private static func parseSummaryValue(_ data: Data) -> SummaryValue? {
        var reader = ProtoReader(data: data)
        var value = SummaryValue()
        while let f = reader.nextField() {
            switch (f.number, f.value) {
            case (1, .lengthDelimited(let d)):
                value.tag = String(data: d, encoding: .utf8) ?? ""
            case (2, .fixed32(let bits)):
                value.simpleValue = Double(floatFromBits(bits))
            case (4, .lengthDelimited(let imageData)):
                value.imageData = parseImage(imageData)
            case (8, .lengthDelimited(let tensorData)):
                value.tensor = parseTensor(tensorData)
            case (9, .lengthDelimited(let metadata)):
                value.pluginName = parsePluginName(metadata)
            default:
                continue
            }
        }
        return value.tag.isEmpty ? nil : value
    }

    private static func parseImage(_ data: Data) -> Data? {
        var reader = ProtoReader(data: data)
        while let f = reader.nextField() {
            if case (4, .lengthDelimited(let encoded)) = (f.number, f.value) {
                return encoded
            }
        }
        return nil
    }

    private static func parsePluginName(_ data: Data) -> String? {
        var reader = ProtoReader(data: data)
        while let f = reader.nextField() {
            if case (1, .lengthDelimited(let pluginData)) = (f.number, f.value) {
                var pluginReader = ProtoReader(data: pluginData)
                while let p = pluginReader.nextField() {
                    if case (1, .lengthDelimited(let nameData)) = (p.number, p.value) {
                        return String(data: nameData, encoding: .utf8)
                    }
                }
            }
        }
        return nil
    }

    private static func parseTensor(_ data: Data) -> TensorValue {
        var reader = ProtoReader(data: data)
        var t = TensorValue()
        while let f = reader.nextField() {
            switch (f.number, f.value) {
            case (1, .varint(let v)):
                t.dtype = Int(v)
            case (2, .lengthDelimited(let d)):
                t.shape = parseShape(d)
            case (4, .lengthDelimited(let d)):
                t.tensorContent = d
            case (5, .fixed32(let bits)):
                t.floatVals.append(floatFromBits(bits))
            case (6, .fixed64(let bits)):
                t.doubleVals.append(doubleFromBits(bits))
            case (7, .varint(let v)):
                t.intVals.append(Int64(bitPattern: v))
            case (8, .lengthDelimited(let d)):
                t.stringVals.append(d)
            default:
                continue
            }
        }
        return t
    }

    private static func parseShape(_ data: Data) -> [Int64] {
        var reader = ProtoReader(data: data)
        var shape: [Int64] = []
        while let f = reader.nextField() {
            if case (2, .lengthDelimited(let dimData)) = (f.number, f.value) {
                var dimReader = ProtoReader(data: dimData)
                while let df = dimReader.nextField() {
                    if case (1, .varint(let v)) = (df.number, df.value) {
                        shape.append(Int64(bitPattern: v))
                    }
                }
            }
        }
        return shape
    }

    private static func readLEUInt64(from data: Data, at i: Int) -> UInt64 {
        data[i..<(i + 8)].enumerated().reduce(UInt64(0)) { partial, pair in
            partial | (UInt64(pair.element) << (UInt64(pair.offset) * 8))
        }
    }

    private static func isImage(_ data: Data) -> Bool {
        data.starts(with: [0x89, 0x50, 0x4E, 0x47]) ||
        data.starts(with: [0xFF, 0xD8, 0xFF]) ||
        data.starts(with: [0x47, 0x49, 0x46, 0x38])
    }
}

func detectMediaKind(_ data: Data) -> MediaKind {
    if data.starts(with: [0x47, 0x49, 0x46, 0x38]) { return .gif }
    if data.count > 12 {
        let header = data.subdata(in: 4..<12)
        if String(data: header, encoding: .ascii)?.contains("ftyp") == true { return .mp4 }
    }
    return .unknown
}
