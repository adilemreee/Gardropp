import SwiftUI

/// Paste a shop link and the garment on that page becomes a wardrobe item.
struct LinkImportSheet: View {
    var onSubmit: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var showsInvalid = false
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Paste the address of a product page. The photo, name and brand come straight from the shop.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textSecondary)

                HStack(spacing: 10) {
                    TextField(String(localized: "https://…"), text: $link)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($isFocused)
                        .submitLabel(.go)
                        .onSubmit(submit)
                        .font(.system(size: 15))
                        .padding(14)
                        .cardBackground(Theme.Radius.tile)

                    PasteButton(payloadType: String.self) { items in
                        guard let first = items.first else { return }
                        link = first.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.circle)
                    .tint(Color.ink)
                }

                if showsInvalid {
                    Label(String(localized: "That doesn't look like a web address."), systemImage: "exclamationmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }

                Button("Add", action: submit)
                    .buttonStyle(PrimaryButtonStyle(isEnabled: !link.isEmpty))
                    .disabled(link.isEmpty)

                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.top, 8)
            .background(Color.canvas)
            .navigationTitle(Text("Add from a link"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(300)])
        .onAppear { isFocused = true }
    }

    private func submit() {
        guard let url = ProductLinkImporter.normalisedURL(from: link) else {
            withAnimation { showsInvalid = true }
            return
        }
        dismiss()
        onSubmit(url)
    }
}
