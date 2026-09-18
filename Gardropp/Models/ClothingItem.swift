import Foundation
import SwiftData

@Model
final class ClothingItem {
    var id: UUID = UUID()
    var name: String = ""
    var categoryRaw: String = ItemCategory.tops.rawValue
    /// Free-form sub type such as "T-shirts" or "Jeans", supplied by the analyser.
    var subcategory: String = ""
    var brand: String?
    var colorName: String = ""
    var colorHex: String = "#808080"
    var colorFamilyRaw: String = ColorFamily.multicolour.rawValue
    var styleRaw: String = StyleTag.casual.rawValue
    var seasonRaws: [String] = Season.allCases.map(\.rawValue)
    var material: String?
    var locationName: String?
    var notes: String = ""
    var isFavorite: Bool = false
    var wearCount: Int = 0
    var lastWornAt: Date?
    var createdAt: Date = Date.now
    /// File name inside the image store for the cleaned-up product shot.
    var imageFilename: String = ""
    /// File name of the untouched capture, kept so the user can re-run the analysis.
    var originalImageFilename: String?
    /// 0...1, how sure the analyser was about the attributes.
    var confidence: Double = 1
    /// Which engine produced the attributes, for display in the item detail sheet.
    var analyzedBy: String = ""

    @Relationship(inverse: \Outfit.items)
    var outfits: [Outfit] = []

    init(
        name: String,
        category: ItemCategory,
        subcategory: String,
        brand: String? = nil,
        colorName: String,
        colorHex: String,
        colorFamily: ColorFamily,
        style: StyleTag,
        seasons: [Season],
        material: String? = nil,
        locationName: String? = nil,
        imageFilename: String,
        originalImageFilename: String? = nil,
        confidence: Double = 1,
        analyzedBy: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.categoryRaw = category.rawValue
        self.subcategory = subcategory
        self.brand = brand
        self.colorName = colorName
        self.colorHex = colorHex
        self.colorFamilyRaw = colorFamily.rawValue
        self.styleRaw = style.rawValue
        self.seasonRaws = seasons.map(\.rawValue)
        self.material = material
        self.locationName = locationName
        self.imageFilename = imageFilename
        self.originalImageFilename = originalImageFilename
        self.confidence = confidence
        self.analyzedBy = analyzedBy
        self.createdAt = .now
    }

    // MARK: - Typed accessors

    var category: ItemCategory {
        get { ItemCategory(rawValue: categoryRaw) ?? .tops }
        set { categoryRaw = newValue.rawValue }
    }

    var style: StyleTag {
        get { StyleTag(rawValue: styleRaw) ?? .casual }
        set { styleRaw = newValue.rawValue }
    }

    var colorFamily: ColorFamily {
        get { ColorFamily(rawValue: colorFamilyRaw) ?? .multicolour }
        set { colorFamilyRaw = newValue.rawValue }
    }

    var seasons: [Season] {
        get { seasonRaws.compactMap(Season.init(rawValue:)).sorted { $0.sortIndex < $1.sortIndex } }
        set { seasonRaws = newValue.map(\.rawValue) }
    }

    var seasonSummary: String {
        let all = seasons
        if all.count == Season.allCases.count { return String(localized: "All year") }
        return all.map { $0.title }.joined(separator: " / ")
    }

    func markWorn(on date: Date = .now) {
        wearCount += 1
        lastWornAt = date
    }

    /// How well the item suits an outdoor temperature, 0...1.
    func temperatureFit(_ celsius: Double) -> Double {
        let ranges = seasons.map(\.temperatureRange)
        guard !ranges.isEmpty else { return 0.5 }
        if ranges.contains(where: { $0.contains(celsius) }) { return 1 }
        let distance = ranges.map { range -> Double in
            celsius < range.lowerBound ? range.lowerBound - celsius : celsius - range.upperBound
        }.min() ?? 0
        return max(0, 1 - distance / 15)
    }
}
