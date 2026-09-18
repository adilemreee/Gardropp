import Observation
import UIKit

/// The editable result of a scan, shown before it becomes a real wardrobe item.
///
/// The photos are written to the image store as soon as the draft is created,
/// and the draft only carries their file names — a batch of twenty garments
/// would otherwise hold hundreds of megabytes of bitmaps in memory.
@Observable
final class GarmentDraft: Identifiable {
    let id = UUID()

    var name: String
    var category: ItemCategory
    var subcategory: String
    var brand: String
    var colorName: String
    var colorHex: String
    var colorFamily: ColorFamily
    var style: StyleTag
    var seasons: Set<Season>
    var material: String
    var notes: String
    var locationName: String?

    let imageFilename: String
    let originalFilename: String?
    let engine: String
    let confidence: Double
    /// Set when a cloud engine failed and the on-device one answered instead.
    let fallbackNotice: String?

    init(
        analysis: GarmentAnalysis,
        cutout: UIImage,
        original: UIImage,
        engine: String,
        fallbackNotice: String? = nil
    ) throws {
        imageFilename = try ImageStore.shared.save(cutout, format: .png)
        originalFilename = try? ImageStore.shared.save(original.resized(maxEdge: 1600), format: .jpeg(quality: 0.75))

        name = analysis.name
        category = ItemCategory.from(analysis.category)
        subcategory = analysis.subcategory
        brand = analysis.brand ?? ""
        colorName = analysis.colorName
        colorHex = analysis.colorHex ?? "#808080"
        colorFamily = ColorFamily.from(analysis.colorName)
        style = StyleTag.from(analysis.style)
        let parsedSeasons = Set(analysis.seasons.compactMap(Season.init(rawValue:)))
        seasons = parsedSeasons.isEmpty ? Set(Season.allCases) : parsedSeasons
        material = analysis.material ?? ""
        notes = ""
        self.engine = engine
        self.confidence = analysis.confidence ?? 1
        self.fallbackNotice = fallbackNotice
    }

    var image: UIImage? { ImageStore.shared.image(named: imageFilename) }

    var typeLabel: String {
        subcategory.isEmpty ? category.title : subcategory
    }

    var seasonSummary: String {
        if seasons.count == Season.allCases.count { return String(localized: "All year") }
        return Season.allCases
            .filter { seasons.contains($0) }
            .map(\.title)
            .joined(separator: " / ")
    }

    /// Turns the draft into a stored item. The images are already on disk.
    func makeItem() -> ClothingItem {
        let item = ClothingItem(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            subcategory: subcategory,
            brand: brand.isEmpty ? nil : brand,
            colorName: colorName,
            colorHex: colorHex,
            colorFamily: colorFamily,
            style: style,
            seasons: Season.allCases.filter { seasons.contains($0) },
            material: material.isEmpty ? nil : material,
            locationName: locationName,
            imageFilename: imageFilename,
            originalImageFilename: originalFilename,
            confidence: confidence,
            analyzedBy: engine
        )
        item.notes = notes
        return item
    }

    /// Throws the photos away again when the draft is abandoned.
    func discard() {
        ImageStore.shared.delete(imageFilename)
        ImageStore.shared.delete(originalFilename)
    }
}
