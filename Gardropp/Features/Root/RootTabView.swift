import SwiftData
import SwiftUI

struct RootTabView: View {
    enum Tab: Hashable {
        case home, outfits, clothes, profile
    }

    @State private var selection: Tab = .home
    @State private var isScanning = false
    @State private var toast: ToastMessage?

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.canvas.ignoresSafeArea()

            Group {
                switch selection {
                case .home: HomeView()
                case .outfits: OutfitsView()
                case .clothes: WardrobeView()
                case .profile: ProfileView()
                }
            }
            .transition(.opacity)

            FloatingTabBar(selection: $selection) { isScanning = true }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
        }
        .overlay(alignment: .bottom) {
            if let toast {
                ToastView(message: toast)
                    .padding(.bottom, 96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .fullScreenCover(isPresented: $isScanning) {
            ScanFlowView { count in
                selection = .clothes
                show(ToastMessage(text: String(localized: "\(count) items added")))
            }
        }
        .animation(.snappy(duration: 0.25), value: selection)
        .animation(.snappy(duration: 0.3), value: toast?.id)
        .environment(\.showToast, ShowToastAction(handler: show))
    }

    private func show(_ message: ToastMessage) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            if toast?.id == message.id { toast = nil }
        }
    }
}

// MARK: - Tab bar

struct FloatingTabBar: View {
    @Binding var selection: RootTabView.Tab
    var onAdd: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            item(.home, symbol: "house", selected: "house.fill", title: "Home")
            item(.outfits, symbol: "hanger", selected: "hanger", title: "Outfits")

            Button(action: onAdd) {
                VStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.onInk)
                        .frame(width: 46, height: 46)
                        .background(Color.ink, in: .circle)
                    Text("Add")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                }
                .offset(y: -8)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            item(.clothes, symbol: "tshirt", selected: "tshirt.fill", title: "Clothes")
            item(.profile, symbol: "person", selected: "person.fill", title: "Profile")
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background {
            RoundedRectangle(cornerRadius: 26)
                .fill(.regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.hairline, lineWidth: 0.5))
        }
        .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
    }

    private func item(_ tab: RootTabView.Tab, symbol: String, selected: String, title: LocalizedStringKey) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: 5) {
                Image(systemName: selection == tab ? selected : symbol)
                    .font(.system(size: 19, weight: selection == tab ? .semibold : .regular))
                Text(title).font(.system(size: 10, weight: selection == tab ? .semibold : .medium))
            }
            .foregroundStyle(selection == tab ? Color.textPrimary : Color.textSecondary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Toast

struct ToastMessage: Equatable, Identifiable {
    let id = UUID()
    var text: String
    var symbol: String = "checkmark.circle.fill"
}

struct ToastView: View {
    let message: ToastMessage

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: message.symbol).font(.system(size: 15, weight: .semibold))
            Text(message.text).font(.system(size: 15, weight: .medium))
        }
        .foregroundStyle(Color.onInk)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.ink, in: .capsule)
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }
}

struct ShowToastAction {
    var handler: (ToastMessage) -> Void
    func callAsFunction(_ text: String, symbol: String = "checkmark.circle.fill") {
        handler(ToastMessage(text: text, symbol: symbol))
    }
}

private struct ShowToastKey: EnvironmentKey {
    static let defaultValue = ShowToastAction { _ in }
}

extension EnvironmentValues {
    var showToast: ShowToastAction {
        get { self[ShowToastKey.self] }
        set { self[ShowToastKey.self] = newValue }
    }
}
