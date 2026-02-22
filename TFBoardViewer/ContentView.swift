import AppKit
import AVKit
import Charts
import SwiftUI
import UniformTypeIdentifiers

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
                        Text(summary(bundle))
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
                    DropHintView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private func summary(_ b: TagBundle) -> String {
        "\(b.scalars.count) scalars • \(b.images.count) images • \(b.media.count) media"
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier("public.file-url") }) else { return false }
        p.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
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
    var body: some View {
        ContentUnavailableView(
            "Drop a tfevents folder",
            systemImage: "tray.and.arrow.down",
            description: Text("Drag a run directory from TensorBoard logs.")
        )
    }
}

private struct TagDetail: View {
    let bundle: TagBundle
    @State private var selectedMedia: MediaFrame?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !bundle.scalars.isEmpty {
                    GroupBox("Scalars") {
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

                if !bundle.media.isEmpty {
                    GroupBox("Video / GIF") {
                        ForEach(bundle.media) { frame in
                            Button("Open step \(frame.step)") {
                                selectedMedia = frame
                            }
                            .buttonStyle(.link)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(bundle.tag)
        .sheet(item: $selectedMedia) { media in
            MediaPlayerSheet(frame: media)
        }
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
