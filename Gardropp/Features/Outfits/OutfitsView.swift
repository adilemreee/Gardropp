import SwiftData
import SwiftUI

struct OutfitsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Outfit> { $0.isSaved }, sort: \Outfit.createdAt, order: .reverse)
    private var outfits: [Outfit]
    @Query private var items: [ClothingItem]

    @State private var isBuilding = false
    @State private var selected: Outfit?

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Outfits").font(.system(size: 32, weight: .bold))
                            Text("\(outfits.count) outfits saved")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                        Button {
                            isBuilding = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.onInk)
                                .frame(width: 42, height: 42)
                                .background(Color.ink, in: .circle)
                        }
                        .buttonStyle(.plain)
                        .disabled(items.count < 2)
                    }
                    .padding(.top, 12)

                    if outfits.isEmpty {
                        EmptyStateView(
                            symbol: "hanger",
                            title: "No outfits yet",
                            message: "Like a suggestion on the home screen, or build one yourself.",
                            actionTitle: items.count >= 2 ? "Build an outfit" : nil,
                            action: items.count >= 2 ? { isBuilding = true } : nil
                        )
                        .padding(.top, 50)
                    } else {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(outfits) { outfit in
                                Button { selected = outfit } label: { card(outfit) }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(role: .destructive) { delete(outfit) } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.gutter)
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
            .background(Color.canvas)
            .navigationDestination(item: $selected) { outfit in
                OutfitDetailView(outfit: outfit)
            }
        }
        .sheet(isPresented: $isBuilding) {
            OutfitBuilderView()
        }
    }

    private func card(_ outfit: Outfit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            OutfitStackView(items: outfit.layeredItems, compact: true)
                .frame(height: 140)
                .padding(.vertical, 8)
            Text(outfit.title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(outfit.occasion.title)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textSecondary)
                if outfit.wearCount > 0 {
                    Text(verbatim: "· \(outfit.wearCount)×")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .cardBackground(Theme.Radius.tile)
    }

    private func delete(_ outfit: Outfit) {
        modelContext.delete(outfit)
        try? modelContext.save()
    }
}

// MARK: - Detail

struct OutfitDetailView: View {
    @Bindable var outfit: Outfit
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.showToast) private var showToast
    @State private var isTryingOn = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                OutfitStackView(items: outfit.layeredItems)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .cardBackground(Theme.Radius.sheet)

                VStack(alignment: .leading, spacing: 4) {
                    Text(outfit.title).font(.system(size: 22, weight: .semibold))
                    if !outfit.rationale.isEmpty {
                        Text(outfit.rationale)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                HStack(spacing: 8) {
                    ChipLabel(title: outfit.occasion.title)
                    if outfit.matchScore > 0 {
                        ChipLabel(title: String(format: String(localized: "%d%% match"), outfit.matchScore))
                    }
                    if outfit.wearCount > 0 {
                        ChipLabel(title: String(format: String(localized: "Worn %d×"), outfit.wearCount))
                    }
                }

                Text("Pieces").font(.system(size: 15, weight: .semibold))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 14) {
                    ForEach(outfit.layeredItems) { item in
                        ItemTile(item: item)
                    }
                }

                Button {
                    isTryingOn = true
                } label: {
                    Label("Try it on", systemImage: "person.crop.square")
                }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.top, 4)

                Button {
                    outfit.markWorn()
                    modelContext.insert(WearEvent(outfitTitle: outfit.title, items: outfit.items))
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
        .sheet(isPresented: $isTryingOn) {
            TryOnView(items: outfit.items, outfitTitle: outfit.title)
        }
        .navigationTitle(Text("Outfit"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        modelContext.delete(outfit)
                        try? modelContext.save()
                        dismiss()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
    }
}

// MARK: - Manual builder

struct OutfitBuilderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ClothingItem.createdAt, order: .reverse) private var items: [ClothingItem]

    @State private var title = ""
    @State private var occasion: Occasion = .everyday
    @State private var picked: Set<UUID> = []

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField(String(localized: "Outfit name"), text: $title)
                        .font(.system(size: 16))
                        .padding(14)
                        .cardBackground(Theme.Radius.tile)

                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(Occasion.allCases) { option in
                                Button { occasion = option } label: {
                                    ChipLabel(title: option.title, isSelected: occasion == option)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollIndicators(.hidden)

                    ForEach(ItemCategory.allCases.filter { category in items.contains { $0.category == category } }) { category in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(category.title).font(.system(size: 16, weight: .semibold))
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(items.filter { $0.category == category }) { item in
                                    Button { toggle(item) } label: {
                                        ItemTile(item: item)
                                            .overlay(alignment: .topTrailing) {
                                                if picked.contains(item.id) {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .font(.system(size: 18))
                                                        .foregroundStyle(Color.ink)
                                                        .padding(6)
                                                }
                                            }
                                            .opacity(picked.contains(item.id) ? 1 : 0.65)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.gutter)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(Color.canvas)
            .navigationTitle(Text("New outfit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(picked.count < 2)
                }
            }
        }
    }

    private func toggle(_ item: ClothingItem) {
        if picked.contains(item.id) { picked.remove(item.id) } else { picked.insert(item.id) }
    }

    private func save() {
        let chosen = items.filter { picked.contains($0.id) }
        let name = title.trimmingCharacters(in: .whitespaces)
        let outfit = Outfit(
            title: name.isEmpty ? String(localized: "My outfit") : name,
            occasion: occasion,
            items: chosen,
            generatedBy: String(localized: "You")
        )
        outfit.isSaved = true
        modelContext.insert(outfit)
        try? modelContext.save()
        dismiss()
    }
}
