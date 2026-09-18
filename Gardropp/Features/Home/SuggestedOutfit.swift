import Observation
import SwiftUI

/// An outfit proposal that only lives in memory until the user likes or wears it.
struct SuggestedOutfit: Identifiable, Equatable {
    let id: UUID
    var title: String
    var rationale: String
    var matchScore: Int
    var occasion: Occasion
    var items: [ClothingItem]
    var engine: String

    static func == (lhs: SuggestedOutfit, rhs: SuggestedOutfit) -> Bool { lhs.id == rhs.id }

    var layered: [ClothingItem] {
        items.sorted { $0.category.layerOrder < $1.category.layerOrder }
    }
}

/// Builds the home screen's suggestions and keeps track of what was dismissed.
@MainActor
@Observable
final class SuggestionModel {
    private(set) var suggestions: [SuggestedOutfit] = []
    private(set) var isLoading = false
    private(set) var engine = ""
    private(set) var errorMessage: String?
    var occasion: Occasion = .everyday

    private var dismissed: Set<UUID> = []
    private var lastSignature: String?

    var visible: [SuggestedOutfit] {
        suggestions.filter { !dismissed.contains($0.id) }
    }

    func dismiss(_ suggestion: SuggestedOutfit) {
        dismissed.insert(suggestion.id)
    }

    /// Regenerates when the wardrobe, the occasion or the weather moved on.
    func refreshIfNeeded(
        items: [ClothingItem],
        temperature: Double?,
        weatherSummary: String?,
        preferredStyles: [StyleTag],
        ai: AIService,
        force: Bool = false
    ) async {
        let signature = [
            "\(items.count)",
            items.map(\.id.uuidString).sorted().joined().hashValue.description,
            occasion.rawValue,
            temperature.map { String(Int($0)) } ?? "-",
            ai.settings.provider.rawValue
        ].joined(separator: "|")

        guard force || signature != lastSignature else { return }
        guard items.count >= 2 else {
            suggestions = []
            lastSignature = signature
            return
        }

        isLoading = true
        errorMessage = nil
        dismissed.removeAll()
        defer { isLoading = false }

        let lookup = Dictionary(uniqueKeysWithValues: items.map { ($0.id.uuidString, $0) })
        let request = OutfitRequest(
            items: items.map { item in
                OutfitItemSummary(
                    id: item.id.uuidString,
                    name: item.name,
                    category: item.category.rawValue,
                    subcategory: item.subcategory,
                    color: item.colorName,
                    colorFamily: item.colorFamily.rawValue,
                    style: item.style.rawValue,
                    seasons: item.seasonRaws,
                    brand: item.brand,
                    wearCount: item.wearCount
                )
            },
            occasion: occasion,
            temperature: temperature,
            weatherSummary: weatherSummary,
            preferredStyles: preferredStyles.map(\.rawValue),
            languageName: AnalysisContext.current.languageName,
            count: 4
        )

        let result = await ai.suggestOutfits(request)
        engine = result.engine
        errorMessage = result.fallbackReason

        suggestions = result.suggestions.compactMap { dto in
            let resolved = dto.itemIds.compactMap { lookup[$0] }
            guard resolved.count >= 2 else { return nil }
            return SuggestedOutfit(
                id: UUID(),
                title: dto.title,
                rationale: dto.rationale,
                matchScore: dto.matchScore,
                occasion: dto.occasion.flatMap(Occasion.init(rawValue:)) ?? occasion,
                items: resolved,
                engine: result.engine
            )
        }
        lastSignature = signature
    }
}
