import SwiftData
import SwiftUI

/// Progress, then a grid of everything the batch found, before it is saved.
struct BatchReviewView: View {
    @Bindable var model: BatchScanModel
    var onSaveAll: ([GarmentDraft]) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StorageLocation.createdAt) private var locations: [StorageLocation]

    @State private var editingDraft: GarmentDraft?
    @State private var sharedLocation: String?
    @State private var isAddingLocation = false
    @State private var newLocationName = ""

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            if model.isRunning {
                progressStage
            } else {
                reviewStage
            }
        }
        .sheet(item: $editingDraft) { draft in
            GarmentDraftEditor(draft: draft)
        }
        .alert(Text("New place"), isPresented: $isAddingLocation) {
            TextField(String(localized: "e.g. Bedroom wardrobe"), text: $newLocationName)
            Button("Cancel", role: .cancel) { newLocationName = "" }
            Button("Add") { addLocation() }
        }
    }

    // MARK: - While it works

    private var progressStage: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            if model.drafts.isEmpty {
                ProgressView().tint(Color.textSecondary)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(model.drafts) { draft in
                        GarmentThumbnail(filename: draft.imageFilename, fallbackSymbol: draft.category.symbol)
                            .aspectRatio(1, contentMode: .fit)
                            .cardBackground(Theme.Radius.tile)
                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, Theme.Spacing.gutter)
                .animation(.snappy, value: model.drafts.count)
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                ProgressView(value: model.progress)
                    .tint(Color.ink)
                    .padding(.horizontal, Theme.Spacing.gutter)
                Text(verbatim: "\(model.completed) / \(model.total)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                Text("Analysing your items…")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: - Review

    private var reviewStage: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(model.drafts.count) items detected")
                            .font(.system(size: 21, weight: .semibold))
                        Text("Tap an item to fix anything the analyser got wrong.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.textSecondary)
                    }

                    if model.failed > 0 {
                        Label {
                            Text("\(model.failed) photos could not be read.")
                                .font(.system(size: 12))
                        } icon: {
                            Image(systemName: "exclamationmark.triangle").font(.system(size: 12))
                        }
                        .foregroundStyle(Color.textSecondary)
                    }

                    locationPicker

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(model.drafts) { draft in
                            card(draft)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.gutter)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)

            Button {
                onSaveAll(model.drafts)
            } label: {
                Text("Save all \(model.drafts.count)")
            }
            .buttonStyle(PrimaryButtonStyle(isEnabled: !model.drafts.isEmpty))
            .disabled(model.drafts.isEmpty)
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    private func card(_ draft: GarmentDraft) -> some View {
        Button {
            editingDraft = draft
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                GarmentThumbnail(filename: draft.imageFilename, fallbackSymbol: draft.category.symbol)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .cardBackground(Theme.Radius.tile)
                    .overlay(alignment: .topTrailing) {
                        Button {
                            withAnimation(.snappy) { model.remove(draft) }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.onInk)
                                .frame(width: 26, height: 26)
                                .background(Color.ink.opacity(0.75), in: .circle)
                        }
                        .buttonStyle(.plain)
                        .padding(7)
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text(draft.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text(draft.typeLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var locationPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Where do you keep them?")
                    .font(.system(size: 15, weight: .semibold))
                Text("Optional, and applies to every item here.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textSecondary)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(locations) { location in
                        Button {
                            sharedLocation = sharedLocation == location.name ? nil : location.name
                            model.applyLocation(sharedLocation)
                        } label: {
                            ChipLabel(
                                title: location.name,
                                isSelected: sharedLocation == location.name,
                                symbol: location.symbol
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        isAddingLocation = true
                    } label: {
                        ChipLabel(title: String(localized: "New"), symbol: "plus")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addLocation() {
        let trimmed = newLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
        newLocationName = ""
        guard !trimmed.isEmpty else { return }
        modelContext.insert(StorageLocation(name: trimmed))
        try? modelContext.save()
        sharedLocation = trimmed
        model.applyLocation(trimmed)
    }
}
