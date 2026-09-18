import SwiftUI

/// Draws an outfit as a vertical stack of cut-outs, the way you would lay the
/// clothes out on a bed: outerwear and tops first, then bottoms, then shoes.
struct OutfitStackView: View {
    let items: [ClothingItem]
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 0 : 2) {
            ForEach(items.prefix(4)) { item in
                GarmentThumbnail(filename: item.imageFilename, fallbackSymbol: item.category.symbol, padding: 0)
                    .frame(maxWidth: .infinity)
                    .frame(height: height(for: item))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func height(for item: ClothingItem) -> CGFloat {
        let base: CGFloat = compact ? 42 : 74
        switch item.category {
        case .footwear: return base * 0.5
        case .accessories: return base * 0.5
        case .dresses: return base * 1.4
        default: return base
        }
    }
}
