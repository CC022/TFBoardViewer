import AppKit
import AVKit
import Charts
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            List(selection: $state.selectedTag) {
                if let folder = state.loadedFolderName {
                    Section("Run") {
                        Label(folder, systemImage: "folder")
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                }

                Section("Tags") {
                    ForEach(state.parsed.sortedBundles) { bundle in
                        SidebarRow(bundle: bundle)
                            .tag(bundle.tag)
                    }
                }
            }
            .navigationTitle("TFBoardViewer")
        } detail: {
            Group {
                if state.isLoading {
                    ProgressView("Loading tfevents…")
                } else if let error = state.error {
                    ContentUnavailableView("Parse failed", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if let bundle = state.parsed.bundlesByTag[state.selectedTag ?? ""] {
                    TagDetail(bundle: bundle, folderName: state.loadedFolderName)
                } else {
                    DropHintView(onSelectFolder: pickFolder)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(16)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Open Folder…", systemImage: "folder.badge.plus") {
                    pickFolder()
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose a TensorBoard log folder"
        if panel.runModal() == .OK, let url = panel.url {
            state.loadFolder(url)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard
                let data = item as? Data,
                let url = NSURL(absoluteURLWithDataRepresentation: data, relativeTo: nil) as URL?
            else { return }
            Task { @MainActor in
                state.loadFolder(url)
            }
        }
        return true
    }
}

private struct SidebarRow: View {
    let bundle: TagBundle

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(bundle.tag)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        if bundle.scalars.count == 1 && bundle.images.isEmpty && bundle.media.isEmpty && bundle.videos.isEmpty,
           let one = bundle.scalars.first {
            return one.value.formatted(.number.precision(.fractionLength(3)))
        }
        return "\(bundle.scalars.count)s • \(bundle.images.count)i • \(bundle.media.count + bundle.videos.count)v"
    }

    private var icon: String {
        if !bundle.scalars.isEmpty { return "gauge.with.dots.needle.67percent" }
        if !bundle.videos.isEmpty || !bundle.media.isEmpty { return "video" }
        if !bundle.images.isEmpty { return "photo" }
        return "doc.text"
    }
}

private struct DropHintView: View {
    let onSelectFolder: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "Drop a tfevents folder",
                systemImage: "tray.and.arrow.down",
                description: Text("Drag a run directory from TensorBoard logs.")
            )
            Button("Select Folder…", action: onSelectFolder)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TagDetail: View {
    let bundle: TagBundle
    let folderName: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerCard

                if !bundle.scalars.isEmpty {
                    ScalarChartCard(tag: bundle.tag, points: bundle.scalars)
                        .id(scalarSeriesIdentity(tag: bundle.tag, points: bundle.scalars))
                }

                if !bundle.images.isEmpty {
                    GroupBox("Images") {
                        LazyVGrid(columns: [.init(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                            ForEach(bundle.images) { frame in
                                VStack(alignment: .leading, spacing: 6) {
                                    if let nsImage = NSImage(data: frame.data) {
                                        Image(nsImage: nsImage)
                                            .resizable()
                                            .scaledToFit()
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .frame(maxWidth: .infinity)
                                    }
                                    Text("step \(frame.step)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if !bundle.videos.isEmpty {
                    GroupBox("Video (Frame Sequence)") {
                        VStack(spacing: 16) {
                            ForEach(bundle.videos) { video in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("step \(video.step) • \(video.frames.count) frames")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    FramePlayerView(video: video)
                                }
                            }
                        }
                    }
                }

                if !bundle.media.isEmpty {
                    GroupBox("Video / GIF") {
                        VStack(spacing: 16) {
                            ForEach(bundle.media) { frame in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("step \(frame.step)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    if frame.kind == .gif {
                                        GIFPlayerView(data: frame.data)
                                    } else {
                                        MediaPlayerView(frame: frame)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(2)
        }
        .navigationTitle(bundle.tag)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(bundle.tag)
                .font(.title2.bold())
            if let folderName {
                Text(folderName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("\(bundle.scalars.count) scalars • \(bundle.images.count) images • \(bundle.media.count + bundle.videos.count) videos")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func scalarSeriesIdentity(tag: String, points: [ScalarPoint]) -> Int {
        var hasher = Hasher()
        hasher.combine(tag)
        hasher.combine(points.count)
        for point in points {
            hasher.combine(point.step)
            hasher.combine(point.value.bitPattern)
        }
        return hasher.finalize()
    }
}

private struct ScalarChartCard: View {
    let tag: String
    let points: [ScalarPoint]
    @State private var chartPoints: [ScalarPoint] = []
    @State private var hovered: ScalarPoint?
    @State private var lastHoverUpdate: TimeInterval = 0

    private static let maxVisiblePoints = 1000
    private static let hoverMinInterval: TimeInterval = 1.0 / 60.0

    init(tag: String, points: [ScalarPoint]) {
        self.tag = tag
        self.points = points
        _chartPoints = State(initialValue: Self.downsample(points))
    }

    var body: some View {
        let visiblePoints = chartPoints.isEmpty ? points : chartPoints

        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Scalars")
                        .font(.headline)
                    Spacer()
                    Button("Copy TSV", systemImage: "doc.on.doc") {
                        copyScalarsTSV(tag: tag, scalars: points)
                    }
                    .buttonStyle(.bordered)
                }

                Chart {
                    ForEach(visiblePoints) { point in
                        LineMark(
                            x: .value("Step", point.step),
                            y: .value("Value", point.value)
                        )
                        .interpolationMethod(.linear)
                    }

                    if let hovered {
                        RuleMark(x: .value("Selected", hovered.step))
                            .foregroundStyle(.gray.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                        PointMark(
                            x: .value("Step", hovered.step),
                            y: .value("Value", hovered.value)
                        )
                        .symbolSize(90)
                        .foregroundStyle(.pink)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 8))
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        let plotFrame = proxy.plotFrame.map { geo[$0] }
                        ZStack(alignment: .topLeading) {
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(let location):
                                        guard let frame = plotFrame else {
                                            hovered = nil
                                            return
                                        }
                                        let xInPlot = location.x - frame.minX
                                        guard xInPlot >= 0, xInPlot <= proxy.plotSize.width else {
                                            hovered = nil
                                            return
                                        }
                                        guard let stepValue: Double = proxy.value(atX: xInPlot) else {
                                            hovered = nil
                                            return
                                        }
                                        let now = Date.timeIntervalSinceReferenceDate
                                        guard now - lastHoverUpdate >= Self.hoverMinInterval else { return }
                                        lastHoverUpdate = now
                                        let targetStep = Int64(stepValue.rounded())
                                        let nearest = nearestPoint(step: targetStep, in: visiblePoints)
                                        if hovered?.step != nearest?.step {
                                            hovered = nearest
                                        }
                                    case .ended:
                                        hovered = nil
                                    }
                                }

                            if let hovered, let frame = plotFrame,
                               let markerX = proxy.position(forX: hovered.step),
                               let markerY = proxy.position(forY: hovered.value) {
                                HoverValueBadge(point: hovered)
                                    .position(
                                        x: min(max(frame.minX + markerX + 56, 64), geo.size.width - 64),
                                        y: max(frame.minY + markerY - 42, 20)
                                    )
                            }
                        }
                    }
                }
                .frame(height: 320)
            }
        }
    }

    private func nearestPoint(step: Int64, in data: [ScalarPoint]) -> ScalarPoint? {
        guard !data.isEmpty else { return nil }
        if step <= data[0].step { return data[0] }
        if step >= data[data.count - 1].step { return data[data.count - 1] }

        var low = 0
        var high = data.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let midStep = data[mid].step
            if midStep == step {
                return data[mid]
            } else if midStep < step {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        let rightIndex = min(low, data.count - 1)
        let leftIndex = max(0, rightIndex - 1)
        let left = data[leftIndex]
        let right = data[rightIndex]
        return abs(left.step - step) <= abs(right.step - step) ? left : right
    }

    private func copyScalarsTSV(tag: String, scalars: [ScalarPoint]) {
        let valueColumn = sanitizedTSVField(tag)
        var tsv = "wall_time\tstep\t\(valueColumn)\n"
        let formatter = ISO8601DateFormatter()
        for s in scalars {
            let ts = formatter.string(from: s.wallTime)
            tsv += "\(ts)\t\(s.step)\t\(String(format: "%.3f", s.value))\n"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(tsv, forType: .string)
    }

    private func sanitizedTSVField(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private static func downsample(_ points: [ScalarPoint]) -> [ScalarPoint] {
        guard points.count > maxVisiblePoints else { return points }

        let sorted = points.sorted { $0.step < $1.step }
        let lastIndex = sorted.count - 1
        let step = Double(lastIndex) / Double(maxVisiblePoints - 1)
        var sampled: [ScalarPoint] = []
        sampled.reserveCapacity(maxVisiblePoints)

        var previousIndex = -1
        for i in 0..<maxVisiblePoints {
            let index = min(lastIndex, Int((Double(i) * step).rounded()))
            if index != previousIndex {
                sampled.append(sorted[index])
                previousIndex = index
            }
        }

        if sampled.last?.step != sorted[lastIndex].step {
            sampled.append(sorted[lastIndex])
        }
        return sampled
    }
}

private struct HoverValueBadge: View {
    let point: ScalarPoint

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(point.value.formatted(.number.precision(.fractionLength(4))))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
            Text("Step \(point.step)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 6)
    }
}

private struct GIFPlayerView: View {
    let data: Data
    @State private var frames: [NSImage] = []
    @State private var delays: [Double] = []
    @State private var frameIndex = 0
    @State private var isPlaying = true

    var body: some View {
        VStack(spacing: 10) {
            if let frame = currentFrame {
                Image(nsImage: frame)
                    .resizable()
                    .scaledToFit()
                    .frame(minHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                ContentUnavailableView("Unsupported GIF", systemImage: "video.slash")
                    .frame(minHeight: 280)
            }

            playerControls
        }
        .task {
            (frames, delays) = decodeGIF(data: data)
            frameIndex = 0
        }
        .task(id: isPlaying) {
            guard isPlaying, !frames.isEmpty else { return }
            while isPlaying {
                let delay = max(0.02, delays.indices.contains(frameIndex) ? delays[frameIndex] : 0.1)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard isPlaying, !frames.isEmpty else { break }
                frameIndex = (frameIndex + 1) % frames.count
            }
        }
    }

    private var currentFrame: NSImage? {
        guard frames.indices.contains(frameIndex) else { return nil }
        return frames[frameIndex]
    }

    private var playerControls: some View {
        HStack {
            Button(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill") {
                isPlaying.toggle()
            }
            .buttonStyle(.bordered)

            Button("Copy Frame", systemImage: "doc.on.doc") {
                if let frame = currentFrame { copyImageToPasteboard(frame) }
            }
            .buttonStyle(.bordered)
            .disabled(currentFrame == nil)

            if frames.count > 1 {
                Slider(
                    value: Binding(
                        get: { Double(frameIndex) },
                        set: { frameIndex = Int($0) }
                    ),
                    in: 0...Double(frames.count - 1),
                    step: 1
                )
            } else {
                Slider(value: .constant(0), in: 0...1)
                    .disabled(true)
            }

            Text("\(frameIndex + 1)/\(max(1, frames.count))")
                .monospacedDigit()
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct FramePlayerView: View {
    let video: VideoSequence
    @State private var frameIndex = 0
    @State private var isPlaying = true

    var body: some View {
        VStack(spacing: 10) {
            if let current = currentImage {
                Image(nsImage: current)
                    .resizable()
                    .scaledToFit()
                    .frame(minHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                ContentUnavailableView("No frames", systemImage: "video.slash")
                    .frame(minHeight: 280)
            }

            HStack {
                Button(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill") {
                    isPlaying.toggle()
                }
                .buttonStyle(.bordered)

                Button("Copy Frame", systemImage: "doc.on.doc") {
                    if let frame = currentImage { copyImageToPasteboard(frame) }
                }
                .buttonStyle(.bordered)
                .disabled(currentImage == nil)

                if video.frames.count > 1 {
                    Slider(
                        value: Binding(
                            get: { Double(frameIndex) },
                            set: { frameIndex = Int($0) }
                        ),
                        in: 0...Double(video.frames.count - 1),
                        step: 1
                    )
                } else {
                    Slider(value: .constant(0), in: 0...1)
                        .disabled(true)
                }

                Text("\(frameIndex + 1)/\(max(1, video.frames.count))")
                    .monospacedDigit()
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: isPlaying) {
            guard isPlaying, video.frames.count > 1 else { return }
            let fps = max(1, video.fps)
            let nanos = UInt64(1_000_000_000 / fps)
            while isPlaying {
                try? await Task.sleep(nanoseconds: nanos)
                guard isPlaying else { break }
                frameIndex = (frameIndex + 1) % video.frames.count
            }
        }
    }

    private var currentImage: NSImage? {
        guard video.frames.indices.contains(frameIndex) else { return nil }
        return NSImage(data: video.frames[frameIndex])
    }
}

private struct MediaPlayerView: View {
    let frame: MediaFrame

    var body: some View {
        if let url = writeTempMedia(frame) {
            VideoPlayer(player: AVPlayer(url: url))
                .frame(minHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            ContentUnavailableView("Unsupported media", systemImage: "video.slash")
        }
    }

    private func writeTempMedia(_ frame: MediaFrame) -> URL? {
        let ext = frame.kind == .gif ? "gif" : frame.kind == .mp4 ? "mp4" : "bin"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tb_\(UUID().uuidString).\(ext)")
        do {
            try frame.data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

private func decodeGIF(data: Data) -> ([NSImage], [Double]) {
    guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return ([], []) }
    let count = CGImageSourceGetCount(src)
    guard count > 0 else { return ([], []) }

    var images: [NSImage] = []
    var delays: [Double] = []
    images.reserveCapacity(count)
    delays.reserveCapacity(count)

    for i in 0..<count {
        guard let cg = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
        images.append(NSImage(cgImage: cg, size: .zero))

        let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
        let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let unclamped = gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        let clamped = gif?[kCGImagePropertyGIFDelayTime] as? Double
        delays.append(max(0.02, unclamped ?? clamped ?? 0.1))
    }
    return (images, delays)
}

private func copyImageToPasteboard(_ image: NSImage) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects([image])
}
