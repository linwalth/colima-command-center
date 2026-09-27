import Cocoa
import SwiftUI

@MainActor
final class DiskViewModel: ObservableObject {
    @Published var blocks: [DiskInspector.Block] = []
    @Published var cleanResult: String?
    @Published var isLoading = false
    @Published var isCleaning = false
    @Published var lastUpdated: Date?
    @Published var available = true
    @Published var showCleanConfirm = false

    func refresh() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let blocks = DiskInspector.usage()
            DispatchQueue.main.async { [weak self] in
                if let blocks {
                    self?.blocks = blocks
                    self?.available = true
                } else {
                    self?.blocks = []
                    self?.available = false
                }
                self?.isLoading = false
                self?.lastUpdated = Date()
            }
        }
    }

    func runClean() {
        isCleaning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = DiskInspector.clean()
            DispatchQueue.main.async { [weak self] in
                self?.cleanResult = result
                self?.isCleaning = false
                // Refresh usage WITHOUT clearing cleanResult.
                self?.refreshUsage()
            }
        }
    }

    private func refreshUsage() {
        DispatchQueue.global(qos: .userInitiated).async {
            let blocks = DiskInspector.usage()
            DispatchQueue.main.async { [weak self] in
                if let blocks { self?.blocks = blocks }
                self?.lastUpdated = Date()
            }
        }
    }
}
