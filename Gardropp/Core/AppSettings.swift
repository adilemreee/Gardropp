import Foundation
import Observation

/// Lightweight user preferences that are not worth a SwiftData model.
@Observable
final class AppSettings {
    private enum Keys {
        static let displayName = "user.displayName"
        static let preferredStyles = "user.preferredStyles"
        static let usesCelsius = "user.usesCelsius"
        static let hasOnboarded = "user.hasOnboarded"
    }

    var displayName: String {
        didSet { UserDefaults.standard.set(displayName, forKey: Keys.displayName) }
    }

    var preferredStyles: [StyleTag] {
        didSet {
            UserDefaults.standard.set(preferredStyles.map(\.rawValue), forKey: Keys.preferredStyles)
        }
    }

    var usesCelsius: Bool {
        didSet { UserDefaults.standard.set(usesCelsius, forKey: Keys.usesCelsius) }
    }

    var hasOnboarded: Bool {
        didSet { UserDefaults.standard.set(hasOnboarded, forKey: Keys.hasOnboarded) }
    }

    init() {
        let defaults = UserDefaults.standard
        displayName = defaults.string(forKey: Keys.displayName) ?? ""
        preferredStyles = (defaults.array(forKey: Keys.preferredStyles) as? [String] ?? ["casual", "minimal"])
            .compactMap(StyleTag.init(rawValue:))
        usesCelsius = defaults.object(forKey: Keys.usesCelsius) as? Bool ?? true
        hasOnboarded = defaults.bool(forKey: Keys.hasOnboarded)
    }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = switch hour {
        case 5..<12: String(localized: "Good morning")
        case 12..<18: String(localized: "Good afternoon")
        default: String(localized: "Good evening")
        }
        return displayName.isEmpty ? part : "\(part), \(displayName)"
    }
}
