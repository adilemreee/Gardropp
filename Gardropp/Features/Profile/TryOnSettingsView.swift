import SwiftUI

/// Your photo, the engine that dresses it, and the keys they need.
struct TryOnSettingsView: View {
    @Environment(TryOnService.self) private var tryOn

    @State private var stillKey = ""
    @State private var stillModel = ""
    @State private var videoKey = ""
    @State private var videoModel = ""

    var body: some View {
        @Bindable var settings = tryOn.settings

        return Form {
            Section {
                ModelSetupView()
                    .padding(.vertical, 4)
            } footer: {
                Text("Outfits are fitted onto this stand-in, so you are the same person in every look.")
            }

            Section {
                Picker(selection: $settings.engine) {
                    ForEach(TryOnEngine.allCases) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                } label: {
                    Text("Engine")
                }
                .onChange(of: settings.engine) { _, _ in loadStill() }

                Text(settings.engine.blurb)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textSecondary)

                SecureField(String(localized: "API key"), text: $stillKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(size: 14, design: .monospaced))

                HStack {
                    TextField(settings.engine.defaultModel, text: $stillModel)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(size: 14, design: .monospaced))
                    Menu {
                        ForEach(settings.engine.suggestedModels, id: \.self) { model in
                            Button(model) { stillModel = model }
                        }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                if let url = settings.engine.consoleURL {
                    Link(destination: url) {
                        Text("Get a key ↗").font(.system(size: 13))
                    }
                }

                Button("Save") { save() }
            } header: {
                Text("Single frame")
            } footer: {
                Text(String(format: String(localized: "About %@ per fitted garment."),
                            settings.engine.approximateCost(model: stillModel.isEmpty ? settings.engine.defaultModel : stillModel)))
            }

            Section {
                Picker(selection: $settings.videoEngine) {
                    ForEach(TryOnVideoEngine.allCases) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                } label: {
                    Text("Engine")
                }
                .onChange(of: settings.videoEngine) { _, _ in loadVideo() }

                Text(settings.videoEngine.blurb)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textSecondary)

                SecureField(String(localized: "API key"), text: $videoKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(size: 14, design: .monospaced))

                HStack {
                    TextField(settings.videoEngine.defaultModel, text: $videoModel)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(size: 14, design: .monospaced))
                    Menu {
                        ForEach(settings.videoEngine.suggestedModels, id: \.self) { model in
                            Button(model) { videoModel = model }
                        }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                if let url = settings.videoEngine.consoleURL {
                    Link(destination: url) {
                        Text("Get a key ↗").font(.system(size: 13))
                    }
                }

                Button("Save") { save() }
            } header: {
                Text("Video")
            } footer: {
                Text(String(format: String(localized: "About %@ for a four second clip. The frame is made first, so a clip costs both."),
                            settings.videoEngine.approximateCost(model: videoModel.isEmpty ? settings.videoEngine.defaultModel : videoModel)))
            }
        }
        .navigationTitle(Text("Virtual try-on"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadStill()
            loadVideo()
        }
    }

    private func loadStill() {
        stillKey = tryOn.settings.apiKey(for: tryOn.settings.engine.keychainAccount)
        stillModel = tryOn.settings.model(for: tryOn.settings.engine)
    }

    private func loadVideo() {
        videoKey = tryOn.settings.apiKey(for: tryOn.settings.videoEngine.keychainAccount)
        videoModel = tryOn.settings.model(for: tryOn.settings.videoEngine)
    }

    private func save() {
        let settings = tryOn.settings
        settings.setAPIKey(stillKey, for: settings.engine.keychainAccount)
        settings.setModel(stillModel, for: settings.engine)
        settings.setAPIKey(videoKey, for: settings.videoEngine.keychainAccount)
        settings.setModel(videoModel, for: settings.videoEngine)
    }
}
