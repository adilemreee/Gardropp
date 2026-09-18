import SwiftUI

// MARK: - Category

enum ItemCategory: String, Codable, CaseIterable, Identifiable {
    case tops, bottoms, outerwear, dresses, footwear, accessories

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tops: String(localized: "Tops")
        case .bottoms: String(localized: "Bottoms")
        case .outerwear: String(localized: "Outerwear")
        case .dresses: String(localized: "Dresses")
        case .footwear: String(localized: "Footwear")
        case .accessories: String(localized: "Accessories")
        }
    }

    var symbol: String {
        switch self {
        case .tops: "tshirt"
        case .bottoms: "rectangle.portrait"
        case .outerwear: "jacket"
        case .dresses: "figure.dress.line.vertical.figure"
        case .footwear: "shoe"
        case .accessories: "handbag"
        }
    }

    /// Order the layers of an outfit are stacked in, top to bottom.
    var layerOrder: Int {
        switch self {
        case .outerwear: 0
        case .tops: 1
        case .dresses: 1
        case .bottoms: 2
        case .footwear: 3
        case .accessories: 4
        }
    }

    static func from(_ raw: String?) -> ItemCategory {
        guard let raw else { return .tops }
        let key = raw.lowercased().trimmingCharacters(in: .whitespaces)
        if let exact = ItemCategory(rawValue: key) { return exact }
        switch key {
        case "top", "shirt", "t-shirt", "tshirt", "tee", "polo", "sweater", "knitwear", "hoodie", "üst", "tişört":
            return .tops
        case "bottom", "pants", "trousers", "jeans", "shorts", "skirt", "alt", "pantolon":
            return .bottoms
        case "jacket", "coat", "blazer", "parka", "dış giyim", "mont", "ceket":
            return .outerwear
        case "dress", "jumpsuit", "elbise":
            return .dresses
        case "shoes", "shoe", "sneakers", "boots", "ayakkabı":
            return .footwear
        case "accessory", "bag", "hat", "belt", "scarf", "watch", "aksesuar":
            return .accessories
        default:
            return .tops
        }
    }
}

// MARK: - Style

enum StyleTag: String, Codable, CaseIterable, Identifiable {
    case casual, smart, formal, sport, party, street, minimal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .casual: String(localized: "Casual")
        case .smart: String(localized: "Smart casual")
        case .formal: String(localized: "Formal")
        case .sport: String(localized: "Sport")
        case .party: String(localized: "Party")
        case .street: String(localized: "Street")
        case .minimal: String(localized: "Minimal")
        }
    }

    static func from(_ raw: String?) -> StyleTag {
        guard let raw else { return .casual }
        let key = raw.lowercased().trimmingCharacters(in: .whitespaces)
        if let exact = StyleTag(rawValue: key) { return exact }
        if key.contains("smart") || key.contains("business") { return .smart }
        if key.contains("formal") || key.contains("klasik") { return .formal }
        if key.contains("sport") || key.contains("athle") || key.contains("spor") { return .sport }
        if key.contains("party") || key.contains("night") || key.contains("parti") { return .party }
        if key.contains("street") || key.contains("sokak") { return .street }
        if key.contains("minimal") { return .minimal }
        return .casual
    }
}

// MARK: - Occasion (used for outfit suggestions)

enum Occasion: String, Codable, CaseIterable, Identifiable {
    case everyday, work, party, sport

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everyday: String(localized: "Casual")
        case .work: String(localized: "Work")
        case .party: String(localized: "Party")
        case .sport: String(localized: "Sport")
        }
    }
}

// MARK: - Season

enum Season: String, Codable, CaseIterable, Identifiable {
    case spring, summer, autumn, winter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spring: String(localized: "Spring")
        case .summer: String(localized: "Summer")
        case .autumn: String(localized: "Autumn")
        case .winter: String(localized: "Winter")
        }
    }

    static func from(_ raw: String?) -> [Season] {
        guard let raw else { return Season.allCases }
        let key = raw.lowercased()
        if key.contains("all") || key.contains("year") || key.contains("tüm") { return Season.allCases }
        var found: [Season] = []
        if key.contains("spring") || key.contains("ilkbahar") || key.contains("s/s") { found.append(.spring) }
        if key.contains("summer") || key.contains("yaz") || key.contains("s/s") { found.append(.summer) }
        if key.contains("autumn") || key.contains("fall") || key.contains("sonbahar") || key.contains("f/w") { found.append(.autumn) }
        if key.contains("winter") || key.contains("kış") || key.contains("f/w") { found.append(.winter) }
        return found.isEmpty ? Season.allCases : Array(Set(found)).sorted { $0.sortIndex < $1.sortIndex }
    }

    var sortIndex: Int {
        switch self {
        case .spring: 0
        case .summer: 1
        case .autumn: 2
        case .winter: 3
        }
    }

    /// Comfortable outdoor temperature range in celsius.
    var temperatureRange: ClosedRange<Double> {
        switch self {
        case .spring: 10...22
        case .summer: 19...45
        case .autumn: 8...20
        case .winter: -20...12
        }
    }

    static func current(for date: Date = .now) -> Season {
        switch Calendar.current.component(.month, from: date) {
        case 3...5: .spring
        case 6...8: .summer
        case 9...11: .autumn
        default: .winter
        }
    }
}

// MARK: - Colour

enum ColorFamily: String, Codable, CaseIterable, Identifiable {
    case black, white, grey, beige, brown, red, orange, yellow, green, blue, purple, pink, multicolour

    var id: String { rawValue }

    var title: String {
        switch self {
        case .black: String(localized: "Black")
        case .white: String(localized: "White")
        case .grey: String(localized: "Grey")
        case .beige: String(localized: "Beige")
        case .brown: String(localized: "Brown")
        case .red: String(localized: "Red")
        case .orange: String(localized: "Orange")
        case .yellow: String(localized: "Yellow")
        case .green: String(localized: "Green")
        case .blue: String(localized: "Blue")
        case .purple: String(localized: "Purple")
        case .pink: String(localized: "Pink")
        case .multicolour: String(localized: "Multicolour")
        }
    }

    var swatch: Color {
        switch self {
        case .black: Color(red: 0.11, green: 0.11, blue: 0.12)
        case .white: Color(red: 0.96, green: 0.96, blue: 0.94)
        case .grey: Color(red: 0.55, green: 0.55, blue: 0.57)
        case .beige: Color(red: 0.85, green: 0.78, blue: 0.66)
        case .brown: Color(red: 0.45, green: 0.32, blue: 0.22)
        case .red: Color(red: 0.76, green: 0.22, blue: 0.20)
        case .orange: Color(red: 0.89, green: 0.49, blue: 0.19)
        case .yellow: Color(red: 0.92, green: 0.77, blue: 0.24)
        case .green: Color(red: 0.27, green: 0.42, blue: 0.31)
        case .blue: Color(red: 0.22, green: 0.35, blue: 0.60)
        case .purple: Color(red: 0.45, green: 0.32, blue: 0.60)
        case .pink: Color(red: 0.87, green: 0.60, blue: 0.66)
        case .multicolour: Color(red: 0.60, green: 0.55, blue: 0.50)
        }
    }

    /// True for colours that go with almost anything.
    var isNeutral: Bool {
        switch self {
        case .black, .white, .grey, .beige, .brown: true
        default: false
        }
    }

    static func from(_ raw: String?) -> ColorFamily {
        guard let raw else { return .multicolour }
        let key = raw.lowercased()
        if let exact = ColorFamily(rawValue: key) { return exact }
        let table: [(ColorFamily, [String])] = [
            (.black, ["black", "siyah", "onyx", "charcoal"]),
            (.white, ["white", "beyaz", "ivory", "cream", "krem", "ecru", "off-white"]),
            (.grey, ["grey", "gray", "gri", "silver", "slate"]),
            (.beige, ["beige", "bej", "sand", "tan", "khaki", "camel", "taupe", "stone"]),
            (.brown, ["brown", "kahve", "chocolate", "coffee", "mocha"]),
            (.red, ["red", "kırmızı", "burgundy", "bordo", "maroon", "wine", "crimson"]),
            (.orange, ["orange", "turuncu", "rust", "terracotta", "coral"]),
            (.yellow, ["yellow", "sarı", "mustard", "gold", "hardal"]),
            (.green, ["green", "yeşil", "olive", "oliva", "sage", "mint", "forest", "khaki green"]),
            (.blue, ["blue", "mavi", "navy", "lacivert", "denim", "indigo", "teal", "turquoise"]),
            (.purple, ["purple", "mor", "violet", "lilac", "lavender", "plum"]),
            (.pink, ["pink", "pembe", "rose", "fuchsia", "magenta", "salmon"])
        ]
        for (family, keys) in table where keys.contains(where: { key.contains($0) }) {
            return family
        }
        return .multicolour
    }
}
