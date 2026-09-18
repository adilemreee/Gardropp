import PhotosUI
import SwiftUI

/// Sets up the stand-in: you provide a face, the app builds a body for it once
/// and every try-on afterwards dresses that same figure.
struct ModelSetupView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(TryOnService.self) private var tryOn
    @State private var builder = ModelBuilder()
    @State private var facePicker: PhotosPickerItem?
    @State private var bodyPicker: PhotosPickerItem?

    var body: some View {
        @Bindable var settings = settings

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                preview

                VStack(alignment: .leading, spacing: 4) {
                    Text("Your stand-in")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Add your face once. The body stays the same in every outfit.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    PhotosPicker(selection: $facePicker, matching: .images, photoLibrary: .shared()) {
                        Text(settings.facePhotoFilename == nil ? "Choose a face photo" : "Change face photo")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.textPrimary)
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }

            Stepper(value: $settings.bodyHeightCM, in: 140...200) {
                HStack {
                    Text("Height")
                    Spacer()
                    Text(verbatim: "\(settings.bodyHeightCM) cm")
                        .foregroundStyle(Color.textSecondary)
                }
                .font(.system(size: 15))
            }

            Picker(selection: $settings.bodyBuild) {
                ForEach(BodyBuild.allCases) { build in
                    Text(build.title).tag(build)
                }
            } label: {
                Text("Build")
            }
            .pickerStyle(.segmented)

            Button {
                Task { await buildStandIn() }
            } label: {
                HStack(spacing: 8) {
                    if builder.isBuilding { ProgressView().controlSize(.small) }
                    Text(settings.personPhotoFilename == nil ? "Build my stand-in" : "Build it again")
                }
            }
            .buttonStyle(PrimaryButtonStyle(isEnabled: settings.facePhotoFilename != nil && !builder.isBuilding))
            .disabled(settings.facePhotoFilename == nil || builder.isBuilding)

            Text("Built once with Gemini, about $0.03. Change the height or build and make it again whenever you like.")
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondary)

            if let error = builder.errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PhotosPicker(selection: $bodyPicker, matching: .images, photoLibrary: .shared()) {
                Text("Or use my own full-length photo")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .onChange(of: facePicker) { _, item in
            guard let item else { return }
            Task { await loadFace(item) }
        }
        .onChange(of: bodyPicker) { _, item in
            guard let item else { return }
            Task { await loadOwnBody(item) }
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var preview: some View {
        let filename = settings.personPhotoFilename ?? settings.facePhotoFilename
        if let filename, let image = ImageStore.shared.image(named: filename) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 84, height: 112)
                .clipShape(.rect(cornerRadius: 12))
                .overlay(alignment: .bottom) {
                    if settings.personPhotoFilename == nil {
                        Text("Face only")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.onInk)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.ink.opacity(0.75), in: .capsule)
                            .padding(5)
                    }
                }
        } else {
            Image(systemName: "person.crop.rectangle")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 84, height: 112)
                .background(Color.surfaceElevated.opacity(0.6), in: .rect(cornerRadius: 12))
        }
    }

    // MARK: - Actions

    private func buildStandIn() async {
        guard let faceName = settings.facePhotoFilename,
              let face = ImageStore.shared.image(named: faceName) else { return }
        guard let model = await builder.build(face: face, spec: settings.bodySpec, settings: tryOn.settings) else { return }
        guard let filename = try? ImageStore.shared.save(model, format: .jpeg(quality: 0.92)) else { return }

        ImageStore.shared.delete(settings.personPhotoFilename)
        settings.personPhotoFilename = filename
    }

    private func loadFace(_ item: PhotosPickerItem) async {
        defer { facePicker = nil }
        guard let image = await image(from: item, maxEdge: 1024) else { return }
        guard let filename = try? ImageStore.shared.save(image, format: .jpeg(quality: 0.92)) else { return }
        ImageStore.shared.delete(settings.facePhotoFilename)
        settings.facePhotoFilename = filename
    }

    private func loadOwnBody(_ item: PhotosPickerItem) async {
        defer { bodyPicker = nil }
        guard let image = await image(from: item, maxEdge: 1600) else { return }
        guard let filename = try? ImageStore.shared.save(image, format: .jpeg(quality: 0.92)) else { return }
        ImageStore.shared.delete(settings.personPhotoFilename)
        settings.personPhotoFilename = filename
    }

    private func image(from item: PhotosPickerItem, maxEdge: CGFloat) async -> UIImage? {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return nil }
        return image.normalizedOrientation().resized(maxEdge: maxEdge)
    }
}
