import SwiftData
import SwiftUI

/// "My wardrobe": stats at the top, then every garment grouped by category.
struct WardrobeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClothingItem.createdAt, order: .reverse) private var items: [ClothingItem]
    @Query private var outfits: [Outfit]

    @State private var search = ""
    @State private var categoryFilter: ItemCategory?
    @State private var showsFavouritesOnly = false
    @State private var isScanning = false
    @State private var selectedItem: ClothingItem?
    @State private var showsStats = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    statTiles
                    moreStatsRow
                    searchRow
                    categoryChips

                    if filtered.isEmpty {
                        EmptyStateView(
                            symbol: items.isEmpty ? "tshirt" : "magnifyingglass",
                            title: items.isEmpty ? "Your wardrobe is empty" : "Nothing matches",
                            message: items.isEmpty
                                ? "Scan your first garment to get started."
                                : "Try another search or filter.",
                            actionTitle: items.isEmpty ? "Scan a garment" : nil,
                            action: items.isEmpty ? { isScanning = true } : nil
                        )
                        .padding(.top, 30)
                    } else {
                        ForEach(groupedCategories, id: \.self) { category in
                            section(for: category)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.gutter)
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
            .background(Color.canvas)
            .navigationDestination(isPresented: $showsStats) { StatsView() }
            .navigationDestination(item: $selectedItem) { item in
                ItemDetailView(item: item)
            }
        }
        .fullScreenCover(isPresented: $isScanning) {
            ScanFlowView { _ in }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("My wardrobe")
                    .font(.system(size: 32, weight: .bold))
                Text(verbatim: "\(String(localized: "\(items.count) items")) · \(String(localized: "\(outfits.filter(\.isSaved).count) outfits"))")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Button {
                isScanning = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.onInk)
                    .frame(width: 42, height: 42)
                    .background(Color.ink, in: .circle)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 12)
    }

    // MARK: - Stats

    private var statTiles: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                statTile(symbol: "tshirt", value: "\(items.count)", caption: "Items")
                statTile(symbol: "square.grid.2x2", value: "\(outfits.filter(\.isSaved).count)", caption: "Outfits")
                statTile(symbol: "chart.bar", value: "\(wornPercentage)%", caption: "Items worn")
                statTile(symbol: "plus", value: "\(newThisMonth)", caption: "New this month")
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func statTile(symbol: String, value: String, caption: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.textPrimary)
            Text(value).font(.system(size: 22, weight: .semibold))
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(2)
        }
        .frame(width: 96, alignment: .leading)
        .padding(12)
        .cardBackground(Theme.Radius.tile)
    }

    private var moreStatsRow: some View {
        Button {
            showsStats = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 16, weight: .medium))
                VStack(alignment: .leading, spacing: 1) {
                    Text("More stats").font(.system(size: 15, weight: .semibold))
                    Text("Calendar, most-worn items and your colours")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
            }
            .foregroundStyle(Color.textPrimary)
            .padding(14)
            .cardBackground(Theme.Radius.tile)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filters

    private var searchRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textSecondary)
                TextField(String(localized: "Search items…"), text: $search)
                    .font(.system(size: 15))
                    .autocorrectionDisabled()
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .cardBackground(Theme.Radius.tile)

            Button {
                showsFavouritesOnly.toggle()
            } label: {
                Image(systemName: showsFavouritesOnly ? "heart.fill" : "slider.horizontal.3")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(showsFavouritesOnly ? Color.onInk : Color.textPrimary)
                    .frame(width: 46, height: 46)
                    .background(showsFavouritesOnly ? Color.ink : Color.surface, in: .rect(cornerRadius: Theme.Radius.tile))
            }
            .buttonStyle(.plain)
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Button { categoryFilter = nil } label: {
                    ChipLabel(title: String(localized: "All"), isSelected: categoryFilter == nil)
                }
                .buttonStyle(.plain)

                ForEach(ItemCategory.allCases) { category in
                    Button {
                        categoryFilter = categoryFilter == category ? nil : category
                    } label: {
                        ChipLabel(title: category.title, isSelected: categoryFilter == category)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Grid

    private func section(for category: ItemCategory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(category.title)
                .font(.system(size: 18, weight: .semibold))

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(filtered.filter { $0.category == category }) { item in
                    Button { selectedItem = item } label: {
                        ItemTile(item: item)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            item.isFavorite.toggle()
                        } label: {
                            Label(item.isFavorite ? "Remove from favourites" : "Add to favourites",
                                  systemImage: item.isFavorite ? "heart.slash" : "heart")
                        }
                        Button(role: .destructive) { delete(item) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Data

    private var filtered: [ClothingItem] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return items.filter { item in
            if showsFavouritesOnly, !item.isFavorite { return false }
            if let categoryFilter, item.category != categoryFilter { return false }
            guard !query.isEmpty else { return true }
            return item.name.lowercased().contains(query)
                || item.subcategory.lowercased().contains(query)
                || (item.brand?.lowercased().contains(query) ?? false)
                || item.colorName.lowercased().contains(query)
        }
    }

    private var groupedCategories: [ItemCategory] {
        ItemCategory.allCases.filter { category in filtered.contains { $0.category == category } }
    }

    private var wornPercentage: Int {
        guard !items.isEmpty else { return 0 }
        return Int((Double(items.filter { $0.wearCount > 0 }.count) / Double(items.count) * 100).rounded())
    }

    private var newThisMonth: Int {
        let start = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .distantPast
        return items.filter { $0.createdAt >= start }.count
    }

    private func delete(_ item: ClothingItem) {
        ImageStore.shared.delete(item.imageFilename)
        ImageStore.shared.delete(item.originalImageFilename)
        modelContext.delete(item)
        try? modelContext.save()
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.textSecondary)
                .padding(.bottom, 4)
            Text(title).font(.system(size: 18, weight: .semibold))
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 10)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
