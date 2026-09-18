import CryptoKit
import Foundation
import Observation
import UIKit

/// What a finished try-on produced.
enum TryOnOutput: Equatable {
    /// File name inside the image store.
    case still(String)
    /// Local file on disk.
    case video(URL)
}

/// Runs try-ons and remembers what it already produced, so looking at the same
/// outfit twice never costs twice.
@MainActor
@Observable
final class TryOnService {
    let settings: TryOnSettings

    private(set) var isRunning = false
    private(set) var status: String?
    private(set) var errorMessage: String?

    init(settings: TryOnSettings) {
        self.settings = settings
    }

    // MARK: - Cache

    private static let indexKey = "tryon.cache"

    private var index: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: Self.indexKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.indexKey) }
    }

    private static var videoDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appending(path: "TryOnVideos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func signature(items: [ClothingItem], person: String, mode: TryOnMode) -> String {
        let engine = mode == .video ? settings.videoEngine.rawValue : settings.engine.rawValue
        let model = mode == .video
            ? settings.model(for: settings.videoEngine)
            : settings.model(for: settings.engine)
        let parts = [
            person,
            items.map(\.id.uuidString).sorted().joined(separator: ","),
            mode.rawValue, engine, model
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(parts.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// The already-produced result for this outfit, if there is one.
    func cached(items: [ClothingItem], person: String, mode: TryOnMode) -> TryOnOutput? {
        guard let stored = index[signature(items: items, person: person, mode: mode)] else { return nil }
        switch mode {
        case .still:
            return ImageStore.shared.image(named: stored) != nil ? .still(stored) : nil
        case .video:
            let url = Self.videoDirectory.appending(path: stored)
            return FileManager.default.fileExists(atPath: url.path) ? .video(url) : nil
        }
    }

    // MARK: - Running

    func run(items: [ClothingItem], person personFilename: String, mode: TryOnMode) async -> TryOnOutput? {
        errorMessage = nil
        isRunning = true
        defer { isRunning = false; status = nil }

        do {
            guard let person = ImageStore.shared.image(named: personFilename) else {
                throw TryOnError.missingPersonPhoto
            }

            // The still is needed either way, and may already be paid for.
            let stillOutput: TryOnOutput
            if let cached = cached(items: items, person: personFilename, mode: .still) {
                stillOutput = cached
            } else {
                status = String(localized: "Fitting the outfit…")
                let image = try await makeStill(person: person, items: items)
                let filename = try ImageStore.shared.save(image, format: .jpeg(quality: 0.92))
                index[signature(items: items, person: personFilename, mode: .still)] = filename
                stillOutput = .still(filename)
            }

            guard mode == .video else { return stillOutput }

            guard case .still(let stillName) = stillOutput,
                  let still = ImageStore.shared.image(named: stillName) else {
                throw TryOnError.noOutput("")
            }
            status = String(localized: "Filming the turnaround…")
            let data = try await makeVideo(from: still)

            let name = signature(items: items, person: personFilename, mode: .video) + ".mp4"
            let url = Self.videoDirectory.appending(path: name)
            try data.write(to: url, options: .atomic)
            index[signature(items: items, person: personFilename, mode: .video)] = name
            return .video(url)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func makeStill(person: UIImage, items: [ClothingItem]) async throws -> UIImage {
        let engine = settings.engine
        let key = settings.apiKey(for: engine.keychainAccount)
        let garments = garments(from: items, for: engine)
        guard !garments.isEmpty else { throw TryOnError.noGarments }

        let provider: TryOnStillProvider = switch engine {
        case .gemini: GeminiTryOnProvider(apiKey: key)
        case .fashn: FashnTryOnProvider(apiKey: key)
        case .idmVton: FalTryOnProvider(apiKey: key)
        }
        return try await provider.fit(person: person, garments: garments, model: settings.model(for: engine))
    }

    private func makeVideo(from still: UIImage) async throws -> Data {
        let engine = settings.videoEngine
        let key = settings.apiKey(for: engine.keychainAccount)
        let provider: TryOnVideoProvider = switch engine {
        case .veo: VeoVideoProvider(apiKey: key)
        case .kling: FalVideoProvider(apiKey: key)
        }
        return try await provider.animate(still: still, model: settings.model(for: engine), seconds: 4)
    }

    /// Dressing order matters when garments are fitted one at a time.
    private func garments(from items: [ClothingItem], for engine: TryOnEngine) -> [TryOnGarment] {
        let order: [ItemCategory] = [.dresses, .bottoms, .tops, .outerwear, .footwear, .accessories]
        return items
            .filter { engine.supportedCategories.contains($0.category) }
            .sorted { lhs, rhs in
                (order.firstIndex(of: lhs.category) ?? 9) < (order.firstIndex(of: rhs.category) ?? 9)
            }
            .compactMap { item in
                guard let cutout = ImageStore.shared.image(named: item.imageFilename) else { return nil }
                return TryOnGarment(
                    image: GarmentImageProcessor.flatten(cutout),
                    category: item.category,
                    name: item.name
                )
            }
    }

    /// How many paid calls a run will make, so the cost shown is honest.
    func callCount(items: [ClothingItem]) -> Int {
        let engine = settings.engine
        let count = items.filter { engine.supportedCategories.contains($0.category) }.count
        return engine.fitsWholeOutfitAtOnce ? min(1, count) : count
    }
}
