import SwiftUI

/// One editor shared by the scan review screen and the item detail screen.
struct GarmentAttributesEditor: View {
    @Binding var name: String
    @Binding var category: ItemCategory
    @Binding var subcategory: String
    @Binding var brand: String
    @Binding var colorName: String
    @Binding var colorFamily: ColorFamily
    @Binding var style: StyleTag
    @Binding var seasons: Set<Season>
    @Binding var material: String
    @Binding var notes: String

    var body: some View {
        Form {
            Section {
                TextField(String(localized: "Name"), text: $name)
                Picker(selection: $category) {
                    ForEach(ItemCategory.allCases) { option in
                        Label(option.title, systemImage: option.symbol).tag(option)
                    }
                } label: {
                    Text("Category")
                }
                TextField(String(localized: "Type, e.g. T-shirts"), text: $subcategory)
                TextField(String(localized: "Brand"), text: $brand)
            }

            Section {
                TextField(String(localized: "Colour"), text: $colorName)
                Picker(selection: $colorFamily) {
                    ForEach(ColorFamily.allCases) { family in
                        HStack {
                            Circle().fill(family.swatch).frame(width: 14, height: 14)
                            Text(family.title)
                        }
                        .tag(family)
                    }
                } label: {
                    Text("Colour family")
                }
                Picker(selection: $style) {
                    ForEach(StyleTag.allCases) { tag in
                        Text(tag.title).tag(tag)
                    }
                } label: {
                    Text("Style")
                }
            } header: {
                Text("Colour and style")
            }

            Section {
                ForEach(Season.allCases) { season in
                    Button {
                        if seasons.contains(season) { seasons.remove(season) } else { seasons.insert(season) }
                    } label: {
                        HStack {
                            Text(season.title).foregroundStyle(Color.textPrimary)
                            Spacer()
                            if seasons.contains(season) {
                                Image(systemName: "checkmark").foregroundStyle(Color.textPrimary)
                            }
                        }
                    }
                }
            } header: {
                Text("Seasons")
            }

            Section {
                TextField(String(localized: "Material"), text: $material)
                TextField(String(localized: "Notes"), text: $notes, axis: .vertical)
                    .lineLimit(2...5)
            }
        }
    }
}
