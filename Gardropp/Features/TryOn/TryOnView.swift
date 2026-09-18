import AVKit
import SwiftUI

/// See an outfit on yourself: a single frame, or a short turnaround clip.
struct TryOnView: View {
    let items: [ClothingItem]
    let outfitTitle: String

    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(TryOnService.self) private var tryOn

    @State private var mode: TryOnMode = .still
    @State private var output: TryOnOutput?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if settings.personPhotoFilename == nil {
                        ModelSetupView()
                            .padding(14)
                            .cardBackground(Theme.Radius.tile)
                    } else {
                        modePicker
                        stage
                        costLine
                        actions
                    }
                }
                .padding(.horizontal, Theme.Spacing.gutter)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(Color.canvas)
            .navigationTitle(Text("Try it on"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if case .still(let filename) = output,
                   let image = ImageStore.shared.image(named: filename) {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: Image(uiImage: image), preview: SharePreview(outfitTitle, image: Image(uiImage: image)))
                    }
                }
                if case .video(let url) = output {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: url)
                    }
                }
            }
        }
        .onAppear(perform: loadCached)
        .onChange(of: mode) { _, _ in loadCached() }
    }

    // MARK: - Pieces

    private var modePicker: some View {
        Picker(selection: $mode) {
            ForEach(TryOnMode.allCases) { option in
                Text(option.title).tag(option)
            }
        } label: {
            Text("Result")
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var stage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.sheet).fill(Color.surface)

            if tryOn.isRunning {
                VStack(spacing: 12) {
                    ProgressView().tint(Color.textSecondary)
                    Text(tryOn.status ?? String(localized: "Working…"))
                        .font(.system(size: 14))
                        .foregroundStyle(Color.textSecondary)
                    Text("This can take up to a minute.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondary.opacity(0.7))
                }
            } else {
                switch output {
                case .still(let filename):
                    if let image = ImageStore.shared.image(named: filename) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(.rect(cornerRadius: Theme.Radius.sheet))
                    }
                case .video(let url):
                    VideoPlayer(player: AVPlayer(url: url))
                        .clipShape(.rect(cornerRadius: Theme.Radius.sheet))
                case nil:
                    VStack(spacing: 10) {
                        Image(systemName: mode == .video ? "video" : "person.crop.square")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(Color.textSecondary)
                        Text(outfitTitle)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.textPrimary)
                        Text(mode == .video
                             ? "A few seconds of you turning in this outfit."
                             : "One photo of you in this outfit.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 30)
                }
            }
        }
        .frame(height: 420)
    }

    private var costLine: some View {
        let engine = tryOn.settings.engine
        let model = tryOn.settings.model(for: engine)
        let calls = tryOn.callCount(items: items)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 11))
                Text(verbatim: "\(engine.displayName) · \(model)")
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.textSecondary)

            if mode == .video {
                let videoEngine = tryOn.settings.videoEngine
                HStack(spacing: 6) {
                    Image(systemName: "video").font(.system(size: 11))
                    Text(verbatim: "\(videoEngine.displayName) · \(videoEngine.approximateCost(model: tryOn.settings.model(for: videoEngine)))")
                        .font(.system(size: 12))
                }
                .foregroundStyle(Color.textSecondary)
            } else {
                Text(String(format: String(localized: "About %1$@ · %2$lld call(s)"), engine.approximateCost(model: model), calls))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textSecondary)
            }

            if let error = tryOn.errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                Task { output = await tryOn.run(items: items, person: settings.personPhotoFilename ?? "", mode: mode) }
            } label: {
                Text(output == nil ? "Try it on" : "Make another")
            }
            .buttonStyle(PrimaryButtonStyle(isEnabled: !tryOn.isRunning))
            .disabled(tryOn.isRunning)

            if !tryOn.settings.isConfigured {
                Text("Add an API key for this engine in Profile › Virtual try-on.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    private func loadCached() {
        output = tryOn.cached(items: items, person: settings.personPhotoFilename ?? "", mode: mode)
    }
}
