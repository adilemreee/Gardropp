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

    private(set) var imageFilename: String
    let originalFilename: String?
    /// Other photos the shop offered, to switch between.
    var alternativeFilenames: [String] = []
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

    /// Turns the draft into a stored item. The images are already on disk; the
    /// photos that were not chosen are not needed any more.
    func makeItem() -> ClothingItem {
        for filename in alternativeFilenames { ImageStore.shared.delete(filename) }
        alternativeFilenames = []

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

    /// Swaps in one of the shop's other photos, keeping the catalogue entry but
    /// re-reading the colour, which is the one thing tied to the picture.
    @MainActor
    func use(alternative filename: String) async {
        guard let source = ImageStore.shared.image(named: filename) else { return }
        let processed = await GarmentImageProcessor.process(source)
        guard let saved = try? ImageStore.shared.save(processed.cutout, format: .png) else { return }

        // The one being replaced becomes an alternative, so switching back is
        // free — its file stays on disk until the draft is saved or thrown away.
        var others = alternativeFilenames
        others.removeAll { $0 == filename }
        others.append(imageFilename)

        imageFilename = saved
        alternativeFilenames = others

        let swatch = ColorAnalyzer.dominantSwatch(of: processed.cutout)
        colorHex = swatch.hex
        colorFamily = swatch.family
    }

    /// Throws the photos away again when the draft is abandoned.
    func discard() {
        ImageStore.shared.delete(imageFilename)
        ImageStore.shared.delete(originalFilename)
        for filename in alternativeFilenames { ImageStore.shared.delete(filename) }
    }
}
