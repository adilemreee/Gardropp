import Foundation
import Observation

/// Which engine analyses garments, which model it uses, and where the keys live.
@Observable
final class AISettings {
    private enum Keys {
        static let provider = "ai.provider"
        static let model = "ai.model."
    }

    var provider: AIProviderKind {
        didSet { UserDefaults.standard.set(provider.rawValue, forKey: Keys.provider) }
    }

    private var modelOverrides: [AIProviderKind: String]

    init() {
        let stored = UserDefaults.standard.string(forKey: Keys.provider)
        provider = stored.flatMap(AIProviderKind.init(rawValue:)) ?? .onDevice
        modelOverrides = [:]
        for kind in AIProviderKind.allCases {
            if let model = UserDefaults.standard.string(forKey: Keys.model + kind.rawValue), !model.isEmpty {
                modelOverrides[kind] = model
            }
        }
    }

    // MARK: - Models

    func model(for kind: AIProviderKind) -> String {
        modelOverrides[kind] ?? kind.defaultModel
    }

    func setModel(_ model: String, for kind: AIProviderKind) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == kind.defaultModel {
            modelOverrides[kind] = nil
            UserDefaults.standard.removeObject(forKey: Keys.model + kind.rawValue)
        } else {
            modelOverrides[kind] = trimmed
            UserDefaults.standard.set(trimmed, forKey: Keys.model + kind.rawValue)
        }
    }

    // MARK: - Keys

    func apiKey(for kind: AIProviderKind) -> String {
        KeychainStore.get(kind.keychainAccount) ?? ""
    }

    func setAPIKey(_ key: String, for kind: AIProviderKind) {
        KeychainStore.set(key.trimmingCharacters(in: .whitespacesAndNewlines), for: kind.keychainAccount)
        // The stored key is not observed directly; bump the provider to refresh views.
        let current = provider
        provider = current
    }

    func hasKey(for kind: AIProviderKind) -> Bool {
        !kind.requiresKey || !apiKey(for: kind).isEmpty
    }

    /// True when the selected engine is ready to be used as-is.
    var isConfigured: Bool { hasKey(for: provider) }

    // MARK: - Factory

    func makeProvider(_ kind: AIProviderKind? = nil) -> AIProvider {
        let kind = kind ?? provider
        let model = model(for: kind)
        let key = apiKey(for: kind)
        guard !kind.requiresKey || !key.isEmpty else { return OnDeviceProvider() }

        switch kind {
        case .onDevice: return OnDeviceProvider()
        case .anthropic: return AnthropicProvider(model: model, apiKey: key)
        case .openai: return OpenAICompatibleProvider.openAI(model: model, apiKey: key)
        case .deepseek: return OpenAICompatibleProvider.deepSeek(model: model, apiKey: key)
        case .gemini: return GeminiProvider(model: model, apiKey: key)
        }
    }

    /// The engine that will actually run a photo analysis — a text-only model
    /// silently hands the job back to the on-device engine.
    var visionProviderKind: AIProviderKind {
        guard hasKey(for: provider), provider.supportsVision(model: model(for: provider)) else { return .onDevice }
        return provider
    }
}
