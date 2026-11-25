import Foundation
import CoreGraphics

// The first-run tour of the stream screen (docs/first-run-walkthrough-plan.md): the rules, pure.
// What each layout's tour teaches and where it points, when it shows by itself, what it remembers,
// where it goes after a rotation, where its card sits, and every word it says. Foundation and
// CoreGraphics only, so it compiles on its own with swiftc (Tests/checks/tour). TourOverlay.swift
// draws it, StreamScreen feeds it.

// MARK: - Steps, layouts and targets

/// One card of the tour: what it teaches. `allCases` is the tour's order, where things are: the
/// picture first, then the bar from left to right, then what is behind its last button (the
/// clipboard and the Mac's sound, `sharing`, then Settings itself), then down the laptop half.
/// `sharing` came with tour version 2 (0.6: `TourPolicy.version`), saved as "sharing" in
/// `Sill.tourSeen`; a build from before it ignores the name.
enum TourTopic: String, CaseIterable, Comparable {
    case touch, bar, sharing, settings, laptop

    static func < (a: TourTopic, b: TourTopic) -> Bool { a.rank < b.rank }
    private var rank: Int { TourTopic.allCases.firstIndex(of: self) ?? 0 }
}

/// The layouts the tour knows: sideways (the slim leading rail beside the picture, and the trackpad
/// and keys when the software keyboard is up), and upright (the picture at the top, one bar below it,
/// the trackpad and the modifier row; `.portrait` for wide screens like the Duo's inner display and
/// iPad, `.phone` for phones and the Duo's cover display).
enum TourLayout: String, Hashable {
    case landscape, portrait, phone

    /// Held upright: picture, one bar, trackpad and key row.
    var upright: Bool { self != .landscape }
}

/// What a step lights: each reported by its view as a frame in the stream screen's space. `apps` is
/// the Apps button (lit sideways, where there is no thumbnail strip); `menus` the Menus button,
/// reported wherever it is drawn (`MacMenuButton`), so only while the Mac sent menus and there is
/// room for it.
enum TourTarget: String, CaseIterable, Hashable {
    case stream, apps, strip, menus, keyboard, settings, keys, trackpad
}

/// What this device remembers (UserDefaults `Sill.tourSeen`, `Sill.tourSkipped`): the steps passed
/// with Next or Done, and whether Skip was ever tapped. Beside them `Sill.tourVersion`, the tour's
/// version they are of: a memory of an older one is cleared once (`TourPolicy.upgraded`).
struct TourMemory: Equatable {
    var seen: Set<TourTopic> = []
    var skipped = false

    init(seen: Set<TourTopic> = [], skipped: Bool = false) {
        self.seen = seen
        self.skipped = skipped
    }

    /// From the saved topic names: a name this build does not know is ignored.
    init(names: [String], skipped: Bool) {
        self.init(seen: Set(names.compactMap(TourTopic.init(rawValue:))), skipped: skipped)
    }

    /// What is saved: the topics seen, in the tour's order.
    var names: [String] { TourTopic.allCases.filter { seen.contains($0) }.map(\.rawValue) }
}

// MARK: - When it shows by itself

/// What the rule looks at, at one moment of a session. Times are `ProcessInfo.systemUptime`.
struct TourMoment: Equatable {
    var now: Double
    /// This session's first picture: the Mac's first window list, a frame size and a source.
    var pictureAt: Double?
    /// When the layout on screen (portrait or landscape) began.
    var layoutAt: Double
    /// This session's picture has had its decision.
    var decided: Bool
    /// The last touch anywhere on the screen, or input sent to the Mac.
    var lastActivityAt: Double?
    /// Touches on the screen now.
    var touchesDown: Int
    /// Something open (the Apps list, the Settings panel, a thumbnail's lights, the Aa ruler, the
    /// software keyboard, the pairing overlay or a link's confirmation), or the app not active.
    var busy: Bool
    /// This session has had its decision in this layout.
    var offered: Bool
    var voiceOver: Bool
    /// Release: always; Debug: only with `-SillTourState`.
    var enabled: Bool
}

enum TourReason: String, Equatable {
    /// Nothing to show here: all of it seen, skipped, already decided, or the tour off.
    case nothingOwed
    /// Something was touched or sent since the picture, or since the turn.
    case used
    /// A touch still down, or something open, at the decision.
    case busy
}

enum TourDecision: Equatable {
    /// Show these steps now.
    case show([TourTopic])
    /// Ask again at this time (nil: at the next change).
    case wait(until: Double?)
    /// Not in this session and layout. The caller marks the layout offered and the picture decided
    /// on any pass or show that comes once there is a picture.
    case pass(TourReason)
}

/// What the automatic tour decided in a session. It outlives the session's stream screen
/// (StreamClient keeps it), so the automatic reconnect's session can go on with it
/// (`TourPolicy.nextSession`).
struct TourSession: Equatable {
    /// The picture's decision was made.
    var decided = false
    /// The layouts that had their decision.
    var offered: Set<TourLayout> = []
    /// A run is on screen, or put aside under the pairing overlay.
    var running = false
}

// MARK: - A run of the tour

/// The tour on screen: its steps, the one showing, and those this run has passed.
struct TourRun: Equatable {
    var steps: [TourTopic]
    var at: TourTopic
    var passed: Set<TourTopic> = []
    /// Take the Tour (every step of the layout), not the automatic tour (the steps owed).
    var replay: Bool

    var index: Int { steps.firstIndex(of: at) ?? 0 }
    var count: Int { steps.count }
    var isLast: Bool { at == steps.last }
    /// The laptop card's subtitle is its own only when it starts a run.
    var firstOfRun: Bool { at == steps.first }
}

// MARK: - Where the card goes

struct TourTail: Equatable {
    enum Edge: String, Equatable { case up, down }
    var edge: Edge
    /// The tip's x, in the screen's space.
    var x: CGFloat
}

struct TourPlacement: Equatable {
    var card: CGRect
    var tail: TourTail?
    /// The card covers its step's lit part (a room too small beside it): the dim then has no cutout
    /// and no ring, since what is left of them would peek out beside the card as slivers.
    var coversTargets = false
}

// MARK: - The words

/// A stretch of a row's words; `strong` is a control's name, set semibold; `isNew` the "New:" that
/// starts a row about what this version adds (`TourPolicy.newPrefix`), set semibold in the accent.
struct TourSpan: Equatable {
    var text: String
    var strong = false
    var isNew = false
}

struct TourRow: Equatable {
    /// An SF Symbol (iOS 17.0 or older), decorative: VoiceOver never reads it.
    var symbol: String
    var spans: [TourSpan]
    /// What VoiceOver reads for the row (the key row's caps by their full names; "New:" with it).
    var spoken: String
    var text: String { spans.map(\.text).joined() }
    /// The row starts with "New:": it is about what this version adds.
    var isNew: Bool { spans.first?.isNew == true }
}

/// What some of the words depend on, on this Mac and this device as they are now (StreamScreen
/// builds it at each render): a row about something this Mac or this device lacks is left out or
/// worded for that, never said wrong. An older Mac (Sill for Mac 0.5.1) has no clipboard and no
/// sound, and its Virtual Display is off unless turned on there.
struct TourFeatures: Equatable {
    /// The Menus button is on screen (its target reported: the Mac sent menus, and the bar holds it).
    var menus: Bool
    /// This device's Three-Finger Gestures are on, and the Mac takes them (its window list says so).
    var gestures: Bool
    /// The Mac's Virtual Display setting is on.
    var virtualDisplay: Bool
    /// The Mac shares its clipboard (its window list says so).
    var clipboard: Bool
    /// Paste on ‹Mac› Right Away, this device's own (on unless turned off).
    var pasteRightAway: Bool
    /// The Mac has sound: its settings carry Send Audio, on or off.
    var sound: Bool
}

struct TourCopy: Equatable {
    var title: String
    var subtitle: String?
    var rows: [TourRow]
    /// Where the lit part is, as VoiceOver's hint on the title.
    var hint: String
}

// MARK: - The rules

enum TourPolicy {
    /// A second after the picture, or after a turn, with nothing happening in it.
    static let beat = 1.0

    /// Every step of a layout, in order: four sideways, five upright. Under VoiceOver the picture's
    /// step goes: VoiceOver takes its gestures for itself, and the picture is no accessibility element.
    static func steps(_ layout: TourLayout, voiceOver: Bool) -> [TourTopic] {
        let all: [TourTopic] = layout == .landscape ? [.touch, .bar, .sharing, .settings] : [.touch, .bar, .sharing, .settings, .laptop]
        return voiceOver ? all.filter { $0 != .touch } : all
    }

    /// The steps only this layout has: all a turn offers. Upright: the keys and the trackpad;
    /// sideways: none.
    static func only(_ layout: TourLayout) -> [TourTopic] {
        layout.upright ? [.laptop] : []
    }

    /// What each step lights. Sideways the leading vertical rail carries Apps, Menus, Keyboard and
    /// Settings (no thumbnail strip); upright the single bar below the picture carries Apps, the
    /// thumbnails, Menus, Keyboard and Settings. The clipboard's and the sound's card lights Settings,
    /// where their switches are.
    static func targets(_ topic: TourTopic, _ layout: TourLayout) -> [TourTarget] {
        switch topic {
        case .touch: return [.stream]
        case .bar: return layout == .landscape ? [.apps, .menus, .keyboard] : [.strip, .menus, .keyboard]
        case .sharing: return [.settings]
        case .settings: return [.settings]
        case .laptop: return [.keys, .trackpad]
        }
    }

    /// The steps this device is owed in a layout: none once skipped, else those not yet seen.
    static func owed(_ layout: TourLayout, voiceOver: Bool, _ m: TourMemory) -> [TourTopic] {
        if m.skipped { return [] }
        return steps(layout, voiceOver: voiceOver).filter { !m.seen.contains($0) }
    }

    /// The automatic tour's one decision per session and layout (§4): at the picture, or at the
    /// first turn after it, a beat later and only if nothing has happened since.
    static func automatic(_ m: TourMoment, _ layout: TourLayout, _ memory: TourMemory) -> TourDecision {
        guard m.enabled else { return .pass(.nothingOwed) }
        guard !m.offered else { return .pass(.nothingOwed) }
        guard let picture = m.pictureAt else { return .wait(until: nil) }
        // Before the picture's decision every step owed in this layout, from the picture or from
        // a rotation during the beat, which starts it again. After it, a turn: only the steps this
        // layout has alone, from the turn, or from the picture of a session that went on with an
        // earlier one's decision (the automatic reconnect's: `nextSession`) in a layout that one
        // never decided in.
        let owedHere = owed(layout, voiceOver: m.voiceOver, memory)
        let list = m.decided ? owedHere.filter { only(layout).contains($0) } : owedHere
        let opens = max(picture, m.layoutAt)
        if list.isEmpty { return .pass(.nothingOwed) }
        if let activity = m.lastActivityAt, activity >= opens { return .pass(.used) }
        if m.now < opens + beat { return .wait(until: opens + beat) }
        if m.touchesDown > 0 { return .pass(.busy) }
        if m.busy { return .pass(.busy) }
        return .show(list)
    }

    // MARK: Memory

    /// The tour's version: 2 since 0.6, whose cards mark what's new and show once more to every device
    /// that saw or skipped version 1's (0.5 and 0.5.1 stored none). Raise it, and mark the new rows,
    /// when a release's tour should show once more.
    static let version = 2

    /// What is saved, as this version reads it (TourStore, at the stream screen): a memory of an older
    /// version's tour, or with no version at all (a fresh install, and 0.5 and 0.5.1, which stored
    /// none), is cleared, nothing seen and not skipped, and `write` says to store that with this
    /// version, so the tour shows once more and once only; this version's memory, or a later build's
    /// (back on this one after a downgrade), is kept as it is, and its version never lowered.
    static func upgraded(_ saved: TourMemory, savedVersion: Int?) -> (memory: TourMemory, write: Bool) {
        guard let v = savedVersion, v >= version else { return (TourMemory(), true) }
        return (saved, false)   // this version's, or a later build's: kept, never lowered
    }

    /// Next or Done passed a step.
    static func passed(_ t: TourTopic, _ m: TourMemory) -> TourMemory {
        var memory = m
        memory.seen.insert(t)
        return memory
    }

    /// Skip: no automatic tour again on this device. Take the Tour still shows it.
    static func skipped(_ m: TourMemory) -> TourMemory {
        var memory = m
        memory.skipped = true
        return memory
    }

    /// Skip on a card (Esc and VoiceOver's escape gesture are Skip too): in the automatic tour it
    /// turns the tour off for good on this device (`skipped`); in Take the Tour it only closes the
    /// run, since the person asked for that one, and what the automatic tour still owes (the
    /// upright card, a topic a later build adds) stays owed.
    static func skip(_ run: TourRun, _ m: TourMemory) -> TourMemory {
        run.replay ? m : skipped(m)
    }

    // MARK: Sessions

    /// A new session's start. The automatic reconnect's session (a Wi-Fi drop, the Mac waking, an
    /// eviction after a trip to another app, Sill.app relaunched) goes on with the last session's
    /// decisions, so someone who started at once is not walked through the tour when the picture
    /// comes back; unless the last one ended before its picture's decision, or in the middle of a
    /// run, which then comes back with a beat of its own. A session the person starts (a row's
    /// tap, pairing, a link, a launch) decides afresh.
    static func nextSession(after last: TourSession, reconnected: Bool) -> TourSession {
        guard reconnected, last.decided, !last.running else { return TourSession() }
        return TourSession(decided: true, offered: last.offered, running: false)
    }

    // MARK: Runs

    /// The automatic tour: the steps owed, from the first.
    static func run(owed list: [TourTopic]) -> TourRun? {
        guard let first = list.first else { return nil }
        return TourRun(steps: list, at: first, replay: false)
    }

    /// Take the Tour: every step of the layout on screen (under VoiceOver, less what it leaves out),
    /// from `start` when the layout has it, else from the first.
    static func replay(_ layout: TourLayout, voiceOver: Bool, from start: TourTopic? = nil) -> TourRun? {
        let list = steps(layout, voiceOver: voiceOver)
        guard let first = list.first else { return nil }
        let at = start.flatMap { list.contains($0) ? $0 : nil } ?? first
        return TourRun(steps: list, at: at, replay: true)
    }

    /// Next or Done: the step showing is passed; the next step, or nil when that was the last.
    static func next(_ run: TourRun) -> TourRun? {
        var moved = run
        moved.passed.insert(run.at)
        guard let i = run.steps.firstIndex(of: run.at), i + 1 < run.steps.count else { return nil }
        moved.at = run.steps[i + 1]
        return moved
    }

    /// A layout change mid-run (a rotation, a resize, the Duo folded): the run as the new layout
    /// has it, or nil when that layout has nothing left of it (the tour ends, nothing more saved).
    /// Its steps are the new layout's (Take the Tour: all of them; the automatic tour: those owed,
    /// and those this run passed, so the count goes on where it was). The step on screen stays
    /// when the new layout has it; otherwise the next step after it that this run has not passed.
    static func carry(_ run: TourRun, to layout: TourLayout, voiceOver: Bool, memory: TourMemory) -> TourRun? {
        let all = steps(layout, voiceOver: voiceOver)
        let list = run.replay ? all : all.filter { !memory.seen.contains($0) || run.passed.contains($0) }
        var carried = run
        carried.steps = list
        if list.contains(run.at) { return carried }
        guard let next = list.first(where: { $0 > run.at && !run.passed.contains($0) }) else { return nil }
        carried.at = next
        return carried
    }

    // MARK: Where the card goes

    /// From the screen's edges; the bottom one sits above the home indicator.
    static let margin: CGFloat = 16
    /// Between a card and the targets it sits beside.
    static let gap: CGFloat = 12
    static let tailSize = CGSize(width: 16, height: 7)
    /// The tail's tip keeps this far from the card's corners, so its base stays on the straight edge.
    static let tailCorner: CGFloat = 28
    /// Upright, a tail points down only at targets that begin this close below the card.
    static let tailReach: CGFloat = 48
    /// The cutout is this much larger than its targets all round.
    static let cutoutOutset: CGFloat = 4
    /// The least room beside its targets a card takes: its footer and a line or two of words at the
    /// largest text size. Only a smaller room (a tiny window) makes a card cover its targets.
    static let minimumRoom: CGFloat = 200

    /// The card's width: 360 pt; 480 on a screen held sideways that is under 520 pt tall (a phone,
    /// the Duo's outer display), where height is what runs out; 560 at accessibility text sizes;
    /// never more than the screen less its margins, nor, across the book pose's fold, than the page
    /// its `targets` are on (DuoPosture.pageWidth), nor wider than the room beside the leading rail
    /// sideways when that room holds a card.
    static func width(screen: CGSize, layout: TourLayout, accessibilityText: Bool, fold: FoldInfo = .inferred,
                      targets: CGRect? = nil) -> CGFloat {
        let short = layout == .landscape && screen.height < 520
        let preferred: CGFloat = accessibilityText ? 560 : (short ? 480 : 360)
        let page = DuoPosture.pageWidth(screenWidth: screen.width, margin: margin, fold: fold, for: targets) ?? .infinity
        let besideRail: CGFloat
        if layout == .landscape, let t = targets, !t.isNull, !t.isEmpty, t.maxX <= StreamLayout.railWidth + 16 {
            let rightEdge = fold.verticalBand.map { min(screen.width - margin, $0.minX) } ?? (screen.width - margin)
            let room = rightEdge - (t.maxX + gap)
            besideRail = room >= minimumRoom ? room : .infinity
        } else {
            besideRail = .infinity
        }
        return max(0, min(preferred, page, besideRail, screen.width - 2 * margin))
    }

    /// The crease of the Duo half-folded upright, its laptop pose: on iOS 27.1 the top of the fold's
    /// real band; before it `ConnectLayout.topHalf`'s rule (taller than wide, 600 to 740 pt wide,
    /// under 1100 pt tall), where it is the portrait layout's own split (DuoPosture.crease). Nothing
    /// of the tour crosses it.
    static func crease(_ screen: CGSize, _ fold: FoldInfo = .inferred) -> CGFloat? {
        guard let band = DuoPosture.crease(screen, fold) else { return nil }
        if case .inferred = fold { return band.top.rounded() }
        return band.top
    }

    /// The lit part: the step's targets as one rectangle, `cutoutOutset` larger all round and
    /// clipped to the screen.
    static func cutout(_ targets: [CGRect], screen: CGSize) -> CGRect? {
        let found = targets.filter { !$0.isNull && !$0.isEmpty }
        guard let first = found.first else { return nil }
        let union = found.dropFirst().reduce(first) { $0.union($1) }
        let lit = union.insetBy(dx: -cutoutOutset, dy: -cutoutOutset).intersection(CGRect(origin: .zero, size: screen))
        return lit.isNull || lit.isEmpty ? nil : lit
    }

    /// The cutout's corner radius: the picture's 12 plus the outset; the bar's buttons (Settings for
    /// the clipboard's and the sound's card too) and the laptop half's caps and pad, 20.
    static func radius(_ topic: TourTopic) -> CGFloat {
        topic == .touch ? 16 : 20
    }

    /// Where the card goes, in the screen's space (§6.3). `card` is its width and the height its
    /// words want there; `targets` the union of what its step lights (nil before they are
    /// measured: centred in the picture); `stream` the picture's panel.
    ///
    /// - The picture's step: centred in the picture. Too tall for the picture, it grows toward the
    ///   top margin, then, upright without a crease, toward the bottom margin.
    /// - Sideways, a rail step: 12 pt to the right of the leading rail, centred vertically on its
    ///   targets and off the book pose's fold; if there is not enough room beside the rail, centred
    ///   in the screen with `coversTargets`.
    /// - Upright: in the picture's half, so it never covers the controls it is about and never
    ///   crosses the crease; a lower step's bottom 12 pt above the picture's bottom, with a tail
    ///   down only when its targets begin within 48 pt and no crease lies between. Too tall for
    ///   that: it grows toward the top margin, then down to 12 pt above its targets (with a crease,
    ///   the picture's half); on a phone under its targets when it fits there or that room is larger.
    static func place(card: CGSize, targets: CGRect?, isStream: Bool, screen: CGSize, layout: TourLayout,
                      stream: CGRect, bottomInset: CGFloat, fold info: FoldInfo = .inferred) -> TourPlacement {
        let w = card.width
        let h = max(0, card.height)
        let top = margin
        let bottom = max(top, screen.height - margin - max(0, bottomInset))
        let fold = crease(screen, info)
        let pictureBottom = min(bottom, max(top, min(stream.maxY - gap, fold.map { $0 - margin } ?? .infinity)))

        func x(centredOn mid: CGFloat) -> CGFloat {
            DuoPosture.offTheFold(x: clamped(mid), width: w, screenWidth: screen.width, margin: margin, fold: info)
        }
        func clamped(_ mid: CGFloat) -> CGFloat {
            let lo = margin, hi = screen.width - margin - w
            return hi < lo ? (screen.width - w) / 2 : min(max(mid - w / 2, lo), hi)
        }
        func tip(_ card: CGRect, _ mid: CGFloat) -> CGFloat {
            card.width < 2 * tailCorner ? card.midX : min(max(mid, card.minX + tailCorner), card.maxX - tailCorner)
        }

        guard !isStream, let t = targets, !t.isNull, !t.isEmpty else {
            // The picture's step (or targets not measured yet): centred in the picture, then
            // toward the top; upright on a screen without a crease, also toward the bottom.
            let lowest = layout == .landscape ? bottom : pictureBottom
            let cardX = x(centredOn: stream.midX)
            if lowest - h >= top {
                let y = min(max(stream.midY - h / 2, top), lowest - h)
                return TourPlacement(card: CGRect(x: cardX, y: y, width: w, height: h), tail: nil)
            }
            let reach = layout.upright && fold == nil ? bottom : lowest
            return TourPlacement(card: CGRect(x: cardX, y: top, width: w, height: min(h, reach - top)), tail: nil)
        }

        let cardX = x(centredOn: t.midX)
        let lit = t.insetBy(dx: -cutoutOutset, dy: -cutoutOutset)
        if layout == .landscape {
            // Sideways: controls live in the leading vertical rail, so place the card 12 pt to its
            // right, vertically centred on its targets and kept off the book pose's fold.
            let beside = t.maxX + gap
            let placedX = DuoPosture.offTheFold(x: beside, width: w, screenWidth: screen.width, margin: margin, fold: info)
            let roomH = max(0, bottom - top)
            let cardH = min(h, roomH)
            let y = min(max(t.midY - cardH / 2, top), bottom - cardH)
            if placedX >= beside && placedX + w <= screen.width - margin + 0.5 {
                let rect = CGRect(x: placedX, y: y, width: w, height: cardH)
                return TourPlacement(card: rect, tail: nil, coversTargets: rect.intersects(lit))
            }
            let rect = CGRect(x: cardX, y: y, width: w, height: cardH)
            return TourPlacement(card: rect, tail: nil, coversTargets: rect.intersects(lit))
        }

        // Upright: a tail down only at targets that begin within 48 pt, with no crease between.
        func tailDown(_ rect: CGRect) -> TourTail? {
            let reaches = t.minY >= rect.maxY && t.minY - rect.maxY <= tailReach
            let noFold = fold.map { !(rect.maxY <= $0 && $0 <= t.minY) } ?? true
            return reaches && noFold ? TourTail(edge: .down, x: tip(rect, t.midX)) : nil
        }
        // Its bottom 12 pt above the picture's bottom while it fits in the picture's half.
        if pictureBottom - h >= top {
            let rect = CGRect(x: cardX, y: pictureBottom - h, width: w, height: h)
            return TourPlacement(card: rect, tail: tailDown(rect))
        }
        // Too tall: from the top margin down to 12 pt above its targets (with a crease, the
        // picture's half); on a phone under its targets when it fits there, or when that room is
        // the larger; only a room too small for a card makes it grow toward the bottom margin, over
        // them.
        let above = fold == nil ? min(bottom, max(top, t.minY - gap)) : pictureBottom
        if layout == .phone && h > above - top {
            let under = t.maxY + gap
            let room = bottom - under
            if h <= room || (room > above - top && room >= minimumRoom) {
                let rect = CGRect(x: cardX, y: under, width: w, height: min(h, room))
                return TourPlacement(card: rect, tail: TourTail(edge: .up, x: tip(rect, t.midX)))
            }
        }
        if fold != nil || h <= above - top || above - top >= minimumRoom {
            // A phone's card stands on its targets; the halves' grows from the top margin, over the
            // picture, which is the most room there is.
            let y = layout == .phone ? max(top, above - h) : top
            let rect = CGRect(x: cardX, y: y, width: w, height: min(h, above - top))
            return TourPlacement(card: rect, tail: tailDown(rect))
        }
        let rect = CGRect(x: cardX, y: top, width: w, height: min(h, bottom - top))
        return TourPlacement(card: rect, tail: nil, coversTargets: rect.intersects(lit))
    }

    // MARK: The words (§7)

    static let skipTitle = "Skip"
    static let nextTitle = "Next"
    static let doneTitle = "Done"
    static let skipHint = "Ends the tour. Take the Tour in Settings shows it again."
    /// The Settings panel's last row.
    static let takeTourTitle = "Take the Tour"
    static func takeTourFootnote(device: String) -> String { "A short tour of Sill’s controls on this \(device)." }
    static func takeTourHint(device: String) -> String { "Shows how to use Sill on this \(device)." }

    /// The title as VoiceOver reads it: its place in the run, when the run has more than one card.
    static func spokenTitle(_ copy: TourCopy, index: Int, count: Int) -> String {
        count > 1 ? "\(copy.title), step \(index + 1) of \(count)" : copy.title
    }

    /// What starts a row about what this version's tour adds (a row built with `new: true`): drawn
    /// semibold in the accent (TourCard.attributed), and read by VoiceOver with the row ("New: Pinch
    /// to zoom…"). Which rows carry it is this version's: the next tour version clears its marks.
    static let newPrefix = "New:"

    /// A step's card. ‹Mac› is the Mac's name ("your Mac" when there is none yet); ‹device› is
    /// "iPad" or "iPhone". Under VoiceOver the rows that name a gesture say VoiceOver's way instead,
    /// or go (the trackpad's, Reverse Scrolling's and the thumbnail hold's: the trackpad is no
    /// accessibility element, and VoiceOver has no drag or hold of its own). `keysOnItsSide`: the
    /// iPhone Duo open (its inner display), which shows the keys and the trackpad with the device
    /// turned on its side, so its words say so where an iPhone's say upright. `thumbnails`: false for
    /// a phone with Larger Picture in effect (a window streaming with the switch on), whose bar card
    /// is about Apps where the thumbnails were. `features`: what this Mac and this device have now;
    /// a row about what they lack is left out or worded for that.
    ///
    /// Tour version 2 (0.6; Noah, 2026-10-31: "Mark the new features with 'New:' and make the tutorial
    /// run for anyone who launches this version for the first time. You don't need to explain the Aa
    /// stuff, maybe add an explanation with Virtual Desktop's explanation"): the rows about what is new
    /// since the tour was written start with "New:" (`newPrefix`): what 0.6 adds, and what came after the
    /// tour of 0.5 without a card of its own (the Menus button, the three-finger gestures, Virtual
    /// Display in either form), which that tour never explained. Aa is named only in the Virtual
    /// Display row.
    static func copy(_ t: TourTopic, _ layout: TourLayout, mac: String, device: String,
                     voiceOver: Bool, firstOfRun: Bool, keysOnItsSide: Bool = false,
                     features: TourFeatures) -> TourCopy {
        let mac = mac.isEmpty ? "your Mac" : mac
        let iPad = device == "iPad"
        switch t {
        case .touch:
            var rows = [row("hand.tap", [strong("Tap"), plain(" to click.")]),
                        row("contextualmenu.and.cursorarrow", [strong("Touch and hold"), plain(" to right-click.")]),
                        row("hand.draw", [strong("Drag"), plain(" to scroll.")])]
            if iPad { rows.append(row("applepencil", [strong("Apple Pencil"), plain(" works as a mouse.")])) }
            rows.append(row("plus.magnifyingglass", [strong("Pinch"), plain(" to zoom the picture here, up to 5×. Zoomed in, two fingers move it, and one finger still taps, holds and drags on \(mac).")], new: true))
            if features.gestures {
                rows.append(row("hand.raised.fingers.spread", [strong("Swipe with three fingers"), plain(": up for Mission Control, down for App Exposé, and sideways between Spaces.")], new: true))
            }
            let hint: String
            switch layout {
            case .landscape: hint = "The picture of \(mac) fills the screen beside the rail."
            case .portrait, .phone: hint = "The picture of \(mac) is at the top of the screen."
            }
            return TourCopy(title: "Tap, Hold, Drag and Pinch", subtitle: "What you do here happens on \(mac).", rows: rows, hint: hint)
        case .bar:
            var rows: [TourRow]
            if layout == .landscape {
                rows = [voiceOver
                    ? row("magnifyingglass", [strong("Apps"), plain(" lists the apps on \(mac) and the Desktop. Choose an open app again for its next window.")])
                    : row("magnifyingglass", [strong("Apps"), plain(" lists the apps on \(mac) and the Desktop: tap an open app again for its next window.")])]
            } else if voiceOver {
                rows = [row("hand.point.up.left", [strong("Each window"), plain(" has actions: close, minimize, full screen, and move left or right. Swipe up or down to hear them.")])]
            } else {
                rows = [row("hand.point.up.left", [strong("Touch and hold"), plain(" a window to close, minimize or go full screen. Keep holding and drag to move it.")])]
            }
            if features.menus {
                rows.append(row("filemenu.and.selection", [strong("Menus"), plain(" has the menu bar of the app you’re using on \(mac).")], new: true))
            }
            let textSize = [plain("; "), strong("Text Size"), plain(" in Settings then sizes its text.")]
            if features.virtualDisplay {
                rows.append(row("display", [strong("Virtual Display"), plain(" is on: a window you pick streams from a display of its own on \(mac), so it keeps updating when something covers it")] + textSize, new: true))
            } else {
                rows.append(row("display", [strong("Virtual Display"), plain(", in Settings, streams a window you pick from a display of its own on \(mac), so it keeps updating when something covers it")] + textSize, new: true))
            }
            rows.append(row("keyboard", [strong("Keyboard"), plain(" brings up the on-screen keyboard with a trackpad and keys to type on \(mac).")]))
            rows.append(row("keyboard.badge.ellipsis", [strong("A hardware keyboard"), plain(" types on \(mac) by itself, Esc included, and "), strong("Keyboard"), plain(" then brings up the keyboard bar.")], new: true))
            let hint: String
            switch layout {
            case .landscape: hint = features.menus ? "In the rail on the left: Apps, Menus and Keyboard."
                                                   : "In the rail on the left: Apps and Keyboard."
            case .portrait, .phone: hint = "In the bar below the picture, after Apps."
            }
            let title = features.menus ? "Windows and Menus" : "Windows"
            return TourCopy(title: title, subtitle: nil, rows: rows, hint: hint)
        case .sharing:
            var rows: [TourRow] = []
            if features.clipboard {
                rows.append(row("doc.on.clipboard", [plain("With "), strong("Share Clipboard"), plain(", text you copy on \(mac) is ready to paste on this \(device).")], new: true))
                rows.append(row("doc.on.doc", [plain("Copy on this \(device), then come back to Sill: "), strong("Paste on \(mac)"),
                                               plain(", on the note Sill shows then or in Settings,"),
                                               plain(features.pasteRightAway ? " puts it where \(mac)’s cursor is." : " sends it to \(mac)’s clipboard.")], new: true))
            }
            if features.sound {
                rows.append(row("speaker.wave.2", [strong("Send Audio"), plain(", a beta, plays \(mac)’s sound here, and "), strong("Mute"), plain(" silences this \(device) alone.")], new: true))
            }
            if !features.clipboard && !features.sound {
                rows.append(row("arrow.down.circle", [strong("Update Sill on \(mac)"), plain(" to copy and paste between it and this \(device), and to hear its sound here.")], new: true))
            }
            let title = features.clipboard == features.sound ? "Clipboard and Sound" : features.clipboard ? "Clipboard" : "Sound"
            return TourCopy(title: title, subtitle: nil, rows: rows,
                            hint: layout == .landscape ? "In Settings, at the bottom of the rail on the left."
                                                       : "In Settings, the last button in the bar below the picture.")
        case .settings:
            var rows = [row("xmark.circle", [strong("Disconnect"), plain(" is at the bottom of Settings.")]),
                        row("questionmark.circle", [strong("Take the Tour"), plain(" is there too, to see this again.")])]
            if !voiceOver {
                rows.append(row("arrow.up.arrow.down", [strong("Reverse Scrolling"), plain(" turns a finger’s drag and the on-screen trackpad’s two-finger scroll around.")], new: true))
                rows.append(row("timer", [strong("Hold to Show Window Controls"), plain(" sets how long you hold a window’s thumbnail before its controls show.")], new: true))
            }
            if layout == .landscape {
                let turn = keysOnItsSide ? "Turn your \(device) on its side" : "Hold your \(device) upright"
                rows.append(row(iPad ? "ipad" : "iphone", [strong(turn), plain(" for a trackpad and keys.")]))
            }
            return TourCopy(title: "Settings", subtitle: nil, rows: rows,
                            hint: layout == .landscape ? "At the bottom of the rail on the left."
                                                       : "The last button in the bar below the picture.")
        case .laptop:
            var rows: [TourRow]
            if voiceOver {
                rows = [row("command", [strong("cmd, opt, ctrl and shift"), plain(" stay on for the next key: cmd, then C, copies.")],
                            spoken: "Command, Option, Control and Shift stay on for the next key: Command, then C, copies.")]
            } else {
                rows = [row("command", [strong("cmd, opt, ctrl and shift"), plain(" stay on for the next key or trackpad click: tap cmd, then C, to copy.")],
                            spoken: "Command, Option, Control and Shift stay on for the next key or trackpad click: tap Command, then C, to copy.")]
            }
            if !voiceOver {
                rows.append(row("cursorarrow.click.2", [strong("Tap with two fingers"), plain(" on the trackpad to right-click.")]))
                rows.append(row("hand.draw", [strong("Touch and hold"), plain(" the trackpad, "), strong("then drag"), plain(", to move a window or select text.")]))
            }
            let subtitle = keysOnItsSide ? "On its side, Sill adds keys and a trackpad." : "Upright, Sill adds keys and a trackpad."
            return TourCopy(title: "Keys and Trackpad", subtitle: firstOfRun ? subtitle : nil, rows: rows,
                            hint: "Below the bar: the trackpad, then the row of keys.")
        }
    }

    private static func strong(_ text: String) -> TourSpan { TourSpan(text: text, strong: true) }
    private static func plain(_ text: String) -> TourSpan { TourSpan(text: text, strong: false) }
    /// A row; `new`: about what this version adds, so "New: " goes ahead of its words, the same in
    /// what VoiceOver reads.
    private static func row(_ symbol: String, _ spans: [TourSpan], spoken: String? = nil, new: Bool = false) -> TourRow {
        let mark = new ? [TourSpan(text: newPrefix, strong: true, isNew: true), TourSpan(text: " ")] : []
        let all = mark + spans
        return TourRow(symbol: symbol, spans: all, spoken: spoken.map { mark.map(\.text).joined() + $0 } ?? all.map(\.text).joined())
    }
}
