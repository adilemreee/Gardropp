import Foundation
import UIKit

/// Reads a shop's product page and pulls out the garment: its photo, name and
/// brand. Nearly every store publishes these as JSON-LD `Product` data or as
/// Open Graph tags for link previews, so no site-specific scraping is needed.
enum ProductLinkImporter {

    struct Product {
        var title: String?
        var brand: String?
        var colorName: String?
        var imageURL: URL?
        var siteName: String?
    }

    enum ImportError: LocalizedError {
        case invalidURL
        case unreachable
        case noGarmentFound

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                String(localized: "That doesn't look like a web address.")
            case .unreachable:
                String(localized: "The page could not be opened.")
            case .noGarmentFound:
                String(localized: "No garment photo was found on that page. Save the photo and add it from your library instead.")
            }
        }
    }

    // MARK: - Entry point

    static func normalisedURL(from text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.lowercased().hasPrefix("http") { trimmed = "https://" + trimmed }
        // A bare word is not an address, however willing URL is to accept it.
        guard let url = URL(string: trimmed), let host = url.host, host.contains(".") else { return nil }
        return url
    }

    /// Fetches the page, reads its product metadata, then downloads the photo.
    /// Shops that answer with a bot challenge instead of markup are retried in
    /// a real web view, which clears the challenge the way a browser does.
    @MainActor
    static func load(_ url: URL) async throws -> (product: Product, image: UIImage) {
        do {
            return try await loadDirectly(url)
        } catch {
            guard let html = await WebProductLoader().html(for: url) else { throw error }
            let product = parse(html: html, pageURL: url)
            guard let imageURL = product.imageURL else { throw ImportError.noGarmentFound }
            return (product, try await downloadImage(imageURL, referer: url))
        }
    }

    private static func loadDirectly(_ url: URL) async throws -> (product: Product, image: UIImage) {
        var request = URLRequest(url: url, timeoutInterval: 25)
        // Shops serve their full markup — including the link-preview tags — to browsers.
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
            throw ImportError.unreachable
        }
        guard let html = decodeHTML(data) else { throw ImportError.unreachable }

        let product = parse(html: html, pageURL: http.url ?? url)
        guard let imageURL = product.imageURL else { throw ImportError.noGarmentFound }
        return (product, try await downloadImage(imageURL, referer: url))
    }

    private static func downloadImage(_ imageURL: URL, referer: URL) async throws -> UIImage {
        var request = URLRequest(url: imageURL, timeoutInterval: 25)
        request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let image = UIImage(data: data) else { throw ImportError.noGarmentFound }
        return image
    }

    // MARK: - Parsing

    static func parse(html: String, pageURL: URL) -> Product {
        var product = Product()

        // JSON-LD is the richest source when a shop provides it.
        for block in jsonLDObjects(in: html) {
            guard let node = findProduct(in: block) else { continue }
            product.title = (node["name"] as? String)?.cleanedText
            product.brand = brandName(from: node["brand"])
            product.colorName = (node["color"] as? String)?.cleanedText
            if let image = firstImage(from: node["image"]) {
                product.imageURL = URL(string: image, relativeTo: pageURL)?.absoluteURL
            }
            break
        }

        // Open Graph fills whatever is still missing.
        let meta = metaTags(in: html)
        if product.imageURL == nil, let image = meta["og:image"] ?? meta["twitter:image"] {
            product.imageURL = URL(string: image.cleanedText, relativeTo: pageURL)?.absoluteURL
        }
        if product.title == nil {
            product.title = (meta["og:title"] ?? meta["twitter:title"] ?? titleTag(in: html))?.cleanedText
        }
        if product.brand == nil {
            product.brand = (meta["product:brand"] ?? meta["og:brand"])?.cleanedText
        }
        product.siteName = meta["og:site_name"]?.cleanedText ?? pageURL.host

        return product
    }

    private static func decodeHTML(_ data: Data) -> String? {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? String(data: data, encoding: .windowsCP1254)
    }

    // MARK: JSON-LD

    private static func jsonLDObjects(in html: String) -> [Any] {
        var found: [Any] = []
        var cursor = html[...]

        while let open = cursor.range(of: "<script", options: .caseInsensitive) {
            let afterOpen = cursor[open.upperBound...]
            guard let tagEnd = afterOpen.range(of: ">") else { break }
            let attributes = afterOpen[..<tagEnd.lowerBound].lowercased()
            let body = afterOpen[tagEnd.upperBound...]

            guard let close = body.range(of: "</script", options: .caseInsensitive) else { break }
            if attributes.contains("application/ld+json") {
                let json = String(body[..<close.lowerBound])
                if let data = json.data(using: .utf8),
                   let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                    found.append(object)
                }
            }
            cursor = body[close.lowerBound...]
        }
        return found
    }

    /// Product data is often nested inside `@graph` or an array of entities.
    private static func findProduct(in json: Any) -> [String: Any]? {
        if let object = json as? [String: Any] {
            if isProduct(object["@type"]) { return object }
            for value in object.values {
                if let match = findProduct(in: value) { return match }
            }
        }
        if let array = json as? [Any] {
            for value in array {
                if let match = findProduct(in: value) { return match }
            }
        }
        return nil
    }

    private static func isProduct(_ type: Any?) -> Bool {
        if let single = type as? String { return single.caseInsensitiveCompare("Product") == .orderedSame }
        if let many = type as? [String] { return many.contains { $0.caseInsensitiveCompare("Product") == .orderedSame } }
        return false
    }

    private static func brandName(from value: Any?) -> String? {
        if let name = value as? String { return name.cleanedText }
        if let object = value as? [String: Any] { return (object["name"] as? String)?.cleanedText }
        if let array = value as? [Any] { return array.compactMap { brandName(from: $0) }.first }
        return nil
    }

    private static func firstImage(from value: Any?) -> String? {
        if let single = value as? String { return single.cleanedText }
        if let array = value as? [Any] { return array.compactMap { firstImage(from: $0) }.first }
        if let object = value as? [String: Any] { return firstImage(from: object["url"] ?? object["contentUrl"]) }
        return nil
    }

    // MARK: Meta tags

    private static func metaTags(in html: String) -> [String: String] {
        var tags: [String: String] = [:]
        var cursor = html[...]

        while let open = cursor.range(of: "<meta", options: .caseInsensitive) {
            let rest = cursor[open.upperBound...]
            guard let end = rest.range(of: ">") else { break }
            let tag = String(rest[..<end.lowerBound])
            if let key = attribute("property", in: tag) ?? attribute("name", in: tag),
               let content = attribute("content", in: tag) {
                let lowered = key.lowercased()
                if tags[lowered] == nil { tags[lowered] = content }
            }
            cursor = rest[end.upperBound...]
        }
        return tags
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let keyRange = tag.range(of: name + "=", options: .caseInsensitive) else { return nil }
        var rest = tag[keyRange.upperBound...]
        guard let quote = rest.first, quote == "\"" || quote == "'" else { return nil }
        rest = rest.dropFirst()
        guard let closing = rest.firstIndex(of: quote) else { return nil }
        return String(rest[..<closing])
    }

    private static func titleTag(in html: String) -> String? {
        guard let open = html.range(of: "<title", options: .caseInsensitive),
              let tagEnd = html[open.upperBound...].range(of: ">"),
              let close = html[tagEnd.upperBound...].range(of: "</title", options: .caseInsensitive) else { return nil }
        return String(html[tagEnd.upperBound..<close.lowerBound])
    }
}

private extension String {
    /// Turns `&#124;` and `&#x27;` style escapes back into characters.
    var decodingNumericEntities: String {
        guard contains("&#") else { return self }
        var output = ""
        var rest = self[...]

        while let start = rest.range(of: "&#") {
            output += rest[..<start.lowerBound]
            let body = rest[start.upperBound...]
            guard let end = body.firstIndex(of: ";") else {
                output += rest[start.lowerBound...]
                return output
            }
            let digits = body[..<end]
            let isHex = digits.first == "x" || digits.first == "X"
            let number = isHex ? digits.dropFirst() : digits
            if let value = UInt32(number, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(value) {
                output.append(Character(scalar))
            }
            rest = body[body.index(after: end)...]
        }
        return output + rest
    }

    /// Collapses whitespace and turns the handful of HTML entities that show up
    /// in product names back into characters.
    var cleanedText: String {
        var text = self
        let entities = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&apos;": "'", "&#39;": "'", "&#x27;": "'", "&nbsp;": " ",
            "&ndash;": "–", "&mdash;": "—", "&hellip;": "…"
        ]
        for (entity, character) in entities {
            text = text.replacingOccurrences(of: entity, with: character, options: .caseInsensitive)
        }
        text = text.replacingOccurrences(of: "\\u003C", with: "<")
        text = text.decodingNumericEntities
        return text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
