import Foundation

// MARK: - Garment analysis

/// What every provider must return after looking at a garment photo.
struct GarmentAnalysis: Codable {
    var name: String
    var category: String
    var subcategory: String
    var brand: String?
    var colorName: String
    var colorHex: String?
    var style: String
    var seasons: [String]
    var material: String?
    var confidence: Double?

    static let placeholder = GarmentAnalysis(
        name: String(localized: "New item"),
        category: ItemCategory.tops.rawValue,
        subcategory: "",
        colorName: String(localized: "Grey"),
        style: StyleTag.casual.rawValue,
        seasons: Season.allCases.map(\.rawValue)
    )
}

/// Extra hints handed to the provider so results match the user's world.
struct AnalysisContext {
    var languageName: String
    var knownBrands: [String] = []
    /// What the garment's outline looks like, when it could be measured.
    var shape: GarmentShape?

    static var current: AnalysisContext {
        AnalysisContext(languageName: Locale.current.localizedString(forLanguageCode: Locale.current.language.languageCode?.identifier ?? "en") ?? "English")
    }
}

// MARK: - Outfit suggestions

struct OutfitItemSummary: Codable {
    var id: String
    var name: String
    var category: String
    var subcategory: String
    var color: String
    var colorFamily: String
    var style: String
    var seasons: [String]
    var brand: String?
    var wearCount: Int
}

struct OutfitRequest {
    var items: [OutfitItemSummary]
    var occasion: Occasion
    var temperature: Double?
    var weatherSummary: String?
    var preferredStyles: [String]
    var languageName: String
    var count: Int = 3
}

/// One suggested outfit, referencing wardrobe items by id.
struct OutfitSuggestionDTO: Codable {
    var title: String
    var itemIds: [String]
    var rationale: String
    var matchScore: Int
    var occasion: String?
}

struct OutfitSuggestionList: Codable {
    var outfits: [OutfitSuggestionDTO]
}

// MARK: - Prompts and schemas shared by every cloud provider

enum AIPrompts {

    static func garmentSystemPrompt(_ context: AnalysisContext) -> String {
        """
        You are a fashion cataloguing assistant for a personal wardrobe app.
        Look at the photo of a single garment and fill in its catalogue entry.

        Rules:
        - `name` is a short, natural shop-style label, 2 to 4 words, written in \(context.languageName). \
        Include the brand when you can read it (e.g. "Green Stüssy tee").
        - `category` must be exactly one of: tops, bottoms, outerwear, dresses, footwear, accessories.
        - `subcategory` is the specific garment type in \(context.languageName), e.g. "T-shirts", "Jeans", "Sneakers".
        - `brand` only when a logo or label is clearly readable, otherwise null. Never guess.
        - `colorName` is the everyday name of the dominant colour in \(context.languageName), e.g. "Olive green".
        - `colorHex` is that colour as #RRGGBB.
        - `style` must be exactly one of: casual, smart, formal, sport, party, street, minimal.
        - `seasons` is a subset of: spring, summer, autumn, winter. Pick every season the garment suits.
        - `material` is the likely fabric in \(context.languageName), or null when unclear.
        - `confidence` is 0 to 1, how sure you are overall.
        Answer with the structured tool/schema only, no prose.
        """
    }

    static let garmentUserPrompt = "Catalogue this garment."

    static func outfitSystemPrompt(_ request: OutfitRequest) -> String {
        var lines = [
            "You are a personal stylist. Build \(request.count) outfits using ONLY the wardrobe items given to you.",
            "Rules:",
            "- Reference items by their exact `id`. Never invent an id.",
            "- Each outfit needs at least a top and a bottom (or a dress), plus footwear when available.",
            "- Never put two items of the same category in one outfit, except accessories.",
            "- `matchScore` is 0-100: how well the outfit fits the user's taste, the weather and the occasion.",
            "- `rationale` is one short sentence in \(request.languageName) explaining why it works.",
            "- `title` is a 2-4 word name for the outfit in \(request.languageName).",
            "- Prefer items the user rarely wears when the result is still good.",
            "Occasion: \(request.occasion.rawValue)."
        ]
        if let temperature = request.temperature {
            lines.append("Outdoor temperature: \(Int(temperature))°C. Dress appropriately for it.")
        }
        if let weather = request.weatherSummary, !weather.isEmpty {
            lines.append("Weather: \(weather).")
        }
        if !request.preferredStyles.isEmpty {
            lines.append("The user describes their style as: \(request.preferredStyles.joined(separator: ", ")).")
        }
        return lines.joined(separator: "\n")
    }

    static func outfitUserPrompt(_ request: OutfitRequest) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = (try? encoder.encode(request.items)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return "Wardrobe:\n\(json)"
    }

    // MARK: JSON Schemas

    /// JSON Schema draft shape, used by Anthropic tools and OpenAI json_schema.
    static func garmentSchema(strict: Bool) -> [String: Any] {
        var schema: [String: Any] = [
            "type": "object",
            "properties": [
                "name": ["type": "string"],
                "category": ["type": "string", "enum": ItemCategory.allCases.map(\.rawValue)],
                "subcategory": ["type": "string"],
                "brand": ["type": strict ? ["string", "null"] : "string"],
                "colorName": ["type": "string"],
                "colorHex": ["type": strict ? ["string", "null"] : "string"],
                "style": ["type": "string", "enum": StyleTag.allCases.map(\.rawValue)],
                "seasons": ["type": "array", "items": ["type": "string", "enum": Season.allCases.map(\.rawValue)]],
                "material": ["type": strict ? ["string", "null"] : "string"],
                "confidence": ["type": "number"]
            ],
            "additionalProperties": false
        ]
        schema["required"] = strict
            ? ["name", "category", "subcategory", "brand", "colorName", "colorHex", "style", "seasons", "material", "confidence"]
            : ["name", "category", "subcategory", "colorName", "style", "seasons"]
        return schema
    }

    static func outfitSchema(strict: Bool) -> [String: Any] {
        let outfit: [String: Any] = [
            "type": "object",
            "properties": [
                "title": ["type": "string"],
                "itemIds": ["type": "array", "items": ["type": "string"]],
                "rationale": ["type": "string"],
                "matchScore": ["type": "integer"],
                "occasion": ["type": strict ? ["string", "null"] : "string"]
            ],
            "required": strict
                ? ["title", "itemIds", "rationale", "matchScore", "occasion"]
                : ["title", "itemIds", "rationale", "matchScore"],
            "additionalProperties": false
        ]
        return [
            "type": "object",
            "properties": ["outfits": ["type": "array", "items": outfit]],
            "required": ["outfits"],
            "additionalProperties": false
        ]
    }

    /// Gemini uses an OpenAPI subset with upper-case type names and no `additionalProperties`.
    static var geminiGarmentSchema: [String: Any] {
        [
            "type": "OBJECT",
            "properties": [
                "name": ["type": "STRING"],
                "category": ["type": "STRING", "enum": ItemCategory.allCases.map(\.rawValue)],
                "subcategory": ["type": "STRING"],
                "brand": ["type": "STRING", "nullable": true],
                "colorName": ["type": "STRING"],
                "colorHex": ["type": "STRING", "nullable": true],
                "style": ["type": "STRING", "enum": StyleTag.allCases.map(\.rawValue)],
                "seasons": ["type": "ARRAY", "items": ["type": "STRING", "enum": Season.allCases.map(\.rawValue)]],
                "material": ["type": "STRING", "nullable": true],
                "confidence": ["type": "NUMBER"]
            ],
            "required": ["name", "category", "subcategory", "colorName", "style", "seasons"]
        ]
    }

    static var geminiOutfitSchema: [String: Any] {
        [
            "type": "OBJECT",
            "properties": [
                "outfits": [
                    "type": "ARRAY",
                    "items": [
                        "type": "OBJECT",
                        "properties": [
                            "title": ["type": "STRING"],
                            "itemIds": ["type": "ARRAY", "items": ["type": "STRING"]],
                            "rationale": ["type": "STRING"],
                            "matchScore": ["type": "INTEGER"],
                            "occasion": ["type": "STRING", "nullable": true]
                        ],
                        "required": ["title", "itemIds", "rationale", "matchScore"]
                    ]
                ]
            ],
            "required": ["outfits"]
        ]
    }

    /// Plain-text description of the schema, for providers in JSON-object mode.
    static func schemaHint(_ schema: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys, .prettyPrinted]),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return "Reply with a single JSON object matching this schema, and nothing else:\n\(text)"
    }
}
