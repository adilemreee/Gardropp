import Foundation

/// A small rule-based stylist. Used by the on-device provider and as the
/// fallback whenever a cloud request fails, so the home screen is never empty.
enum LocalOutfitEngine {

    static func suggest(_ request: OutfitRequest) -> [OutfitSuggestionDTO] {
        let items = request.items
        let tops = items.filter { ItemCategory.from($0.category) == .tops }
        let bottoms = items.filter { ItemCategory.from($0.category) == .bottoms }
        let dresses = items.filter { ItemCategory.from($0.category) == .dresses }
        let shoes = items.filter { ItemCategory.from($0.category) == .footwear }
        let outerwear = items.filter { ItemCategory.from($0.category) == .outerwear }

        var candidates: [(dto: OutfitSuggestionDTO, score: Double)] = []

        var bases: [[OutfitItemSummary]] = []
        for top in tops {
            for bottom in bottoms { bases.append([top, bottom]) }
        }
        for dress in dresses { bases.append([dress]) }

        let needsLayer = (request.temperature ?? 18) < 14

        for var base in bases {
            if let shoe = bestMatch(in: shoes, for: base, request: request) { base.append(shoe) }
            if needsLayer, let layer = bestMatch(in: outerwear, for: base, request: request) { base.append(layer) }

            let score = score(base, request: request)
            candidates.append((
                OutfitSuggestionDTO(
                    title: title(for: base),
                    itemIds: base.map(\.id),
                    rationale: rationale(for: base, request: request),
                    matchScore: Int((score * 100).rounded()),
                    occasion: request.occasion.rawValue
                ),
                score
            ))
        }

        // Keep the best, but avoid returning three variations of the same top.
        var chosen: [OutfitSuggestionDTO] = []
        var usedLeads: Set<String> = []
        for candidate in candidates.sorted(by: { $0.score > $1.score }) {
            guard let lead = candidate.dto.itemIds.first else { continue }
            if usedLeads.contains(lead) && chosen.count < request.count { continue }
            usedLeads.insert(lead)
            chosen.append(candidate.dto)
            if chosen.count == request.count { break }
        }
        if chosen.isEmpty {
            chosen = candidates.sorted { $0.score > $1.score }.prefix(request.count).map(\.dto)
        }
        return chosen
    }

    // MARK: - Scoring

    private static func bestMatch(
        in pool: [OutfitItemSummary],
        for base: [OutfitItemSummary],
        request: OutfitRequest
    ) -> OutfitItemSummary? {
        pool.max { lhs, rhs in
            score(base + [lhs], request: request) < score(base + [rhs], request: request)
        }
    }

    private static func score(_ items: [OutfitItemSummary], request: OutfitRequest) -> Double {
        guard !items.isEmpty else { return 0 }

        // Colour harmony: neutrals go with everything, one accent is ideal.
        let families = items.map { ColorFamily.from($0.colorFamily) }
        let accents = families.filter { !$0.isNeutral }
        var colorScore: Double
        switch accents.count {
        case 0: colorScore = 0.8
        case 1: colorScore = 1.0
        case 2: colorScore = Set(accents).count == 1 ? 0.9 : 0.55
        default: colorScore = 0.3
        }
        if Set(families).count == 1 && families.count > 2 { colorScore = min(colorScore, 0.75) }

        // Style coherence.
        let styles = items.map { StyleTag.from($0.style) }
        let styleScore = Set(styles).count == 1 ? 1.0 : (Set(styles).count == 2 ? 0.8 : 0.55)

        // Occasion fit.
        let occasionScore = items.map { occasionFit(StyleTag.from($0.style), request.occasion) }.reduce(0, +) / Double(items.count)

        // Weather fit.
        var weatherScore = 1.0
        if let temperature = request.temperature {
            weatherScore = items.map { item in
                let seasons = item.seasons.compactMap(Season.init(rawValue:))
                guard !seasons.isEmpty else { return 0.6 }
                if seasons.contains(where: { $0.temperatureRange.contains(temperature) }) { return 1.0 }
                let distance = seasons.map { range -> Double in
                    temperature < range.temperatureRange.lowerBound
                        ? range.temperatureRange.lowerBound - temperature
                        : temperature - range.temperatureRange.upperBound
                }.min() ?? 0
                return max(0.1, 1 - distance / 15)
            }.reduce(0, +) / Double(items.count)
        }

        // Taste: does it use the styles the user says they like?
        var tasteScore = 0.7
        if !request.preferredStyles.isEmpty {
            let preferred = Set(request.preferredStyles.map { StyleTag.from($0) })
            let hits = styles.filter { preferred.contains($0) }.count
            tasteScore = 0.6 + 0.4 * (Double(hits) / Double(styles.count))
        }

        // Nudge towards clothes that sit unworn.
        let averageWear = Double(items.map(\.wearCount).reduce(0, +)) / Double(items.count)
        let freshness = max(0.6, 1 - averageWear / 20)

        // Completeness: a full look beats a half one.
        let categories = Set(items.map { ItemCategory.from($0.category) })
        let completeness = categories.contains(.footwear) ? 1.0 : 0.85

        return (colorScore * 0.26 + styleScore * 0.16 + occasionScore * 0.18
            + weatherScore * 0.22 + tasteScore * 0.1 + freshness * 0.04 + completeness * 0.04)
    }

    private static func occasionFit(_ style: StyleTag, _ occasion: Occasion) -> Double {
        switch occasion {
        case .everyday:
            switch style {
            case .casual, .street, .minimal: 1.0
            case .smart: 0.85
            case .sport: 0.7
            case .formal, .party: 0.4
            }
        case .work:
            switch style {
            case .smart, .formal, .minimal: 1.0
            case .casual: 0.6
            case .street: 0.4
            case .sport, .party: 0.2
            }
        case .party:
            switch style {
            case .party: 1.0
            case .smart, .street: 0.8
            case .formal, .minimal: 0.7
            case .casual: 0.5
            case .sport: 0.2
            }
        case .sport:
            switch style {
            case .sport: 1.0
            case .casual, .street: 0.6
            default: 0.2
            }
        }
    }

    // MARK: - Copy

    private static func title(for items: [OutfitItemSummary]) -> String {
        let families = items.map { ColorFamily.from($0.colorFamily) }
        if families.allSatisfy(\.isNeutral) { return String(localized: "Minimal and neutral colours") }
        let styles = Set(items.map { StyleTag.from($0.style) })
        if styles.count == 1, let style = styles.first { return style.title }
        if let accent = families.first(where: { !$0.isNeutral }) {
            return String(format: String(localized: "%@ accent"), accent.title)
        }
        return String(localized: "Everyday look")
    }

    private static func rationale(for items: [OutfitItemSummary], request: OutfitRequest) -> String {
        if let temperature = request.temperature {
            return String(format: String(localized: "Balanced colours, right for %d°"), Int(temperature.rounded()))
        }
        let families = items.map { ColorFamily.from($0.colorFamily) }
        return families.allSatisfy(\.isNeutral)
            ? String(localized: "Neutral tones that always work together")
            : String(localized: "One accent colour against neutrals")
    }
}
