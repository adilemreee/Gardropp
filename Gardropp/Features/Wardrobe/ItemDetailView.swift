import SwiftData
import SwiftUI

struct ItemDetailView: View {
    @Bindable var item: ClothingItem

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.showToast) private var showToast
    @Query(sort: \StorageLocation.createdAt) private var locations: [StorageLocation]

    @State private var isEditing = false
    @State private var seasonSelection: Set<Season> = []

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GarmentThumbnail(filename: item.imageFilename, fallbackSymbol: item.category.symbol, padding: 26)
                    .frame(height: 330)
                    .frame(maxWidth: .infinity)
                    .cardBackground(Theme.Radius.sheet)

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.system(size: 21, weight: .semibold))
                        Text(item.subcategory.isEmpty ? item.category.title : item.subcategory)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                    CircularIconButton(symbol: "pencil") { startEditing() }
                }

                attributeRows

                if !item.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes").font(.system(size: 13, weight: .semibold))
                        Text(item.notes).font(.system(size: 14)).foregroundStyle(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .cardBackground(Theme.Radius.tile)
                }

                locationRow

                Button {
                    item.markWorn()
                    modelContext.insert(WearEvent(outfitTitle: item.name, items: [item]))
                    try? modelContext.save()
                    showToast(String(localized: "Marked as worn today"))
                } label: {
                    Label("Wearing this today", systemImage: "checkmark.circle")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(Color.canvas)
        .navigationTitle(Text("Item details"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        item.isFavorite.toggle()
                    } label: {
                        Label(item.isFavorite ? "Remove from favourites" : "Add to favourites",
                              systemImage: item.isFavorite ? "heart.slash" : "heart")
                    }
                    Button { startEditing() } label: { Label("Edit item", systemImage: "pencil") }
                    Divider()
                    Button(role: .destructive) { delete() } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .sheet(isPresented: $isEditing, onDismiss: commitEdits) {
            NavigationStack {
                GarmentAttributesEditor(
                    name: $item.name,
                    category: Binding(get: { item.category }, set: { item.category = $0 }),
                    subcategory: $item.subcategory,
                    brand: Binding(get: { item.brand ?? "" }, set: { item.brand = $0.isEmpty ? nil : $0 }),
                    colorName: $item.colorName,
                    colorFamily: Binding(get: { item.colorFamily }, set: { item.colorFamily = $0 }),
                    style: Binding(get: { item.style }, set: { item.style = $0 }),
                    seasons: $seasonSelection,
                    material: Binding(get: { item.material ?? "" }, set: { item.material = $0.isEmpty ? nil : $0 }),
                    notes: $item.notes
                )
                .navigationTitle(Text("Edit item"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { isEditing = false }
                    }
                }
            }
        }
    }

    // MARK: - Rows

    private var attributeRows: some View {
        VStack(spacing: 0) {
            row("tag", "Brand", value: item.brand ?? String(localized: "Unknown"))
            divider
            row("paintpalette", "Colour", value: item.colorName) {
                Circle().fill(Color(hexString: item.colorHex)).frame(width: 12, height: 12)
            }
            divider
            row("square.3.layers.3d", "Style", value: item.style.title)
            divider
            row("calendar", "Season", value: item.seasonSummary)
            divider
            row("square.grid.2x2", "Category", value: item.category.title)
            divider
            row("arrow.triangle.2.circlepath", "Times worn", value: "\(item.wearCount)")
            if item.analyzedBy.isEmpty == false {
                divider
                row("sparkles", "Analysed by", value: item.analyzedBy)
            }
        }
        .padding(.vertical, 4)
        .cardBackground(Theme.Radius.tile)
    }

    private var divider: some View {
        Rectangle().fill(Color.hairline).frame(height: 0.5).padding(.leading, 44)
    }

    private func row(
        _ symbol: String,
        _ title: LocalizedStringKey,
        value: String,
        @ViewBuilder accessory: () -> some View = { EmptyView() }
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 20)
            Text(title).font(.system(size: 15)).foregroundStyle(Color.textSecondary)
            Spacer()
            accessory()
            Text(value).font(.system(size: 15, weight: .medium)).foregroundStyle(Color.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var locationRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Where do you keep it?").font(.system(size: 15, weight: .semibold))
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(locations) { location in
                        Button {
                            item.locationName = item.locationName == location.name ? nil : location.name
                            try? modelContext.save()
                        } label: {
                            ChipLabel(
                                title: location.name,
                                isSelected: item.locationName == location.name,
                                symbol: location.symbol
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private func startEditing() {
        seasonSelection = Set(item.seasons)
        isEditing = true
    }

    private func commitEdits() {
        item.seasons = Season.allCases.filter { seasonSelection.contains($0) }
        try? modelContext.save()
    }

    private func delete() {
        ImageStore.shared.delete(item.imageFilename)
        ImageStore.shared.delete(item.originalImageFilename)
        modelContext.delete(item)
        try? modelContext.save()
        dismiss()
    }
}
