import Foundation

/// Copies this app's settings to its sibling (SillS to SillE, or back) with one tap: every `Sill.` key of
/// UserDefaults, as a binary property list in a link (`sille://settings?d=…`, `sill://settings?d=…`) the
/// other app opens and takes. The device's key in the Keychain is not in it: the other app is a new device
/// to a Mac that requires pairing, and pairs once.
///
/// Pure: Foundation only, checked in Tests/checks/changelog.
enum SettingsTransfer {
    /// The keys copied: this app's own settings, never a DEBUG hook (those are `Sill` + a capital, no dot).
    static let prefix = "Sill."
    /// What the link carries at most, encoded; a larger set is not sent.
    static let maxBytes = 48_000

    /// The other app's link scheme: SillE's is `sille`, SillS's `sill`.
    static func scheme(forSiblingOf bundleID: String) -> String {
        bundleID.hasPrefix("me.saffer.sill.e") ? "sill" : "sille"
    }

    /// The settings worth copying from a defaults dictionary.
    static func pick(_ all: [String: Any]) -> [String: Any] {
        all.filter { $0.key.hasPrefix(prefix) && PropertyListSerialization.propertyList($0.value, isValidFor: .binary) }
    }

    /// The link, or nil when there is nothing to send or it is too large.
    static func link(_ settings: [String: Any], scheme: String) -> URL? {
        guard !settings.isEmpty,
              let data = try? PropertyListSerialization.data(fromPropertyList: settings, format: .binary, options: 0)
        else { return nil }
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        guard encoded.utf8.count <= maxBytes else { return nil }
        return URL(string: "\(scheme)://settings?d=\(encoded)")
    }

    /// The settings a link carries: nil for any other link (a pairing link among them) or a damaged one.
    static func settings(from url: URL) -> [String: Any]? {
        guard url.host?.lowercased() == "settings",
              let item = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "d" }),
              var text = item.value, text.utf8.count <= maxBytes
        else { return nil }
        text = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        text += String(repeating: "=", count: (4 - text.count % 4) % 4)
        guard let data = Data(base64Encoded: text),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = plist as? [String: Any]
        else { return nil }
        let kept = pick(dict)
        return kept.isEmpty ? nil : kept
    }
}
