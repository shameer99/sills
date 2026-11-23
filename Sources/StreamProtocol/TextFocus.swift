import Foundation

// Text focus on the Mac: kind 48. The rules of HostSettings.swift apply (JSON only; every field
// optional, and fields added later too; no enums on the wire, strings instead; never rename or
// retype a field).
//
// Pure: Foundation only, so it is checked on its own with swiftc (Tests/checks/text-focus).

/// Host → device (kind 48): whether the Mac's focused UI element in the streamed source is an
/// editable text field, so an iOS device without a hardware keyboard can show or dismiss its
/// on-screen keyboard automatically. JSON; every field optional, so `{}` decodes and an older
/// peer's absence of a field reads as nil.
public struct TextFocus: Codable, Hashable, Sendable {
    /// What this host sends in kind 48 (`WindowList.textFocus`): 1 is `editable` and `secure`.
    public static let generation = 1

    /// Whether the focused UI element accepts typed text. Nil counts as false.
    public var editable: Bool?
    /// Whether the focused editable element is a secure (password) text field. Nil counts as false.
    public var secure: Bool?

    public init(editable: Bool? = nil, secure: Bool? = nil) {
        self.editable = editable
        self.secure = secure
    }

    /// Whether this payload says an editable text field has focus (`editable == true`).
    public var isEditable: Bool { editable == true }

    /// Whether this payload says a secure text field has focus (`isEditable && secure == true`).
    public var isSecure: Bool { isEditable && secure == true }
}
