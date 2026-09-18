import PhotosUI
import SwiftUI

/// The one place a photo becomes a draft: clean it up, analyse it, store it.
/// Both the single scan and the batch import go through here.
enum GarmentScanner {

    /// Photos are capped before anything else runs — a 12 MP capture costs
    /// nothing extra in accuracy and a lot in memory when twenty arrive at once.
    static let workingEdge: CGFloat = 2048

    @MainActor
    static func makeDraft(from photo: UIImage, ai: AIService) async -> GarmentDraft? {
        let prepared = photo.normalizedOrientation().resized(maxEdge: workingEdge)
        let processed = await GarmentImageProcessor.process(prepared)
        let forAnalysis = processed.didIsolateSubject
            ? GarmentImageProcessor.flatten(processed.cutout)
            : prepared
        let result = await ai.analyzeGarment(image: forAnalysis, shape: processed.shape)

        return try? GarmentDraft(
            analysis: result.analysis,
            cutout: processed.cutout,
            original: prepared,
            engine: result.engine,
            fallbackNotice: result.fallbackReason
        )
    }

    @MainActor
    static func makeDraft(from item: PhotosPickerItem, ai: AIService) async -> GarmentDraft? {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let photo = UIImage(data: data) else { return nil }
        return await makeDraft(from: photo, ai: ai)
    }
}

extension GarmentScanner {
    /// Builds a draft from a shop's product page: the photo goes through the
    /// same analysis, then the page's own name, brand and colour win where they
    /// exist, because the shop knows its product better than any model does.
    @MainActor
    static func makeDraft(
        from product: ProductLinkImporter.Product,
        image: UIImage,
        sourceURL: URL,
        ai: AIService
    ) async -> GarmentDraft? {
        guard let draft = await makeDraft(from: image, ai: ai) else { return nil }

        if let title = product.title?.productName, !title.isEmpty {
            draft.name = title
        }
        // The shop's own brand field wins; then whatever the analyser read off
        // the label; and for a single-brand store the site name is a fair guess.
        if let brand = product.brand, !brand.isEmpty {
            draft.brand = brand
        } else if draft.brand.isEmpty, let site = product.siteName, site.count <= 24 {
            draft.brand = site
        }
        if let colour = product.colorName, !colour.isEmpty {
            draft.colorName = colour
            draft.colorFamily = ColorFamily.from(colour)
        }
        draft.notes = sourceURL.absoluteString
        return draft
    }
}

private extension String {
    /// Shop titles trail off into site names and slogans — keep the product bit.
    var productName: String {
        let head = split(separator: "|").first.map(String.init) ?? self
        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 60 ? String(trimmed.prefix(60)).trimmingCharacters(in: .whitespaces) : trimmed
    }
}
