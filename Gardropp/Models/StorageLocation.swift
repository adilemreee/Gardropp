import Foundation
import SwiftData

/// Where a garment physically lives — "Bedroom wardrobe", "Storage box".
@Model
final class StorageLocation {
    var id: UUID = UUID()
    var name: String = ""
    var symbol: String = "archivebox"
    var createdAt: Date = Date.now

    init(name: String, symbol: String = "archivebox") {
        self.id = UUID()
        self.name = name
        self.symbol = symbol
        self.createdAt = .now
    }

    static let defaults: [(name: String, symbol: String)] = [
        (String(localized: "Bedroom wardrobe"), "cabinet"),
        (String(localized: "Storage"), "archivebox")
    ]
}
