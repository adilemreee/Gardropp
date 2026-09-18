import UIKit

/// The "Gardropp'a ekle" entry in the iOS share sheet. It only has one job:
/// hand the shared address to the app. The app does the fetching and the
/// analysis when it opens, where it already has the wardrobe and the settings.
final class ShareViewController: UIViewController {

    /// Shared with the app through the app group.
    private static let suite = "group.adilemre.Gardropp"
    private static let key = "pendingLinks"

    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpConfirmation()

        Task {
            if let url = await sharedURL() {
                store(url)
            } else {
                label.text = NSLocalizedString("No link found", comment: "")
            }
            try? await Task.sleep(for: .seconds(0.9))
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    // MARK: - Reading what was shared

    private func sharedURL() async -> URL? {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        for item in items {
            for provider in item.attachments ?? [] {
                // NSURL is what the provider actually vends; URL is not loadable directly.
                if let url = await loadObject(NSURL.self, from: provider) as URL? {
                    return url
                }
                // Some apps share the address as plain text instead.
                if let text = await loadObject(NSString.self, from: provider) as String?,
                   let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                   url.scheme?.hasPrefix("http") == true {
                    return url
                }
            }
        }
        return nil
    }

    private func loadObject<T: NSItemProviderReading>(_ type: T.Type, from provider: NSItemProvider) async -> T? {
        guard provider.canLoadObject(ofClass: type) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: type) { object, _ in
                continuation.resume(returning: object as? T)
            }
        }
    }

    private func store(_ url: URL) {
        guard let defaults = UserDefaults(suiteName: Self.suite) else { return }
        var pending = defaults.stringArray(forKey: Self.key) ?? []
        pending.append(url.absoluteString)
        defaults.set(Array(pending.suffix(20)), forKey: Self.key)
    }

    // MARK: - The little confirmation card

    private func setUpConfirmation() {
        view.backgroundColor = .clear

        let card = UIView()
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 22
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        let icon = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        icon.tintColor = .label
        icon.translatesAutoresizingMaskIntoConstraints = false

        label.text = NSLocalizedString("Added to Gardropp", comment: "")
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .label
        label.numberOfLines = 2
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let caption = UILabel()
        caption.text = NSLocalizedString("Open the app to finish adding it.", comment: "")
        caption.font = .systemFont(ofSize: 13)
        caption.textColor = .secondaryLabel
        caption.numberOfLines = 2
        caption.textAlignment = .center
        caption.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(icon)
        card.addSubview(label)
        card.addSubview(caption)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 260),

            icon.topAnchor.constraint(equalTo: card.topAnchor, constant: 26),
            icon.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            icon.widthAnchor.constraint(equalToConstant: 34),
            icon.heightAnchor.constraint(equalToConstant: 34),

            label.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 12),
            label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),

            caption.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 4),
            caption.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            caption.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            caption.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24)
        ])
    }
}
