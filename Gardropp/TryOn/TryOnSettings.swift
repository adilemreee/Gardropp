import Foundation
import Observation

/// Which try-on engines to use, and where their keys live.
@Observable
final class TryOnSettings {
    private enum Keys {
        static let engine = "tryon.engine"
        static let videoEngine = "tryon.videoEngine"
        static let model = "tryon.model."
        static let videoModel = "tryon.videoModel."
    }

    var engine: TryOnEngine {
        didSet { UserDefaults.standard.set(engine.rawValue, forKey: Keys.engine) }
    }

    var videoEngine: TryOnVideoEngine {
        didSet { UserDefaults.standard.set(videoEngine.rawValue, forKey: Keys.videoEngine) }
    }

    private var models: [String: String]

    init() {
        let defaults = UserDefaults.standard
        engine = defaults.string(forKey: Keys.engine).flatMap(TryOnEngine.init(rawValue:)) ?? .gemini
        videoEngine = defaults.string(forKey: Keys.videoEngine).flatMap(TryOnVideoEngine.init(rawValue:)) ?? .veo
        models = [:]
        for kind in TryOnEngine.allCases {
            if let value = defaults.string(forKey: Keys.model + kind.rawValue) { models[Keys.model + kind.rawValue] = value }
        }
        for kind in TryOnVideoEngine.allCases {
            if let value = defaults.string(forKey: Keys.videoModel + kind.rawValue) { models[Keys.videoModel + kind.rawValue] = value }
        }
    }

    // MARK: - Models

    func model(for engine: TryOnEngine) -> String {
        models[Keys.model + engine.rawValue] ?? engine.defaultModel
    }

    func setModel(_ model: String, for engine: TryOnEngine) {
        store(model, key: Keys.model + engine.rawValue, fallback: engine.defaultModel)
    }

    func model(for engine: TryOnVideoEngine) -> String {
        models[Keys.videoModel + engine.rawValue] ?? engine.defaultModel
    }

    func setModel(_ model: String, for engine: TryOnVideoEngine) {
        store(model, key: Keys.videoModel + engine.rawValue, fallback: engine.defaultModel)
    }

    private func store(_ model: String, key: String, fallback: String) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == fallback {
            models[key] = nil
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            models[key] = trimmed
            UserDefaults.standard.set(trimmed, forKey: key)
        }
    }

    // MARK: - Keys

    func apiKey(for account: String) -> String {
        KeychainStore.get(account) ?? ""
    }

    func setAPIKey(_ key: String, for account: String) {
        KeychainStore.set(key.trimmingCharacters(in: .whitespacesAndNewlines), for: account)
        let current = engine
        engine = current      // nudge observers
    }

    func hasKey(for engine: TryOnEngine) -> Bool { !apiKey(for: engine.keychainAccount).isEmpty }
    func hasKey(for engine: TryOnVideoEngine) -> Bool { !apiKey(for: engine.keychainAccount).isEmpty }

    var isConfigured: Bool { hasKey(for: engine) }
}
