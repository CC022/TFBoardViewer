import AppKit
import AVKit
import Charts
import SwiftUI
import UniformTypeIdentifiers

private enum PreviewSelection: Identifiable {
    case media(MediaFrame)
    case video(VideoSequence)

    var id: UUID {
        switch self {
        case .media(let m): return m.id
        case .video(let v): return v.id
        }
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            List(selection: $state.selectedTag) {
                ForEach(state.parsed.sortedBundles) { bundle in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bundle.tag)
                            .lineLimit(1)
                        Text(sidebarDetail(bundle))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(bundle.tag)
                }
            }
            .navigationTitle("Tags")
        } detail: {
            Group {
                if state.isLoading {
                    ProgressView("Loading tfevents…")
                } else if let error = state.error {
                    ContentUnavailableView("Parse failed", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if let bundle = state.parsed.bundlesByTag[state.selectedTag ?? ""] {
                    TagDetail(bundle: bundle)
                } else {
                    DropHintView(onSelectFolder: pickFolder)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Open Folder…", systemImage: "folder") {
                    pickFolder()
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private func sidebarDetail(_ b: TagBundle) -> String {
        if b.scalars.count == 1 && b.images.isEmpty && b.media.isEmpty && b.videos.isEmpty,
           let one = b.scalars.first {
            return one.value.formatted(.number.precision(.fractionLength(0...6)))
        }
        return "\(b.scalars.count) scalars • \(b.images.count) images • \(b.media.count + b.videos.count) videos"
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
        }
    }
}

private struct TagDetail: View {
    let bundle: TagBundle
    @State private var selectedPreview: PreviewSelection?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !bundle.scalars.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Scalars")
                                    .font(.headline)
                                Spacer()
                                Button("Copy CSV", systemImage: "doc.on.doc") {
                                    copyScalarsCSV(bundle.scalars)
                                }
                                .buttonStyle(.bordered)
                            }
                            Chart(bundle.scalars) { point in
                                LineMark(
                                    x: .value("Step", point.step),
                                    y: .value("Value", point.value)
                                )
                                PointMark(
                                    x: .value("Step", point.step),
                                    y: .value("Value", point.value)
                                )
                                .opacity(0.35)
                            }
                            .frame(height: 260)
                        }
                    }
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
                        ForEach(bundle.videos) { video in
                            Button("Play step \(video.step) (\(video.frames.count) frames)") {
                                selectedPreview = .video(video)
                            }
                            .buttonStyle(.link)
                        }
                    }
                }

                if !bundle.media.isEmpty {
                    GroupBox("Video / GIF") {
                        ForEach(bundle.media) { frame in
                            Button("Open step \(frame.step)") {
                                selectedPreview = .media(frame)
                            }
                            .buttonStyle(.link)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(bundle.tag)
        .sheet(item: $selectedPreview) { preview in
            switch preview {
            case .media(let media):
                MediaPlayerSheet(frame: media)
            case .video(let video):
                FramePlayerSheet(video: video)
            }
        }
    }

    private func copyScalarsCSV(_ scalars: [ScalarPoint]) {
        var csv = "step,wall_time,value\n"
        let formatter = ISO8601DateFormatter()
        for s in scalars {
            let ts = formatter.string(from: s.wallTime)
            csv += "\(s.step),\(ts),\(s.value)\n"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(csv, forType: .string)
    }
}

private struct FramePlayerSheet: View {
    let video: VideoSequence
    @State private var frameIndex = 0
    @State private var isPlaying = true

    var body: some View {
        VStack(spacing: 12) {
            if let current = currentImage {
                Image(nsImage: current)
                    .resizable()
                    .scaledToFit()
                    .frame(minWidth: 640, minHeight: 380)
            } else {
                ContentUnavailableView("No frames", systemImage: "video.slash")
                    .frame(minWidth: 640, minHeight: 380)
            }

            HStack {
                Button(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill") {
                    isPlaying.toggle()
                }
                .buttonStyle(.bordered)

                Slider(
                    value: Binding(
                        get: { Double(frameIndex) },
                        set: { frameIndex = Int($0) }
                    ),
                    in: 0...Double(max(0, video.frames.count - 1)),
                    step: 1
                )

                Text("\(frameIndex + 1)/\(max(1, video.frames.count))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
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

private struct MediaPlayerSheet: View {
    let frame: MediaFrame

    var body: some View {
        if let url = writeTempMedia(frame) {
            VideoPlayer(player: AVPlayer(url: url))
                .frame(minWidth: 600, minHeight: 380)
                .padding()
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
