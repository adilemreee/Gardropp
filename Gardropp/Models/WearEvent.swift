import Foundation
import SwiftData

/// One "I wore this today" entry, used by the calendar and the stats screen.
@Model
final class WearEvent {
    var id: UUID = UUID()
    var date: Date = Date.now
    var outfitTitle: String = ""
    var items: [ClothingItem] = []

    init(date: Date = .now, outfitTitle: String = "", items: [ClothingItem] = []) {
        self.id = UUID()
        self.date = Calendar.current.startOfDay(for: date)
        self.outfitTitle = outfitTitle
        self.items = items
    }
}
