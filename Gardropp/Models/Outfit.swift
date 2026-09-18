import Foundation
import SwiftData

@Model
final class Outfit {
    var id: UUID = UUID()
    var title: String = ""
    /// One-line explanation shown under the outfit ("Matches your minimal style").
    var rationale: String = ""
    var occasionRaw: String = Occasion.everyday.rawValue
    /// 0...100 match score shown as "80% for you".
    var matchScore: Int = 0
    var createdAt: Date = Date.now
    var lastWornAt: Date?
    var wearCount: Int = 0
    var isSaved: Bool = false
    var isDismissed: Bool = false
    var isLiked: Bool = false
    var generatedBy: String = ""
    /// Temperature the suggestion was generated for, if any.
    var suggestedForTemperature: Double?

    var items: [ClothingItem] = []

    init(
        title: String,
        rationale: String = "",
        occasion: Occasion = .everyday,
        matchScore: Int = 0,
        items: [ClothingItem] = [],
        generatedBy: String = "",
        suggestedForTemperature: Double? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.rationale = rationale
        self.occasionRaw = occasion.rawValue
        self.matchScore = matchScore
        self.items = items
        self.generatedBy = generatedBy
        self.suggestedForTemperature = suggestedForTemperature
        self.createdAt = .now
    }

    var occasion: Occasion {
        get { Occasion(rawValue: occasionRaw) ?? .everyday }
        set { occasionRaw = newValue.rawValue }
    }

    var layeredItems: [ClothingItem] {
        items.sorted { $0.category.layerOrder < $1.category.layerOrder }
    }

    func markWorn(on date: Date = .now) {
        wearCount += 1
        lastWornAt = date
        for item in items { item.markWorn(on: date) }
    }
}
