import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var parsed = ParsedLog()
    var isLoading = false
    var error: String?
    var selectedTag: String?
    var loadedFolderName: String?

    func loadFolder(_ url: URL) {
        isLoading = true
        error = nil
        loadedFolderName = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        Task {
            do {
                let parsed = try await Task.detached(priority: .userInitiated) {
                    try EventParser.parse(folderURL: url)
                }.value
                self.parsed = parsed
                self.selectedTag = parsed.sortedBundles.first?.tag
            } catch {
                self.error = error.localizedDescription
                self.parsed = ParsedLog()
                self.selectedTag = nil
            }
            self.isLoading = false
        }
    }
}
