import Foundation

struct ScalarPoint: Identifiable, Hashable {
    let id = UUID()
    let step: Int64
    let wallTime: Date
    let value: Double
}

struct ImageFrame: Identifiable, Hashable {
    let id = UUID()
    let step: Int64
    let wallTime: Date
    let data: Data
}

enum MediaKind: Hashable {
    case gif
    case mp4
    case unknown
}

struct MediaFrame: Identifiable, Hashable {
    let id = UUID()
    let step: Int64
    let wallTime: Date
    let data: Data
    let kind: MediaKind
}

struct VideoSequence: Identifiable, Hashable {
    let id = UUID()
    let step: Int64
    let wallTime: Date
    let frames: [Data]
    let fps: Double
}

struct TagBundle: Identifiable {
    let id = UUID()
    let tag: String
    var scalars: [ScalarPoint] = []
    var images: [ImageFrame] = []
    var media: [MediaFrame] = []
    var videos: [VideoSequence] = []
}

struct ParsedLog {
    var bundlesByTag: [String: TagBundle] = [:]

    mutating func pushScalar(tag: String, step: Int64, wallTime: Date, value: Double) {
        var bundle = bundlesByTag[tag] ?? TagBundle(tag: tag)
        bundle.scalars.append(.init(step: step, wallTime: wallTime, value: value))
        bundlesByTag[tag] = bundle
    }

    mutating func pushImage(tag: String, step: Int64, wallTime: Date, data: Data) {
        var bundle = bundlesByTag[tag] ?? TagBundle(tag: tag)
        bundle.images.append(.init(step: step, wallTime: wallTime, data: data))
        bundlesByTag[tag] = bundle
    }

    mutating func pushMedia(tag: String, step: Int64, wallTime: Date, data: Data, kind: MediaKind) {
        var bundle = bundlesByTag[tag] ?? TagBundle(tag: tag)
        bundle.media.append(.init(step: step, wallTime: wallTime, data: data, kind: kind))
        bundlesByTag[tag] = bundle
    }

    mutating func pushVideo(tag: String, step: Int64, wallTime: Date, frames: [Data], fps: Double) {
        var bundle = bundlesByTag[tag] ?? TagBundle(tag: tag)
        bundle.videos.append(.init(step: step, wallTime: wallTime, frames: frames, fps: fps))
        bundlesByTag[tag] = bundle
    }

    var sortedBundles: [TagBundle] {
        bundlesByTag.values
            .map {
                var copy = $0
                copy.scalars.sort { $0.step < $1.step }
                copy.images.sort { $0.step < $1.step }
                copy.media.sort { $0.step < $1.step }
                copy.videos.sort { $0.step < $1.step }
                return copy
            }
            .sorted { $0.tag < $1.tag }
    }
}
