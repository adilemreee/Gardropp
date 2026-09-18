import SwiftData
import SwiftUI

/// Calendar, most-worn items and the colours that actually fill your wardrobe.
struct StatsView: View {
    @Query(sort: \ClothingItem.createdAt, order: .reverse) private var items: [ClothingItem]
    @Query(sort: \WearEvent.date, order: .reverse) private var events: [WearEvent]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                calendarSection
                mostWornSection
                colourSection
                neglectedSection
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(Color.canvas)
        .navigationTitle(Text("Stats"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Calendar

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This month").font(.system(size: 18, weight: .semibold))
            let days = daysOfMonth
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(days, id: \.self) { day in
                    let worn = wornDays.contains(Calendar.current.startOfDay(for: day))
                    Text(verbatim: "\(Calendar.current.component(.day, from: day))")
                        .font(.system(size: 12, weight: worn ? .semibold : .regular))
                        .foregroundStyle(worn ? Color.onInk : Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(worn ? Color.ink : Color.surface, in: .rect(cornerRadius: 9))
                }
            }
            Text("\(wornDays.count) days logged this month")
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var daysOfMonth: [Date] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: .now) else { return [] }
        var days: [Date] = []
        var cursor = interval.start
        while cursor < interval.end {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    private var wornDays: Set<Date> {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: .now) else { return [] }
        return Set(events.filter { interval.contains($0.date) }.map { calendar.startOfDay(for: $0.date) })
    }

    // MARK: - Most worn

    private var mostWornSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Most worn").font(.system(size: 18, weight: .semibold))
            let top = items.filter { $0.wearCount > 0 }.sorted { $0.wearCount > $1.wearCount }.prefix(5)
            if top.isEmpty {
                Text("Nothing logged yet. Tap “Wearing this today” to start.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textSecondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(top)) { item in
                        HStack(spacing: 12) {
                            GarmentThumbnail(filename: item.imageFilename, fallbackSymbol: item.category.symbol, padding: 6)
                                .frame(width: 44, height: 44)
                                .background(Color.surfaceElevated.opacity(0.5), in: .rect(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name).font(.system(size: 14, weight: .medium)).lineLimit(1)
                                Text(item.subcategory).font(.system(size: 11)).foregroundStyle(Color.textSecondary)
                            }
                            Spacer()
                            Text(verbatim: "\(item.wearCount)×")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.textSecondary)
                        }
                        .padding(10)
                        .cardBackground(Theme.Radius.tile)
                    }
                }
            }
        }
    }

    // MARK: - Colours

    private var colourSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your colours").font(.system(size: 18, weight: .semibold))
            let counts = Dictionary(grouping: items, by: \.colorFamily)
                .mapValues(\.count)
                .sorted { $0.value > $1.value }
            if counts.isEmpty {
                Text("Add a few items to see your palette.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textSecondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(counts.prefix(6), id: \.key) { family, count in
                        HStack(spacing: 10) {
                            Circle().fill(family.swatch).frame(width: 14, height: 14)
                                .overlay(Circle().stroke(Color.hairline, lineWidth: 0.5))
                            Text(family.title).font(.system(size: 14))
                            Spacer()
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.surfaceElevated.opacity(0.6))
                                    Capsule().fill(family.swatch)
                                        .frame(width: proxy.size.width * fraction(count))
                                }
                            }
                            .frame(width: 110, height: 8)
                            Text(verbatim: "\(count)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.textSecondary)
                                .frame(width: 24, alignment: .trailing)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .cardBackground(Theme.Radius.tile)
                    }
                }
            }
        }
    }

    private func fraction(_ count: Int) -> CGFloat {
        let maximum = Dictionary(grouping: items, by: \.colorFamily).values.map(\.count).max() ?? 1
        return CGFloat(count) / CGFloat(max(maximum, 1))
    }

    // MARK: - Neglected

    private var neglectedSection: some View {
        let unworn = items.filter { $0.wearCount == 0 }
        return Group {
            if !unworn.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Never worn").font(.system(size: 18, weight: .semibold))
                    Text("\(unworn.count) items are still waiting for their day.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textSecondary)
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(unworn.prefix(10)) { item in
                                ItemTile(item: item).frame(width: 96)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
    }
}
