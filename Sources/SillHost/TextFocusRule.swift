import Foundation
import StreamProtocol

/// Pure classification of a Mac Accessibility element as editable text focus, plus debounced
/// transition tracking for `TextFocusWatcher`. Foundation and StreamProtocol only, so it is
/// checked standalone with swiftc (`Tests/checks/text-focus`).
enum TextFocusRule {
    /// Accessibility attributes read from the focused UI element (all optional, as AX attributes
    /// may be missing or unsupported).
    struct Element: Equatable {
        /// `kAXRoleAttribute` (e.g. `"AXTextField"`, `"AXTextArea"`, `"AXComboBox"`, `"AXSearchField"`, `"AXWebArea"`).
        var role: String?
        /// `kAXSubroleAttribute` (e.g. `"AXSecureTextField"`, `"AXSearchField"`).
        var subrole: String?
        /// `kAXEnabledAttribute`: nil when unsupported (assumed enabled unless explicitly false).
        var enabled: Bool?
        /// `"AXEditable"` (WebKit / Chromium / Electron contenteditable elements).
        var editableAttribute: Bool?
        /// Whether `kAXValueAttribute` is settable (`AXUIElementIsAttributeSettable`), read only
        /// when `editableAttribute == nil` and `needsValueSettable(role:subrole:)` is true.
        var valueSettable: Bool?

        init(role: String? = nil, subrole: String? = nil, enabled: Bool? = nil,
             editableAttribute: Bool? = nil, valueSettable: Bool? = nil) {
            self.role = role
            self.subrole = subrole
            self.enabled = enabled
            self.editableAttribute = editableAttribute
            self.valueSettable = valueSettable
        }
    }

    /// Standard macOS Accessibility roles for text inputs.
    static let textRoles: Set<String> = [
        "AXTextField",
        "AXTextArea",
        "AXComboBox",
        "AXSearchField",
    ]
    static let secureSubrole = "AXSecureTextField"
    static let searchSubrole = "AXSearchField"
    static let webAreaRole = "AXWebArea"

    /// Whether `kAXValueAttribute` settability can affect classification for this role/subrole.
    /// Avoids extra AX IPCs for non-text controls (buttons, sliders, checkboxes, windows) whose
    /// `AXValue` may be settable without accepting typed text.
    static func needsValueSettable(role: String?, subrole: String?) -> Bool {
        if let role, textRoles.contains(role) || role == webAreaRole { return true }
        return subrole == secureSubrole || subrole == searchSubrole
    }

    /// Classifies a focused Accessibility element (nil when nothing is focused) into the wire
    /// `TextFocus` state.
    static func classify(_ element: Element?) -> TextFocus {
        guard let element else { return TextFocus(editable: false) }
        if element.enabled == false { return TextFocus(editable: false) }
        if element.editableAttribute == false { return TextFocus(editable: false) }

        let secure = element.subrole == secureSubrole
        let isTextRole = element.role.map { textRoles.contains($0) } ?? false
        let isTextSubrole = secure || element.subrole == searchSubrole

        let editable: Bool
        if element.editableAttribute == true {
            editable = true
        } else if isTextRole || isTextSubrole {
            editable = element.valueSettable != false
        } else if element.role == webAreaRole && element.valueSettable == true {
            editable = true
        } else {
            editable = false
        }

        guard editable else { return TextFocus(editable: false) }
        return TextFocus(editable: true, secure: secure ? true : nil)
    }

    /// Debounced transition tracker: coalesces rapid focus flickers (e.g. moving between two fields
    /// or activating a window) and emits only when the settled state differs from `current`.
    struct Tracker: Equatable {
        /// How long a new state must hold before it is emitted (seconds).
        static let debounce: TimeInterval = 0.08

        /// The last state emitted while streaming; nil before the first emit or after `reset()`.
        private(set) var current: TextFocus?
        /// A candidate state waiting out `debounce` since `since`, if it differs from `current`.
        private(set) var pending: (focus: TextFocus, since: TimeInterval)?

        static func == (lhs: Tracker, rhs: Tracker) -> Bool {
            lhs.current == rhs.current
                && lhs.pending?.focus == rhs.pending?.focus
                && lhs.pending?.since == rhs.pending?.since
        }

        /// Records a classified focus reading at `now`. Returns the time at which `flush(at:)`
        /// should run if a timer is needed, or nil if no transition is pending (e.g. settled back
        /// to `current`). Keeping `since` when `focus` matches the already-pending state prevents
        /// repeated notifications from starving the debounce.
        mutating func observe(_ focus: TextFocus, at now: TimeInterval) -> TimeInterval? {
            if focus == current {
                pending = nil
                return nil
            }
            if let existing = pending, existing.focus == focus, now >= existing.since {
                return existing.since + Self.debounce
            }
            pending = (focus, now)
            return now + Self.debounce
        }

        /// Commits the pending state if its debounce has elapsed (or the clock stepped backwards),
        /// returning the newly emitted `TextFocus` on a transition, or nil otherwise.
        mutating func flush(at now: TimeInterval) -> TextFocus? {
            guard let pending else { return nil }
            guard now < pending.since || now - pending.since >= Self.debounce else { return nil }
            self.pending = nil
            guard pending.focus != current else { return nil }
            current = pending.focus
            return pending.focus
        }

        /// Clears emitted and pending state when streaming stops.
        mutating func reset() {
            current = nil
            pending = nil
        }
    }
}
