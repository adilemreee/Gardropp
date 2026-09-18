import Foundation
import UIKit

/// The app's single entry point to "ask the AI something". It picks the
/// configured provider, and quietly falls back to the on-device engine when a
/// cloud call fails so the user is never stuck.
@MainActor
@Observable
final class AIService {
    let settings: AISettings

    init(settings: AISettings) {
        self.settings = settings
    }

    struct AnalysisResult {
        var analysis: GarmentAnalysis
        var engine: String
        /// Why the cloud engine was skipped, when it was.
        var fallbackReason: String?
        var usedFallback: Bool { fallbackReason != nil }
    }

    func analyzeGarment(image: UIImage, shape: GarmentShape? = nil) async -> AnalysisResult {
        let kind = settings.visionProviderKind
        var context = AnalysisContext.current
        context.shape = shape
        var fallbackReason: String?

        if kind != .onDevice {
            do {
                let provider = settings.makeProvider(kind)
                var analysis = try await provider.analyzeGarment(image: image, context: context)
                // The model reads the colour by eye; the pixels are more accurate.
                if analysis.colorHex == nil {
                    analysis.colorHex = ColorAnalyzer.dominantSwatch(of: image).hex
                }
                return AnalysisResult(analysis: analysis, engine: kind.displayName, fallbackReason: nil)
            } catch {
                fallbackReason = error.localizedDescription
            }
        }

        let analysis = (try? await OnDeviceProvider().analyzeGarment(image: image, context: context))
            ?? .placeholder
        return AnalysisResult(
            analysis: analysis,
            engine: AIProviderKind.onDevice.displayName,
            fallbackReason: fallbackReason
        )
    }

    struct SuggestionResult {
        var suggestions: [OutfitSuggestionDTO]
        var engine: String
        var fallbackReason: String?
        var usedFallback: Bool { fallbackReason != nil }
    }

    func suggestOutfits(_ request: OutfitRequest) async -> SuggestionResult {
        let kind = settings.hasKey(for: settings.provider) ? settings.provider : .onDevice
        var fallbackReason: String?

        if kind != .onDevice {
            do {
                let provider = settings.makeProvider(kind)
                let suggestions = try await provider.suggestOutfits(request)
                let valid = sanitize(suggestions, against: request)
                if !valid.isEmpty {
                    return SuggestionResult(suggestions: valid, engine: kind.displayName, fallbackReason: nil)
                }
                fallbackReason = String(localized: "The model returned no usable outfits.")
            } catch {
                fallbackReason = error.localizedDescription
            }
        }

        return SuggestionResult(
            suggestions: LocalOutfitEngine.suggest(request),
            engine: AIProviderKind.onDevice.displayName,
            fallbackReason: fallbackReason
        )
    }

    /// Drops hallucinated ids and outfits that ended up empty.
    private func sanitize(_ suggestions: [OutfitSuggestionDTO], against request: OutfitRequest) -> [OutfitSuggestionDTO] {
        let known = Set(request.items.map(\.id))
        return suggestions.compactMap { suggestion in
            var cleaned = suggestion
            cleaned.itemIds = suggestion.itemIds.filter { known.contains($0) }
            cleaned.matchScore = min(100, max(0, suggestion.matchScore))
            return cleaned.itemIds.count >= 2 ? cleaned : nil
        }
    }
}
