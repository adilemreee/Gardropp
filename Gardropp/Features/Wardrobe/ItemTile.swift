import SwiftUI

/// Grid cell for a garment: the cut-out on a soft card, name underneath.
struct ItemTile: View {
    let item: ClothingItem
    var showsCaption = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GarmentThumbnail(filename: item.imageFilename, fallbackSymbol: item.category.symbol)
                .aspectRatio(1, contentMode: .fit)
                .cardBackground(Theme.Radius.tile)

            if showsCaption {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text(item.subcategory.isEmpty ? item.category.title : item.subcategory)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// Loads a stored garment image, with a symbol placeholder while it is missing.
struct GarmentThumbnail: View {
    let filename: String
    var fallbackSymbol: String = "tshirt"
    var padding: CGFloat = 10

    var body: some View {
        if let image = ImageStore.shared.image(named: filename) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(padding)
        } else {
            Image(systemName: fallbackSymbol)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
