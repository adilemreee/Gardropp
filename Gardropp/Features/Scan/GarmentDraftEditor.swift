import SwiftUI

/// The "correct what the analyser got wrong" sheet, shared by the single-item
/// review screen and the batch review grid.
struct GarmentDraftEditor: View {
    @Bindable var draft: GarmentDraft
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GarmentAttributesEditor(
                name: $draft.name,
                category: $draft.category,
                subcategory: $draft.subcategory,
                brand: $draft.brand,
                colorName: $draft.colorName,
                colorFamily: $draft.colorFamily,
                style: $draft.style,
                seasons: $draft.seasons,
                material: $draft.material,
                notes: $draft.notes
            )
            .navigationTitle(Text("Edit item"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
