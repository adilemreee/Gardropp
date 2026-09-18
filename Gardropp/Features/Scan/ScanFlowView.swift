import Combine
import PhotosUI
import SwiftData
import SwiftUI

/// Camera or gallery → background removal → AI attributes → review → save.
/// Picking several photos at once switches to the batch path, which analyses
/// them a few at a time and reviews them together.
struct ScanFlowView: View {
    /// Called with how many items were added.
    var onSaved: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AIService.self) private var ai

    @State private var camera = CameraController()
    @State private var batch = BatchScanModel()
    @State private var phase: Phase = .capture
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var didSave = false
    @State private var isAskingForLink = false
    @State private var linkError: String?

    private static let maxSelection = 24

    private enum Phase {
        case capture
        case readingLink(String)
        case processing(UIImage)
        case review(GarmentDraft)
        case batch
    }

    var body: some View {
        ZStack {
            Color.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                switch phase {
                case .capture:
                    captureStage
                case .readingLink(let host):
                    ReadingLinkStage(host: host)
                case .processing(let image):
                    ProcessingStage(image: image)
                case .review(let draft):
                    DetectedItemView(draft: draft, onSave: save, onRetake: retake)
                case .batch:
                    BatchReviewView(model: batch, onSaveAll: saveAll)
                }
            }
        }
        .task { await camera.start() }
        .onDisappear {
            camera.stop()
            if !didSave { discardPending() }
        }
        .onChange(of: pickerItems) { _, newValue in
            Task { await handlePicked(newValue) }
        }
        .sheet(isPresented: $isAskingForLink) {
            LinkImportSheet { url in
                Task { await importLink(url) }
            }
        }
        .alert(
            Text("Couldn't read that link"),
            isPresented: Binding(get: { linkError != nil }, set: { if !$0 { linkError = nil } })
        ) {
            Button("OK", role: .cancel) { linkError = nil }
        } message: {
            Text(linkError ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.textPrimary)
            HStack {
                CircularIconButton(symbol: "xmark") { close() }
                Spacer()
                if case .capture = phase {
                    photoPicker {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.textPrimary)
                            .frame(width: 38, height: 38)
                            .background(Color.surface, in: .circle)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.vertical, 12)
    }

    private var title: String {
        switch phase {
        case .capture: String(localized: "Scan garment")
        case .readingLink: String(localized: "Adding from a link")
        case .processing: String(localized: "Processing")
        case .review: String(localized: "Item detected")
        case .batch: batch.isRunning ? String(localized: "Processing") : String(localized: "Items detected")
        }
    }

    /// One picker definition for both entry points — several photos at a time.
    private func photoPicker(@ViewBuilder label: () -> some View) -> some View {
        PhotosPicker(
            selection: $pickerItems,
            maxSelectionCount: Self.maxSelection,
            selectionBehavior: .ordered,
            matching: .images,
            photoLibrary: .shared(),
            label: label
        )
    }

    // MARK: - Capture stage

    private var captureStage: some View {
        VStack(spacing: 22) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.sheet)
                    .fill(Color.surface)

                switch camera.availability {
                case .ready:
                    CameraPreview(session: camera.session)
                        .clipShape(.rect(cornerRadius: Theme.Radius.sheet))
                case .denied:
                    permissionNotice(
                        symbol: "camera.fill",
                        title: "Camera access is off",
                        message: "Turn it on in Settings, or pick photos from your library."
                    )
                case .unavailable:
                    permissionNotice(
                        symbol: "photo.on.rectangle.angled",
                        title: "No camera here",
                        message: "Pick photos of your garments from your library instead."
                    )
                case .unknown:
                    ProgressView().tint(Color.textSecondary)
                }

                if camera.availability == .ready {
                    ViewfinderFrame(isActive: camera.hasSubjectInFrame)
                }
            }
            .padding(.horizontal, Theme.Spacing.gutter)

            VStack(spacing: 14) {
                if camera.availability == .ready {
                    Button {
                        Task { await capture() }
                    } label: {
                        ZStack {
                            Circle().stroke(Color.textSecondary.opacity(0.4), lineWidth: 2).frame(width: 74, height: 74)
                            Circle().fill(Color.ink).frame(width: 62, height: 62)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(camera.isCapturing)

                    Text(camera.hasSubjectInFrame ? "Item detected" : "Hold the garment in frame")
                        .font(.system(size: 13))
                        .foregroundStyle(camera.hasSubjectInFrame ? Color.positive : Color.textSecondary)
                        .animation(.easeInOut, value: camera.hasSubjectInFrame)

                    HStack(spacing: 18) {
                        photoPicker {
                            Label("Library", systemImage: "square.stack")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.textPrimary)
                        }
                        Button {
                            isAskingForLink = true
                        } label: {
                            Label("Link", systemImage: "link")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.textPrimary)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    photoPicker {
                        Text("Choose photos")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.onInk)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.ink, in: .rect(cornerRadius: Theme.Radius.tile))
                    }
                    .padding(.horizontal, Theme.Spacing.gutter)

                    Button {
                        isAskingForLink = true
                    } label: {
                        Label("Add from a link", systemImage: "link")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func permissionNotice(symbol: String, title: LocalizedStringKey, message: LocalizedStringKey) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Color.textSecondary)
            Text(title).font(.system(size: 17, weight: .semibold))
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
    }

    // MARK: - Actions

    private func capture() async {
        guard let photo = await camera.capturePhoto() else { return }
        await run(on: photo)
    }

    private func handlePicked(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        pickerItems = []
        camera.stop()

        if items.count == 1 {
            guard let data = try? await items[0].loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            await run(on: image)
        } else {
            withAnimation(.snappy) { phase = .batch }
            batch.start(items: items, ai: ai)
        }
    }

    private func importLink(_ url: URL) async {
        camera.stop()
        withAnimation(.snappy) { phase = .readingLink(url.host() ?? url.absoluteString) }

        do {
            let (product, image) = try await ProductLinkImporter.load(url)
            withAnimation(.snappy) { phase = .processing(image) }
            guard let draft = await GarmentScanner.makeDraft(
                from: product, image: image, sourceURL: url, ai: ai
            ) else {
                throw ProductLinkImporter.ImportError.noGarmentFound
            }
            withAnimation(.snappy) { phase = .review(draft) }
        } catch {
            linkError = error.localizedDescription
            retake()
        }
    }

    private func run(on photo: UIImage) async {
        withAnimation(.snappy) { phase = .processing(photo) }
        camera.stop()

        guard let draft = await GarmentScanner.makeDraft(from: photo, ai: ai) else {
            retake()
            return
        }
        withAnimation(.snappy) { phase = .review(draft) }
    }

    private func retake() {
        if case .review(let draft) = phase { draft.discard() }
        withAnimation(.snappy) { phase = .capture }
        Task { await camera.start() }
    }

    private func save(_ draft: GarmentDraft) {
        modelContext.insert(draft.makeItem())
        try? modelContext.save()
        didSave = true
        onSaved(1)
        dismiss()
    }

    private func saveAll(_ drafts: [GarmentDraft]) {
        for draft in drafts {
            modelContext.insert(draft.makeItem())
        }
        try? modelContext.save()
        didSave = true
        onSaved(drafts.count)
        dismiss()
    }

    private func close() {
        discardPending()
        dismiss()
    }

    /// Anything analysed but not saved leaves its photos behind otherwise.
    private func discardPending() {
        if case .review(let draft) = phase { draft.discard() }
        batch.discardAll()
    }
}

// MARK: - Processing stage

private struct ProcessingStage: View {
    let image: UIImage
    @State private var activeDot = 0

    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 20) {
            Color.surface
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
                .clipShape(.rect(cornerRadius: Theme.Radius.sheet))
                .padding(.horizontal, Theme.Spacing.gutter)

            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(index == activeDot ? Color.textPrimary : Color.textSecondary.opacity(0.35))
                        .frame(width: 6, height: 6)
                }
            }

            Text("Analysing your item…")
                .font(.system(size: 15))
                .foregroundStyle(Color.textSecondary)
                .padding(.bottom, 40)
        }
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.25)) { activeDot = (activeDot + 1) % 3 }
        }
    }
}

// MARK: - Link stage

private struct ReadingLinkStage: View {
    let host: String

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "link")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Color.textSecondary)
            ProgressView().tint(Color.textSecondary)
            Text("Reading the link…")
                .font(.system(size: 15))
                .foregroundStyle(Color.textSecondary)
            Text(host)
                .font(.system(size: 13))
                .foregroundStyle(Color.textSecondary.opacity(0.7))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
