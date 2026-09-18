import SwiftData
import SwiftUI

/// The "Item detected" review screen: everything the analyser worked out, with
/// one tap to correct it and one to save.
struct DetectedItemView: View {
    @Bindable var draft: GarmentDraft
    var onSave: (GarmentDraft) -> Void
    var onRetake: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StorageLocation.createdAt) private var locations: [StorageLocation]

    @State private var isEditing = false
    @State private var isAddingLocation = false
    @State private var newLocationName = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    GarmentThumbnail(filename: draft.imageFilename, fallbackSymbol: draft.category.symbol, padding: 18)
                        .frame(maxWidth: .infinity)
                        .frame(height: 300)
                        .cardBackground(Theme.Radius.sheet)

                    if !draft.alternativeFilenames.isEmpty {
                        photoChoices
                    }

                    if let notice = draft.fallbackNotice {
                        FallbackBanner(message: notice)
                    }

                    VStack(spacing: 3) {
                        Text(draft.name)
                            .font(.system(size: 21, weight: .semibold))
                            .multilineTextAlignment(.center)
                        Text(draft.typeLabel)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.textSecondary)
                    }

                    AttributeChipsRow(
                        brand: draft.brand,
                        color: draft.colorName,
                        style: draft.style.title,
                        season: draft.seasonSummary
                    )

                    locationPicker
                }
                .padding(.horizontal, Theme.Spacing.gutter)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 12) {
                Button("Edit") { isEditing = true }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Save") { onSave(draft) }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .sheet(isPresented: $isEditing) {
            GarmentDraftEditor(draft: draft)
        }
        .alert(Text("New place"), isPresented: $isAddingLocation) {
            TextField(String(localized: "e.g. Bedroom wardrobe"), text: $newLocationName)
            Button("Cancel", role: .cancel) { newLocationName = "" }
            Button("Add") { addLocation() }
        }
    }

    /// Shops publish the same garment on a model and on its own. The better
    /// looking one is picked automatically; this is how you overrule it.
    private var photoChoices: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Another photo from the shop")
                .font(.system(size: 13, weight: .semibold))

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(draft.alternativeFilenames, id: \.self) { filename in
                        Button {
                            Task { await draft.use(alternative: filename) }
                        } label: {
                            GarmentThumbnail(filename: filename, fallbackSymbol: draft.category.symbol, padding: 0)
                                .frame(width: 62, height: 82)
                                .clipShape(.rect(cornerRadius: 10))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10).stroke(Color.hairline, lineWidth: 0.5)
                                }
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

    // MARK: - Where do you keep it

    private var locationPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Where do you keep it?")
                    .font(.system(size: 16, weight: .semibold))
                Text("Optional. It'll help you find it later.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textSecondary)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(locations) { location in
                        Button {
                            draft.locationName = draft.locationName == location.name ? nil : location.name
                        } label: {
                            ChipLabel(
                                title: location.name,
                                isSelected: draft.locationName == location.name,
                                symbol: location.symbol
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        isAddingLocation = true
                    } label: {
                        ChipLabel(title: String(localized: "New"), symbol: "plus")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addLocation() {
        let trimmed = newLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
        newLocationName = ""
        guard !trimmed.isEmpty else { return }
        let location = StorageLocation(name: trimmed)
        modelContext.insert(location)
        try? modelContext.save()
        draft.locationName = trimmed
    }
}

// MARK: - Shared pieces

/// The four caption/value pills under a garment's name.
struct AttributeChipsRow: View {
    var brand: String
    var color: String
    var style: String
    var season: String

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip("Brand", brand.isEmpty ? "—" : brand)
                chip("Colour", color)
                chip("Style", style)
                chip("Season", season)
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ caption: LocalizedStringKey, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(Color.textSecondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.surface, in: .rect(cornerRadius: Theme.Radius.chip))
    }
}

/// Shown when a cloud engine failed and the on-device one stepped in.
struct FallbackBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text("Analysed on device")
                    .font(.system(size: 13, weight: .semibold))
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.surface, in: .rect(cornerRadius: Theme.Radius.tile))
    }
}
