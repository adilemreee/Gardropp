import SwiftUI

/// An outfit laid out the way you would put it on the bed: pieces side by side,
/// each on its own tile, so every garment is actually legible.
struct OutfitLineup: View {
    let items: [ClothingItem]
    var compact = false

    private var shown: [ClothingItem] {
        Array(items.prefix(compact ? 3 : 4))
    }

    var body: some View {
        HStack(spacing: compact ? 5 : 8) {
            ForEach(shown) { item in
                GarmentThumbnail(
                    filename: item.imageFilename,
                    fallbackSymbol: item.category.symbol,
                    padding: compact ? 4 : 8
                )
                .frame(maxWidth: .infinity)
                .aspectRatio(compact ? 0.82 : 0.78, contentMode: .fit)
                .background(
                    Color.surfaceElevated.opacity(compact ? 0.5 : 0.65),
                    in: .rect(cornerRadius: compact ? 10 : Theme.Radius.tile)
                )
            }
        }
    }
}
