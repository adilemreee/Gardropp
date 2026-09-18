import SwiftData
import SwiftUI

struct ProfileView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AISettings.self) private var aiSettings
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [ClothingItem]
    @Query(sort: \StorageLocation.createdAt) private var locations: [StorageLocation]

    @State private var isAddingLocation = false
    @State private var newLocationName = ""

    var body: some View {
        @Bindable var settings = settings

        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Profile")
                        .font(.system(size: 32, weight: .bold))
                        .padding(.top, 12)

                    card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Your name").font(.system(size: 13, weight: .semibold))
                            TextField(String(localized: "What should I call you?"), text: $settings.displayName)
                                .font(.system(size: 16))
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                                .background(Color.surfaceElevated.opacity(0.6), in: .rect(cornerRadius: 12))
                        }
                    }

                    card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Your style").font(.system(size: 13, weight: .semibold))
                            Text("The stylist leans on these when it picks outfits.")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.textSecondary)
                            FlowChips(
                                options: StyleTag.allCases,
                                isSelected: { settings.preferredStyles.contains($0) },
                                title: { $0.title }
                            ) { tag in
                                if let index = settings.preferredStyles.firstIndex(of: tag) {
                                    settings.preferredStyles.remove(at: index)
                                } else {
                                    settings.preferredStyles.append(tag)
                                }
                            }
                        }
                    }

                    NavigationLink {
                        AISettingsView()
                    } label: {
                        card {
                            HStack(spacing: 12) {
                                Image(systemName: "sparkles").font(.system(size: 16, weight: .medium))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("AI engine").font(.system(size: 15, weight: .semibold))
                                    Text(engineSummary)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.textSecondary)
                            }
                            .foregroundStyle(Color.textPrimary)
                        }
                    }
                    .buttonStyle(.plain)

                    card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Where you keep things").font(.system(size: 13, weight: .semibold))
                            ForEach(locations) { location in
                                HStack(spacing: 10) {
                                    Image(systemName: location.symbol)
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color.textSecondary)
                                        .frame(width: 20)
                                    Text(location.name).font(.system(size: 15))
                                    Spacer()
                                    Text(verbatim: "\(items.filter { $0.locationName == location.name }.count)")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color.textSecondary)
                                    Button {
                                        modelContext.delete(location)
                                        try? modelContext.save()
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(Color.textSecondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            Button {
                                isAddingLocation = true
                            } label: {
                                Label("Add a place", systemImage: "plus")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color.textPrimary)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 2)
                        }
                    }

                    card {
                        Toggle(isOn: $settings.usesCelsius) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Celsius").font(.system(size: 15, weight: .medium))
                                Text("Turn off for Fahrenheit")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        .tint(Color.ink)
                    }

                    Text("\(items.count) items in your wardrobe")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Theme.Spacing.gutter)
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
            .background(Color.canvas)
        }
        .alert(Text("New place"), isPresented: $isAddingLocation) {
            TextField(String(localized: "e.g. Bedroom wardrobe"), text: $newLocationName)
            Button("Cancel", role: .cancel) { newLocationName = "" }
            Button("Add") {
                let trimmed = newLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
                newLocationName = ""
                guard !trimmed.isEmpty else { return }
                modelContext.insert(StorageLocation(name: trimmed))
                try? modelContext.save()
            }
        }
        .task {
            if locations.isEmpty {
                for entry in StorageLocation.defaults {
                    modelContext.insert(StorageLocation(name: entry.name, symbol: entry.symbol))
                }
                try? modelContext.save()
            }
        }
    }

    private var engineSummary: String {
        let kind = aiSettings.provider
        guard kind.requiresKey else { return kind.displayName }
        return aiSettings.hasKey(for: kind)
            ? "\(kind.displayName) · \(aiSettings.model(for: kind))"
            : String(format: String(localized: "%@ · no key yet"), kind.displayName)
    }

    private func card(@ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .cardBackground(Theme.Radius.tile)
    }
}

/// Wrapping row of selectable chips.
struct FlowChips<Option: Identifiable & Hashable>: View {
    let options: [Option]
    let isSelected: (Option) -> Bool
    let title: (Option) -> String
    let toggle: (Option) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(options) { option in
                Button { toggle(option) } label: {
                    ChipLabel(title: title(option), isSelected: isSelected(option))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Minimal wrapping layout — chips flow onto the next line when they run out of room.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var rows: CGFloat = 1
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        var total: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                total += rowHeight + spacing
                rows += 1
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: total + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
