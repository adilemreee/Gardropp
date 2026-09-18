import SwiftData
import SwiftUI

/// "What are you wearing today?" — the stylist screen.
struct HomeView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AIService.self) private var ai
    @Environment(WeatherService.self) private var weather
    @Environment(\.modelContext) private var modelContext
    @Environment(\.showToast) private var showToast

    @Query(sort: \ClothingItem.createdAt, order: .reverse) private var items: [ClothingItem]
    @State private var model = SuggestionModel()
    @State private var isScanning = false
    @State private var tryOnSelection: TryOnSelection?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    topBar
                    greeting
                    occasionChips

                    if items.count < 2 {
                        EmptyStateView(
                            symbol: "sparkles",
                            title: "Two items and I can start",
                            message: "Scan a few garments and I'll put outfits together for you.",
                            actionTitle: "Scan a garment",
                            action: { isScanning = true }
                        )
                        .padding(.top, 40)
                    } else if model.isLoading && model.visible.isEmpty {
                        loadingCard
                    } else if let hero = model.visible.first {
                        sectionLabel("FOR YOU TODAY")
                        OutfitSuggestionCard(
                            suggestion: hero,
                            temperature: temperatureText,
                            onDismiss: { withAnimation(.snappy) { model.dismiss(hero) } },
                            onLike: { like(hero) },
                            onWear: { wear(hero) },
                            onTryOn: { tryOnSelection = TryOnSelection(items: hero.items, title: hero.title) }
                        )

                        if model.visible.count > 1 {
                            alternatives
                        }
                    } else {
                        EmptyStateView(
                            symbol: "hanger",
                            title: "No more ideas right now",
                            message: "Ask for a fresh set of outfits.",
                            actionTitle: "Try again",
                            action: { Task { await refresh(force: true) } }
                        )
                        .padding(.top, 30)
                    }

                    if let error = model.errorMessage, !model.visible.isEmpty {
                        FallbackBanner(message: error)
                    }
                }
                .padding(.horizontal, Theme.Spacing.gutter)
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
            .background(Color.canvas)
            .refreshable { await refresh(force: true) }
        }
        .task {
            weather.refresh()
            await refresh()
        }
        .onChange(of: items.count) { _, _ in Task { await refresh() } }
        .onChange(of: model.occasion) { _, _ in Task { await refresh() } }
        .fullScreenCover(isPresented: $isScanning) { ScanFlowView { _ in } }
        .sheet(item: $tryOnSelection) { selection in
            TryOnView(items: selection.items, outfitTitle: selection.title)
        }
    }

    // MARK: - Header

    private var topBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Gardropp")
                    .font(.system(size: 17, weight: .semibold))
                Text("YOUR PERSONAL STYLIST")
                    .font(.system(size: 9, weight: .medium))
                    .tracking(1.1)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            if let conditions = weather.conditions {
                HStack(spacing: 8) {
                    Image(systemName: conditions.symbol)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.textSecondary)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(conditions.formatted(celsius: settings.usesCelsius))
                            .font(.system(size: 15, weight: .semibold))
                        Text(conditions.rangeFormatted(celsius: settings.usesCelsius))
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .cardBackground(Theme.Radius.chip)
            }
        }
        .padding(.top, 12)
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(settings.greeting)
                .font(.system(size: 15))
                .foregroundStyle(Color.textSecondary)
            Text("What are you wearing today?")
                .font(.system(size: 34, weight: .bold))
                .lineSpacing(-4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var occasionChips: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Occasion.allCases) { occasion in
                        Button {
                            model.occasion = occasion
                        } label: {
                            ChipLabel(
                                title: occasion.title,
                                isSelected: model.occasion == occasion
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)

            Button {
                Task { await refresh(force: true) }
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(Color.surface, in: .circle)
            }
            .buttonStyle(.plain)
            .disabled(model.isLoading)
        }
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(Color.textSecondary)
    }

    private var loadingCard: some View {
        VStack(spacing: 14) {
            ProgressView().tint(Color.textSecondary)
            Text("Putting looks together…")
                .font(.system(size: 14))
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .cardBackground(Theme.Radius.card)
    }

    private var alternatives: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("You could also try these")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    Task { await refresh(force: true) }
                } label: {
                    Label("See others", systemImage: "arrow.trianglehead.2.clockwise")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(model.visible.dropFirst()) { suggestion in
                        Button {
                            wear(suggestion)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                OutfitStackView(items: suggestion.layered, compact: true)
                                    .frame(height: 118)
                                    .padding(.vertical, 6)
                                Text(suggestion.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.textPrimary)
                                    .lineLimit(1)
                                Text("\(suggestion.matchScore)% for you")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.textSecondary)
                            }
                            .padding(12)
                            .frame(width: 148)
                            .cardBackground(Theme.Radius.tile)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Data

    private var temperatureText: String? {
        weather.conditions.map { conditions in
            String(format: String(localized: "Ideal for %@"), conditions.formatted(celsius: settings.usesCelsius))
        }
    }

    private func refresh(force: Bool = false) async {
        await model.refreshIfNeeded(
            items: items,
            temperature: weather.conditions?.temperature,
            weatherSummary: weather.conditions?.summary,
            preferredStyles: settings.preferredStyles,
            ai: ai,
            force: force
        )
    }

    private func like(_ suggestion: SuggestedOutfit) {
        let outfit = Outfit(
            title: suggestion.title,
            rationale: suggestion.rationale,
            occasion: suggestion.occasion,
            matchScore: suggestion.matchScore,
            items: suggestion.items,
            generatedBy: suggestion.engine,
            suggestedForTemperature: weather.conditions?.temperature
        )
        outfit.isSaved = true
        outfit.isLiked = true
        modelContext.insert(outfit)
        try? modelContext.save()
        showToast(String(localized: "Saved to your outfits"), symbol: "heart.fill")
    }

    private func wear(_ suggestion: SuggestedOutfit) {
        for item in suggestion.items { item.markWorn() }
        modelContext.insert(WearEvent(outfitTitle: suggestion.title, items: suggestion.items))
        try? modelContext.save()
        withAnimation(.snappy) { model.dismiss(suggestion) }
        showToast(String(localized: "Have a good day!"))
    }
}

// MARK: - The hero card

struct OutfitSuggestionCard: View {
    let suggestion: SuggestedOutfit
    var temperature: String?
    var onDismiss: () -> Void
    var onLike: () -> Void
    var onWear: () -> Void
    var onTryOn: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            OutfitStackView(items: suggestion.layered)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            VStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(suggestion.title)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text("\(suggestion.matchScore)% for you")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                }

                HStack(spacing: 8) {
                    reason(symbol: "heart", text: suggestion.rationale)
                    if let temperature {
                        reason(symbol: "cloud", text: temperature)
                    }
                }

                HStack(spacing: 8) {
                    secondaryAction("Dismiss", symbol: "xmark", action: onDismiss)
                    secondaryAction("Like", symbol: "heart", action: onLike)
                    secondaryAction("Try on", symbol: "person.crop.square", action: onTryOn)
                }

                Button(action: onWear) {
                    Label("Wearing this today", systemImage: "checkmark.circle")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(14)
        .cardBackground(Theme.Radius.card)
    }

    private func secondaryAction(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Color.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.surfaceElevated.opacity(0.6), in: .rect(cornerRadius: Theme.Radius.chip))
        }
        .buttonStyle(.plain)
    }

    private func reason(symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11))
            Text(text).font(.system(size: 12)).lineLimit(3)
        }
        .foregroundStyle(Color.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


/// Wraps the picked outfit so it can drive an `item:` sheet.
private struct TryOnSelection: Identifiable {
    let id = UUID()
    let items: [ClothingItem]
    let title: String
}
