import CoreGraphics
import Foundation

/// The stream's input view (InputOverlayView) and a hardware keyboard on this device: whether the view
/// holds the keyboard, whose holding it is, and what to do when something changes
/// (docs/hardware-keyboard-plan.md §2). Keys and typed text reach the Mac only while the view is first
/// responder. With a hardware keyboard attached the view takes the keyboard by itself (`automatic`),
/// so typing reaches the Mac without the Keyboard button, after a rotation, a reconnect and whatever
/// took the keyboard meanwhile; the button keeps its meaning for the software keyboard (`own`, the
/// person's).
///
/// Only the person's own holding is the person's: it lights the Keyboard button, and it is what the
/// first-run tour's rule counts as the keyboard being up and its changes as something happening, so a
/// person with a keyboard attached still gets the tour (StreamScreen's `tourBusy`, `noteAction`).
///
/// The stream screen's `InputOverlayProxy` owns one (it outlives a rotation; a new session's screen
/// makes a new one), tells it what happens and does what it answers. Pure: Foundation only, checked
/// in Tests/checks/hardware-keyboard.
struct HardwareKeyboardPolicy: Equatable {
    /// What can be open over the stream that takes the keyboard for itself, or must keep keys from the
    /// Mac: the Settings panel, the pairing overlay (Pair This iPad…, an outside link), the first-run
    /// tour, the Apps drawer (its search field), the Menus pull-down. The Add a Mac card is the connect
    /// screen's, where no input view is on screen.
    enum Taker: String, CaseIterable, Hashable {
        case settings, pairing, tour, drawer, menus
    }

    /// Who holds the keyboard now: nobody, this rule for the hardware keyboard, or the person.
    enum Hold: String, Equatable {
        case none, automatic, own
    }

    /// What the input view does (the proxy does it).
    enum Action: Equatable, CustomStringConvertible {
        /// Become first responder: for the hardware keyboard (an empty input view, nothing drawn, not
        /// the person's) or as the person's own (the system keyboard).
        case take(automatic: Bool)
        /// Already first responder for the hardware keyboard, now the person's: the system keyboard's
        /// views come back, the Keyboard button lights.
        case makeOwn
        /// Already first responder as the person's, now the hardware keyboard's: the software keyboard
        /// goes, keys still reach the Mac.
        case makeAutomatic
        /// Resign first responder.
        case letGo

        var description: String {
            switch self {
            case .take(let automatic): return automatic ? "take (hardware keyboard)" : "take (the person's)"
            case .makeOwn: return "make it the person's"
            case .makeAutomatic: return "make it the hardware keyboard's"
            case .letGo: return "let go"
            }
        }
    }

    /// Who holds it now, as UIKit has confirmed (`became`, `resigned`), or as `makeOwn` and
    /// `makeAutomatic` set it.
    private(set) var hold: Hold = .none
    /// A hardware keyboard is attached (GameController's coalesced keyboard).
    private(set) var attached: Bool
    /// What is open that takes the keyboard.
    private(set) var takers: Set<Taker> = []
    /// The current input view is in a window: a session's stream screen shows.
    private(set) var onScreen = false
    /// What this view held before it last let go, for a first responder UIKit gives back by itself
    /// (after a presentation): the same again.
    private(set) var lastHeld: Hold = .none
    /// Whether the streamed Mac reports editable text focus (kind 48, `TextFocus`).
    private(set) var textFocus = false
    /// Whether the current `.own` hold was opened automatically for Mac text focus (rather than
    /// manually by the person), so it auto-dismisses when focus leaves, a taker opens, or a
    /// hardware keyboard attaches.
    private(set) var autoSoft = false
    /// Whether `lastHeld` was `.own` opened automatically for Mac text focus.
    private var lastAutoSoft = false
    /// Whether the next `became(automatic: false)` completes an automatic soft-keyboard take.
    private var pendingAutoSoft = false
    /// Whether this policy just asked UIKit to resign (`.letGo`), so `resigned()` knows not to
    /// treat our own dismissal as a manual dismissal by the person.
    private var lettingGo = false
    /// The person manually dismissed the soft keyboard during the current editable focus: do not
    /// auto-show it again until focus leaves and enters again, or the person opens it manually.
    private(set) var softDismissed = false

    init(attached: Bool = false) {
        self.attached = attached
    }

    /// The hardware keyboard's hold is wanted: a session's input view in a window, a keyboard attached,
    /// nothing open that takes the keyboard.
    var wantsAutomatic: Bool { onScreen && attached && takers.isEmpty }

    /// The software keyboard should be shown automatically for Mac text focus: a session's input view
    /// in a window, no hardware keyboard attached, no local taker open, editable focus on the Mac,
    /// and the person has not manually dismissed it during this focus.
    var wantsSoftAutomatic: Bool { onScreen && !attached && takers.isEmpty && textFocus && !softDismissed }

    /// The software keyboard is up (opened manually by the person or automatically for Mac text
    /// focus): the Keyboard button lights, the tour counts it.
    var isOwn: Bool { hold == .own }

    /// The person opened the keyboard themselves (not automatically for Mac text focus): panels that
    /// temporarily take the keyboard down restore this one when they close.
    var isManualOwn: Bool { hold == .own && !autoSoft }

    /// Take it for the hardware keyboard when wanted and nobody holds it.
    private var takeIfWanted: [Action] { hold == .none && wantsAutomatic ? [.take(automatic: true)] : [] }

    /// Take it for the software keyboard automatically when Mac text focus wants it and nobody holds it.
    private mutating func takeSoftIfWanted() -> [Action] {
        guard hold == .none && wantsSoftAutomatic else { return [] }
        pendingAutoSoft = true
        return [.take(automatic: false)]
    }

    /// Ask UIKit to resign, marking that the resignation came from this policy rather than the person.
    private mutating func releaseHold() -> [Action] {
        lettingGo = true
        return [.letGo]
    }

    // MARK: Events

    /// A new input view joined a window and is now the current one: a session's start, a rotation's
    /// other layout, a reconnect's new screen. It holds nothing yet. The old view's resignation, when it
    /// comes, is the old view's (the proxy does not pass it on).
    mutating func joined() -> [Action] {
        onScreen = true
        hold = .none
        lastHeld = .none
        autoSoft = false
        lastAutoSoft = false
        pendingAutoSoft = false
        lettingGo = false
        let actions = takeIfWanted
        return actions.isEmpty ? takeSoftIfWanted() : actions
    }

    /// The current input view left its window (UIKit takes its first responder with it).
    mutating func left() {
        onScreen = false
        hold = .none
        autoSoft = false
        pendingAutoSoft = false
        lettingGo = false
    }

    /// A hardware keyboard attached or the last one went. Only a change acts: an attach takes the
    /// keyboard if wanted (or switches an automatically shown soft keyboard to the invisible hardware
    /// hold); a detach lets the hardware keyboard's hold go, or hands it over to the automatic soft
    /// keyboard if a Mac text field has focus (the person's own stays: they asked for the keyboard).
    mutating func keyboard(attached now: Bool) -> [Action] {
        guard now != attached else { return [] }
        attached = now
        if now {
            if hold == .own && autoSoft && wantsAutomatic {
                autoSoft = false
                hold = .automatic
                return [.makeAutomatic]
            }
            return takeIfWanted
        }
        if hold == .automatic {
            if wantsSoftAutomatic {
                autoSoft = true
                hold = .own
                return [.makeOwn]
            }
            return releaseHold()
        }
        return []
    }

    /// What is open changed. Something open: the hardware keyboard's hold and any automatically shown
    /// soft keyboard let go (the person's manually opened keyboard stays, as before: the Settings
    /// panel, the tour and the pairing overlay take it down themselves, the drawer and the Menus
    /// pull-down never did). The last one closed: taken for the hardware keyboard or automatic Mac
    /// text focus if wanted, unless the person's own came back first.
    mutating func takers(_ now: Set<Taker>) -> [Action] {
        let was = takers
        takers = now
        if !now.isEmpty {
            if hold == .automatic { return releaseHold() }
            if hold == .own && autoSoft {
                autoSoft = false
                return releaseHold()
            }
            return []
        }
        guard !was.isEmpty else { return [] }
        let actions = takeIfWanted
        return actions.isEmpty ? takeSoftIfWanted() : actions
    }

    /// The streamed Mac's focused UI element became editable or stopped being editable (kind 48).
    /// Only a transition acts: entering editable focus clears any prior dismiss override and opens
    /// the soft keyboard when no hardware keyboard is attached and no local taker is open; leaving
    /// editable focus clears any dismiss override and dismisses an automatically opened soft keyboard
    /// while leaving a manually opened one alone.
    mutating func textFocus(editable now: Bool) -> [Action] {
        guard now != textFocus else { return [] }
        textFocus = now
        softDismissed = false
        if now { return takeSoftIfWanted() }
        if hold == .own && autoSoft {
            autoSoft = false
            return releaseHold()
        }
        return []
    }

    /// The Keyboard button (and the portrait key row's keyboard cap). Nobody holds it: the person's
    /// own (the software keyboard; with a hardware keyboard attached, iPadOS's own small bar), while a
    /// view is in a window (between a rotation's two views, nothing). The hardware keyboard holds it:
    /// now the person's. The person holds it: down (remembered as a manual dismiss while the current
    /// Mac text focus lasts), and back to the hardware keyboard at once when it is wanted, so the
    /// software keyboard goes and keys still reach the Mac.
    mutating func toggled() -> [Action] {
        switch hold {
        case .none:
            guard onScreen else { return [] }
            softDismissed = false
            pendingAutoSoft = false
            return [.take(automatic: false)]
        case .automatic:
            softDismissed = false
            autoSoft = false
            hold = .own
            return [.makeOwn]
        case .own:
            autoSoft = false
            if textFocus { softDismissed = true }
            guard wantsAutomatic else { return releaseHold() }
            hold = .automatic
            return [.makeAutomatic]
        }
    }

    /// `setKeyboard(shown:)`. True: the person's keyboard put back (the Settings panel or the tour
    /// closing over the keyboard they had up, the Menus pull-down after Settings; DEBUG
    /// `-SillKeyboard 1`), while a view is in a window. False: whoever holds it lets go (the Settings
    /// panel, the tour and the pairing overlay opening).
    mutating func shown(_ show: Bool) -> [Action] {
        guard show else {
            autoSoft = false
            pendingAutoSoft = false
            return hold == .none ? [] : releaseHold()
        }
        switch hold {
        case .none:
            guard onScreen else { return [] }
            softDismissed = false
            pendingAutoSoft = false
            return [.take(automatic: false)]
        case .automatic:
            softDismissed = false
            autoSoft = false
            hold = .own
            return [.makeOwn]
        case .own:
            autoSoft = false
            return []
        }
    }

    /// The kind a first responder UIKit gives back by itself would be (the view needs it before it
    /// becomes first responder, for its input view): what this view last held, else the hardware
    /// keyboard's when that is wanted, else the person's.
    var unpromptedKind: Hold {
        if lastHeld != .none { return lastHeld }
        return wantsAutomatic ? .automatic : .own
    }

    /// The current view became first responder. `automatic`: what was asked (`take`); nil when UIKit
    /// did it by itself, which counts as `unpromptedKind`. A hardware keyboard's hold or automatic
    /// soft hold that is not wanted any more lets go at once.
    mutating func became(automatic: Bool?) -> [Action] {
        let wasPendingAutoSoft = pendingAutoSoft
        pendingAutoSoft = false
        lettingGo = false
        if let automatic {
            hold = automatic ? .automatic : .own
            autoSoft = !automatic && wasPendingAutoSoft
        } else {
            hold = unpromptedKind
            autoSoft = hold == .own && lastAutoSoft
        }
        if hold == .automatic && !wantsAutomatic { return releaseHold() }
        if hold == .own && autoSoft && !wantsSoftAutomatic {
            autoSoft = false
            return releaseHold()
        }
        return []
    }

    /// The current view resigned: let go of here, or another responder (or the iPadOS keyboard's own
    /// dismiss key) took the keyboard. Not fought: the next moment above takes it back. An external
    /// dismissal while editable Mac text focus is active and no local taker is open counts as a manual
    /// dismiss override for this focus.
    mutating func resigned() {
        let external = !lettingGo
        lettingGo = false
        if external && hold == .own && textFocus && takers.isEmpty && !attached {
            softDismissed = true
        }
        if hold != .none {
            lastHeld = hold
            lastAutoSoft = autoSoft
        }
        hold = .none
        autoSoft = false
        pendingAutoSoft = false
    }
}

/// A scroll from the iPad's own trackpad (two fingers), a Magic Mouse or a mouse's wheel over the picture
/// (docs/hardware-keyboard-plan.md §3, issue #130, PR #217): how far it has gone, and where on the picture
/// all of it goes. Its pan (InputOverlayView's `trackpadScroll` and `wheelScroll`) has no touch and the
/// pointer stays where it is, but UIKit moves the pan's location on by its translation, as if a finger had
/// been dragged from the pointer (measured in the iOS 27 simulator, three notches of a wheel over a pointer
/// at y 308.8: the pan's translation 3, 6 and 9 pt, its location at y 311.8, 314.8 and 317.8). Posted at
/// the pan's location, a scroll's events walked off the pointer by as much as it scrolled (a synthetic
/// host's log: ten notches from y 447 to 497 of the picture's 949, phased events of 194 points from 459 to 636),
/// and the Mac takes each to what is under it (InputInjector's `postScroll`): at first the window under the
/// pointer, then whatever the point had reached, or the picture's edge it is held to.
/// Every event of the scroll, its end and its coast now go where the pointer was as it began: the pan's
/// first location less its first reading.
///
/// Each reading is taken and the pan's translation zeroed (InputOverlayView), so a reading is what moved
/// since the last one whether UIKit adds a scroll's events up, as it does in the simulator (and as it does
/// a finger's), or hands each event only its own movement, as PR #217 reasoned a Magic Keyboard does: `total`
/// adds the readings up into the translation a finger's pan would have, which the scroll path diffs as it
/// does a finger's.
///
/// Pure: Foundation and CoreGraphics, checked in Tests/checks/hardware-keyboard.
struct PointerScroll {
    /// Where the pointer was as the scroll began, in the view's points: where every event of it goes.
    private(set) var at: CGPoint = .zero
    /// The scroll so far: every reading since it began added up.
    private(set) var total: CGPoint = .zero

    /// The pan began: its location, and its first reading (what moved before it began, which that
    /// location already has in it).
    mutating func began(at location: CGPoint, reading: CGPoint) {
        at = CGPoint(x: location.x - reading.x, y: location.y - reading.y)
        total = reading
    }

    /// A later event (a change, the end, a cancel): what moved since the last reading.
    mutating func moved(_ reading: CGPoint) {
        total = CGPoint(x: total.x + reading.x, y: total.y + reading.y)
    }
}
