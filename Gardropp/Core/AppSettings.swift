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
        static let personPhoto = "user.personPhoto"
        static let facePhoto = "user.facePhoto"
        static let bodyHeight = "user.bodyHeight"
        static let bodyBuild = "user.bodyBuild"
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

    /// Close-up of the user's face — the only photo of themselves they provide.
    var facePhotoFilename: String? {
        didSet {
            if let facePhotoFilename {
                UserDefaults.standard.set(facePhotoFilename, forKey: Keys.facePhoto)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.facePhoto)
            }
        }
    }

    /// Height of the stand-in body, in centimetres.
    var bodyHeightCM: Int {
        didSet { UserDefaults.standard.set(bodyHeightCM, forKey: Keys.bodyHeight) }
    }

    var bodyBuild: BodyBuild {
        didSet { UserDefaults.standard.set(bodyBuild.rawValue, forKey: Keys.bodyBuild) }
    }

    var bodySpec: BodySpec {
        BodySpec(heightCM: bodyHeightCM, build: bodyBuild)
    }

    /// The generated full-length stand-in that every try-on dresses.
    var personPhotoFilename: String? {
        didSet {
            if let personPhotoFilename {
                UserDefaults.standard.set(personPhotoFilename, forKey: Keys.personPhoto)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.personPhoto)
            }
        }
    }

    init() {
        let defaults = UserDefaults.standard
        displayName = defaults.string(forKey: Keys.displayName) ?? ""
        preferredStyles = (defaults.array(forKey: Keys.preferredStyles) as? [String] ?? ["casual", "minimal"])
            .compactMap(StyleTag.init(rawValue:))
        usesCelsius = defaults.object(forKey: Keys.usesCelsius) as? Bool ?? true
        hasOnboarded = defaults.bool(forKey: Keys.hasOnboarded)
        personPhotoFilename = defaults.string(forKey: Keys.personPhoto)
        facePhotoFilename = defaults.string(forKey: Keys.facePhoto)
        bodyHeightCM = defaults.object(forKey: Keys.bodyHeight) as? Int ?? BodySpec.default.heightCM
        bodyBuild = defaults.string(forKey: Keys.bodyBuild).flatMap(BodyBuild.init(rawValue:)) ?? BodySpec.default.build
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
