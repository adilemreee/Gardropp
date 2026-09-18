import SwiftUI

/// Pick the engine that analyses photos and styles outfits, and keep its key.
struct AISettingsView: View {
    @Environment(AISettings.self) private var settings
    @Environment(AIService.self) private var ai

    @State private var draftKey = ""
    @State private var draftModel = ""
    @State private var editingKind: AIProviderKind?
    @State private var testState: TestState = .idle

    private enum TestState: Equatable {
        case idle, running, success(String), failure(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Every engine does the same two jobs: read a garment from a photo, and put outfits together. On-device works offline and for free; the others are usually sharper at brands and naming.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textSecondary)

                ForEach(AIProviderKind.allCases) { kind in
                    providerCard(kind)
                }
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(Color.canvas)
        .navigationTitle(Text("AI engine"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func providerCard(_ kind: AIProviderKind) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                settings.provider = kind
                if editingKind != kind { open(kind) }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: settings.provider == kind ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(settings.provider == kind ? Color.textPrimary : Color.textSecondary)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(kind.displayName).font(.system(size: 16, weight: .semibold))
                            if kind.requiresKey && settings.hasKey(for: kind) {
                                Image(systemName: "key.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.positive)
                            }
                        }
                        Text(kind.blurb)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Color.textPrimary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if kind.requiresKey {
                if editingKind == kind {
                    configuration(for: kind)
                } else {
                    Button {
                        open(kind)
                    } label: {
                        Text(settings.hasKey(for: kind) ? "Change key or model" : "Add API key")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.textPrimary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 30)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(Theme.Radius.tile)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.tile)
                .stroke(settings.provider == kind ? Color.textPrimary.opacity(0.35) : .clear, lineWidth: 1)
        }
    }

    @ViewBuilder
    private func configuration(for kind: AIProviderKind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("API key").font(.system(size: 12, weight: .semibold))
                SecureField(String(localized: "Paste your key"), text: $draftKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(size: 14, design: .monospaced))
                    .padding(10)
                    .background(Color.surfaceElevated.opacity(0.6), in: .rect(cornerRadius: 10))
                if let url = kind.consoleURL {
                    Link(destination: url) {
                        Text("Get a key ↗")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Model").font(.system(size: 12, weight: .semibold))
                HStack(spacing: 8) {
                    TextField(kind.defaultModel, text: $draftModel)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(size: 14, design: .monospaced))
                        .padding(10)
                        .background(Color.surfaceElevated.opacity(0.6), in: .rect(cornerRadius: 10))
                    Menu {
                        ForEach(kind.suggestedModels, id: \.self) { model in
                            Button(model) { draftModel = model }
                        }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 38, height: 38)
                            .background(Color.surfaceElevated.opacity(0.6), in: .rect(cornerRadius: 10))
                    }
                }
                if !kind.supportsVision(model: draftModel.isEmpty ? kind.defaultModel : draftModel) {
                    Label("This model can't read images — photo analysis will run on device.",
                          systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textSecondary)
                }
            }

            HStack(spacing: 10) {
                Button("Save") { save(kind) }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.onInk)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.ink, in: .capsule)

                Button {
                    Task { await test(kind) }
                } label: {
                    HStack(spacing: 6) {
                        if testState == .running { ProgressView().controlSize(.mini) }
                        Text("Test")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.surfaceElevated.opacity(0.6), in: .capsule)
                }
                .disabled(draftKey.isEmpty || testState == .running)
            }
            .buttonStyle(.plain)

            switch testState {
            case .success(let message):
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.positive)
            case .failure(let message):
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            default:
                EmptyView()
            }
        }
        .padding(.leading, 30)
    }

    // MARK: - Actions

    private func open(_ kind: AIProviderKind) {
        editingKind = kind
        draftKey = settings.apiKey(for: kind)
        draftModel = settings.model(for: kind)
        testState = .idle
    }

    private func save(_ kind: AIProviderKind) {
        settings.setAPIKey(draftKey, for: kind)
        settings.setModel(draftModel, for: kind)
        editingKind = nil
        testState = .idle
    }

    /// A real round trip: auth, model name and JSON parsing all get exercised.
    private func test(_ kind: AIProviderKind) async {
        testState = .running
        let model = draftModel.isEmpty ? kind.defaultModel : draftModel
        let provider = makeProvider(kind, model: model, key: draftKey)

        let request = OutfitRequest(
            items: [
                OutfitItemSummary(id: "a", name: "White tee", category: "tops", subcategory: "T-shirts",
                                  color: "White", colorFamily: "white", style: "casual",
                                  seasons: ["spring", "summer"], brand: nil, wearCount: 0),
                OutfitItemSummary(id: "b", name: "Blue jeans", category: "bottoms", subcategory: "Jeans",
                                  color: "Indigo", colorFamily: "blue", style: "casual",
                                  seasons: ["spring", "autumn"], brand: nil, wearCount: 0)
            ],
            occasion: .everyday,
            temperature: 18,
            weatherSummary: nil,
            preferredStyles: ["casual"],
            languageName: AnalysisContext.current.languageName,
            count: 1
        )

        do {
            let outfits = try await provider.suggestOutfits(request)
            testState = outfits.isEmpty
                ? .failure(String(localized: "Connected, but the model returned nothing."))
                : .success(String(format: String(localized: "Works — %@ replied."), model))
        } catch {
            testState = .failure(error.localizedDescription)
        }
    }

    private func makeProvider(_ kind: AIProviderKind, model: String, key: String) -> AIProvider {
        switch kind {
        case .onDevice: OnDeviceProvider()
        case .anthropic: AnthropicProvider(model: model, apiKey: key)
        case .openai: OpenAICompatibleProvider.openAI(model: model, apiKey: key)
        case .deepseek: OpenAICompatibleProvider.deepSeek(model: model, apiKey: key)
        case .gemini: GeminiProvider(model: model, apiKey: key)
        }
    }
}
