import Observation
import PhotosUI
import SwiftUI

/// Runs a whole gallery selection through the scanner, a few at a time, and
/// keeps the drafts in the order they were picked.
@MainActor
@Observable
final class BatchScanModel {
    private(set) var drafts: [GarmentDraft] = []
    private(set) var completed = 0
    private(set) var total = 0
    private(set) var failed = 0
    private(set) var isRunning = false

    private var task: Task<Void, Never>?

    var progress: Double {
        total == 0 ? 0 : Double(completed) / Double(total)
    }

    func start(items: [PhotosPickerItem], ai: AIService) {
        cancel()
        drafts = []
        completed = 0
        failed = 0
        total = items.count
        isRunning = true

        task = Task { [weak self] in
            await self?.run(items: items, ai: ai)
        }
    }

    /// Cloud engines get a narrower window so a big import does not trip rate limits.
    private func run(items: [PhotosPickerItem], ai: AIService) async {
        let window = ai.settings.visionProviderKind == .onDevice ? 3 : 2
        var results: [Int: GarmentDraft] = [:]

        for chunk in stride(from: 0, to: items.count, by: window) {
            if Task.isCancelled { break }
            let range = chunk..<min(chunk + window, items.count)

            await withTaskGroup(of: (Int, GarmentDraft?).self) { group in
                for index in range {
                    let item = items[index]
                    group.addTask { @MainActor in
                        (index, await GarmentScanner.makeDraft(from: item, ai: ai))
                    }
                }
                for await (index, draft) in group {
                    if let draft {
                        results[index] = draft
                    } else {
                        failed += 1
                    }
                    completed += 1
                }
            }
            // Publish progressively so the grid fills in as work finishes.
            drafts = results.keys.sorted().compactMap { results[$0] }
        }

        if Task.isCancelled {
            for draft in results.values { draft.discard() }
            drafts = []
        }
        isRunning = false
    }

    func cancel() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    func remove(_ draft: GarmentDraft) {
        drafts.removeAll { $0.id == draft.id }
        draft.discard()
    }

    /// Called when the sheet closes without saving.
    func discardAll() {
        cancel()
        for draft in drafts { draft.discard() }
        drafts = []
        total = 0
        completed = 0
    }

    func applyLocation(_ name: String?) {
        for draft in drafts { draft.locationName = name }
    }
}
