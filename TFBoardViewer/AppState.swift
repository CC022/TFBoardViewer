import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var parsed = ParsedLog()
    @Published var isLoading = false
    @Published var error: String?
    @Published var selectedTag: String?

    func loadFolder(_ url: URL) {
        isLoading = true
        error = nil
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
