import Foundation

/// Links handed over by the share extension. The extension only writes; the
/// app drains the queue the next time it comes to the front.
enum SharedInbox {
    static let appGroup = "group.adilemre.Gardropp"
    private static let key = "pendingLinks"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    /// Removes and returns the oldest waiting link.
    static func takeNext() -> URL? {
        guard let defaults else { return nil }
        var pending = defaults.stringArray(forKey: key) ?? []
        guard !pending.isEmpty else { return nil }

        let first = pending.removeFirst()
        defaults.set(pending, forKey: key)
        return URL(string: first)
    }

    static var hasPending: Bool {
        !(defaults?.stringArray(forKey: key) ?? []).isEmpty
    }
}
