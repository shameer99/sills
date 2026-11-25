import Foundation
import CoreGraphics

// The iPhone Duo's posture, and the layout rules that follow from it (docs/iphone-duo-plan.md).
//
// Pure: Foundation and CoreGraphics only, so Tests/checks/duo compiles it with swiftc on its own. Its
// inputs come from DuoPostureReader.swift, which reads iOS 27.1's hinge (`onHingeChange`) and the
// fold's reserved region (`GeometryProxy.reservedRegions(kind: .division)`). Before iOS 27.1, and on
// any device without a hinge (every iPhone and iPad until the Duo), nothing is known and every rule
// here answers exactly as the size alone did before (`FoldInfo.inferred`).
//
// What the device reports, measured on the iOS 27.1 simulator (the plan's Facts): one window scene
// that moves between the displays as the hinge closes and opens; on the inner display (951×669 pt
// sideways, 669×951 upright) a `.division` region 40 pt wide down the middle of its longer side (the
// crease at 475.5, with 20 pt of margin each side), active exactly while the hinge is partly open
// (the book and laptop poses) and inactive open flat; on the cover (466×678, 678×466) none.

/// What a layout knows of a fold across it.
enum FoldInfo: Equatable {
    /// Nothing known (before iOS 27.1, a device without a hinge): the rules infer the half-folded
    /// Duo's crease from the screen's size alone, exactly as before.
    case inferred
    /// The device said: the band nothing interactive sits on while the display is half-folded (the
    /// fold's reserved region, margins included, in the layout's own space and clipped to it), or
    /// nil when nothing is folded across this screen (open flat, the cover).
    case known(CGRect?)

    /// The band, when the device said there is one.
    var band: CGRect? {
        if case .known(let band) = self { return band }
        return nil
    }

    /// A fold down the middle of a screen held sideways: the book pose.
    var verticalBand: CGRect? {
        guard let band, band.height > band.width else { return nil }
        return band
    }

    /// A fold across a screen held upright: the laptop pose.
    var horizontalBand: CGRect? {
        guard let band, band.width >= band.height else { return nil }
        return band
    }
}

/// The posture as one screen of Sill sees it: the hinge, and the fold in that screen's own space.
struct DuoPosture: Equatable {
    /// The hinge as iOS 27.1 reports it (`DeviceHinge.Status`); `unknown` before iOS 27.1 and on a
    /// device without one.
    enum Hinge: String, Equatable {
        case unknown, closed, partiallyOpen, fullyOpen
    }

    /// The six poses, in duorig's words (Tests/duorig); `unknown` when nothing is known.
    enum Pose: String, Equatable {
        case unknown
        case book
        case laptop
        case flatLandscape = "flat-landscape"
        case flatPortrait = "flat-portrait"
        case closedUpright = "closed-upright"
        case closedSide = "closed-side"
    }

    var hinge: Hinge = .unknown
    /// The display's fold (its `.division` reserved region, margins included) in the screen's own
    /// space, in the way or not; nil on a display without one (the cover).
    var fold: CGRect? = nil

    static let unknown = DuoPosture()

    /// The fold is in the way exactly while the hinge is partly open: iOS reports the region active
    /// then and only then (90° and 174° alike), and the hinge's change is what redraws the layouts.
    var foldActive: Bool { hinge == .partiallyOpen && fold != nil }

    /// What the layout rules get for a screen of `size`.
    func info(in size: CGSize) -> FoldInfo {
        guard hinge != .unknown else { return .inferred }
        guard foldActive, let fold else { return .known(nil) }
        let band = fold.intersection(CGRect(origin: .zero, size: size))
        return .known(band.isNull || band.isEmpty ? nil : band)
    }

    /// Which of the six poses a screen of `size` is in.
    func pose(_ size: CGSize) -> Pose {
        let sideways = size.width > size.height
        switch hinge {
        case .unknown: return .unknown
        case .closed: return sideways ? .closedSide : .closedUpright
        case .partiallyOpen: return sideways ? .book : .laptop
        case .fullyOpen: return sideways ? .flatLandscape : .flatPortrait
        }
    }

    /// The hinge open: Sill is on the inner display (the book, laptop and open flat poses).
    var onInnerDisplay: Bool { hinge == .partiallyOpen || hinge == .fullyOpen }

    /// The hinge to go by: what `onHingeChange` reported, or, before its first call (a frame or two
    /// after launch on a device, longer in the simulator), what the display's fold says where it has
    /// one (only the inner display does): in the way, half-folded; not, open flat. Neither: unknown,
    /// as on every device without a hinge, where no display has a fold.
    static func hinge(reported: Hinge, regionActive: Bool?) -> Hinge {
        guard reported == .unknown, let regionActive else { return reported }
        return regionActive ? .partiallyOpen : .fullyOpen
    }

    /// Whether the stream screen hides the status bar: on the inner display in every pose (Noah,
    /// 2026-10-09: option 1 of the three the mock canvas drew side by side). Upright (the laptop
    /// pose, open flat upright) it would take 82 pt at the top out of the picture above the fold;
    /// sideways (the book pose, open flat sideways) an 84 pt strip at the side out of the picture's
    /// width, so Sill has all 951 pt and the book pose's bar keeps its regular size (`bookBar`). It
    /// stays on the cover, as on an iPhone, and on every other screen in every pose (the connect
    /// screen keeps the clock and the Wi-Fi it asks about). The alternatives: `pose == .laptop ||
    /// pose == .flatPortrait` here keeps it sideways; dropping StreamScreen's `.duoStatusBar` line
    /// keeps it everywhere.
    static func hidesStatusBar(_ pose: Pose) -> Bool {
        pose == .laptop || pose == .flatPortrait || pose == .book || pose == .flatLandscape
    }

    /// "book, the fold x 455.5–495.5 in the way, 951×669", for the DEBUG console.
    func describe(_ size: CGSize) -> String {
        func n(_ v: CGFloat) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", Double(v)) }
        var words = pose(size).rawValue
        if let fold {
            let along = fold.height > fold.width ? "x \(n(fold.minX))–\(n(fold.maxX))" : "y \(n(fold.minY))–\(n(fold.maxY))"
            words += ", the fold \(along) " + (foldActive ? "in the way" : "flat")
        }
        return words + ", \(n(size.width))×\(n(size.height))"
    }
}

// MARK: - The laptop pose: the crease across a screen held upright

extension DuoPosture {
    /// The fold across a screen held upright, its top and bottom edges. Known: the band of the
    /// laptop pose, else none (open flat nothing pins the split). Inferred, as before iOS 27.1: the
    /// middle of a screen taller than wide, 600 to 740 pt wide and under 1100 tall (the half-folded
    /// Duo as Sill's first numbers, 710×1000, guessed it), as a band of no height.
    static func crease(_ size: CGSize, _ fold: FoldInfo) -> (top: CGFloat, bottom: CGFloat)? {
        switch fold {
        case .inferred:
            guard size.height > size.width, size.width >= 600, size.width < 740, size.height < 1100 else { return nil }
            return (size.height / 2, size.height / 2)
        case .known:
            guard let band = fold.horizontalBand else { return nil }
            return (band.minY, band.maxY)
        }
    }

    /// The room above a fold the device reported across the screen (the laptop pose), from the
    /// screen's top: the connect screen's column lives and scrolls there, so that a long list or a
    /// card never runs onto the fold. Nil for the inferred crease (as before iOS 27.1, where the
    /// column is only centred in the top half) and without a fold across.
    static func roomAboveFold(_ size: CGSize, _ fold: FoldInfo) -> CGFloat? {
        guard case .known = fold, let crease = crease(size, fold) else { return nil }
        return max(0, crease.top)
    }

    /// The pane's shape open flat: the picture's own (`video`, in pixels) while the Mac keeps the
    /// window's shape; 16:10 before there is a picture, and while the Mac fits the window to the pane
    /// (a window with Aa set, or on the virtual display), so the pane never follows a shape it gave
    /// the window itself (an app's least size would shrink the pane step by step).
    static let defaultAspect: CGFloat = 1.6

    static func paneAspect(video: CGSize, fitsWindowToPane: Bool) -> CGFloat {
        guard !fitsWindowToPane, video.width > 0, video.height > 0 else { return defaultAspect }
        return video.width / video.height
    }
}

// MARK: - The software keyboard's glass in the laptop pose (KeyboardFrameMonitor)

extension DuoPosture {
    /// The software keyboard's glass as Sill knows it, in the screen's space: where it begins, or nil while
    /// Sill cannot tell (in the laptop pose, before a reading since the last change, or with only one that
    /// cannot be a keyboard).
    struct KeyboardGlass: Equatable {
        var top: CGFloat?
    }

    /// The top of `frame` when it can be the software keyboard's glass on a screen of `size`: as wide as the
    /// screen (within a point), down to its foot (within a point), of some height, and beginning under
    /// `controlsTop` (in the laptop pose the fold's lower edge: nothing of a keyboard is ever over it, and
    /// UIKit's page begins over it, at the fold's top edge); else nil.
    static func plausibleGlass(_ frame: CGRect?, size: CGSize, controlsTop: CGFloat) -> CGFloat? {
        guard let frame, frame.height > 0, abs(frame.width - size.width) <= 1, abs(frame.maxY - size.height) <= 1,
              frame.minY > controlsTop, frame.minY < size.height else { return nil }
        return frame.minY
    }

    /// Where the glass begins, in the screen's space; nil while no keyboard is up (`reported`, the top UIKit
    /// reports, nil or at or below the foot).
    /// - Open flat (`laptop` false) UIKit reports every keyboard as itself, live: its top.
    /// - In the laptop pose UIKit reports every keyboard as the whole lower page, (0, 455.5, 669×495.5) on
    ///   the Duo, whatever it draws at the foot (the English keyboard from 555, the emoji and Chinese
    ///   (Pinyin) ones from 506; the iOS 27.1 simulator), and the begin frame of a switch's report is UIKit's
    ///   last committed frame, the keyboard left or an older one. So only a reading tells: `read`, the begin
    ///   frame of the report Sill provokes by reloading its input views, which is the keyboard up at that
    ///   moment (KeyboardFrameMonitor), taken since the last change. None yet, or none that can be a
    ///   keyboard (`plausibleGlass`): not known.
    static func keyboardGlass(reported: CGFloat?, read: CGRect?, size: CGSize, controlsTop: CGFloat, laptop: Bool) -> KeyboardGlass? {
        guard let reported, reported < size.height else { return nil }
        guard laptop else { return KeyboardGlass(top: reported) }
        return KeyboardGlass(top: plausibleGlass(read, size: size, controlsTop: controlsTop))
    }

    /// The keyboard as its own views place it (KeyboardFrameMonitor's look, no side effects): of `frames`,
    /// the frames on the screen of the views in the scene's windows other than Sill's (the keyboard's: a
    /// container and the remote keyboard's placeholder, found by their geometry alone), the first as wide as
    /// the screen (within a point) and down to its foot whose top is more than a point under the top UIKit
    /// reports (`reported`). In the laptop pose UIKit reports the page (from the fold's top edge, 455.5)
    /// while these views sit where the keyboard is drawn, updated with each show and each switch as UIKit
    /// posts its report (the iOS 27.1 simulator: English 555, emoji 507 for a glass at 506); once anything
    /// has reloaded the input views they are the page as well, and tell nothing (nil).
    static func keyboardLook(_ frames: [CGRect], reported: CGRect?, screen: CGSize) -> CGRect? {
        guard let reported else { return nil }
        return frames.first { frame in
            frame.height > 0 && abs(frame.width - screen.width) <= 1 && abs(frame.maxY - screen.height) <= 1
                && frame.minY > reported.minY + 1 && frame.minY < screen.height
        }
    }

    /// Whether looks are off: UIKit's own report of the keyboard a switch left (`begin`, its frame as UIKit
    /// last committed it) begins more than 1.5 pt from where the last look put that keyboard (`lastLook`).
    /// On the simulator they agree within a point but around the emoji search, after which the views sit
    /// 9–10 pt under the glass (English read at 564 for a glass at 555).
    static func keyboardLookIsOff(lastLook: CGRect?, begin: CGRect?) -> Bool {
        guard let lastLook, let begin, begin.height > 0, !begin.isNull else { return false }
        return abs(lastLook.minY - begin.minY) > 1.5
    }

    /// When KeyboardFrameMonitor looks again after a change (each change restarts them), in seconds: looks
    /// cost nothing, and a late update of the keyboard's views must not matter.
    static let keyboardLookDelays: [Double] = [0.02, 0.06, 0.15, 0.4, 1, 2]
    /// How long after UITextInputMode's notification a switch's own report may come (55–190 ms on the
    /// simulator) before the keyboard is read by reloads instead: a switch with no report (the emoji search
    /// left; two keyboards of one height) leaves the keyboard's views where they were.
    static let keyboardSwitchReportWait: Double = 0.4

    /// Whether a keyboard's glass leaves room under `controlsTop` for a 44 pt row with 8 pt of margins
    /// (used by KeyboardFrameMonitor when deciding whether a stale look needs a reload check).
    static let keyboardRowLeast: CGFloat = 44
    static let keyboardRowMargins: CGFloat = 8
    static func keyboardRowFits(glassTop: CGFloat, controlsTop: CGFloat) -> Bool {
        glassTop - controlsTop >= keyboardRowLeast + keyboardRowMargins
    }

    /// What Sill remembers of the keyboards it has read in the laptop pose, to decide at once at a show or a
    /// switch and let the reading that follows correct it (KeyboardFrameMonitor): the height of each input
    /// mode's letters keyboard as last read (`letters`, by `keyboardHintKey`: the mode and the screen's width),
    /// and the height of the other keyboard a switch within one mode brings (`other`, by the width: the emoji
    /// keyboard; iOS 27's emoji keyboard is no input mode of its own) as last read. Filled only by readings,
    /// never by hand, and trusted only until the next reading; kept across launches (`Sill.keyboardHints`,
    /// never sent).
    struct KeyboardHints: Equatable, Codable {
        var letters: [String: Double] = [:]
        var other: [String: Double] = [:]
    }

    /// What came before a reading, for what it teaches and what to assume: a show, a switch to another input
    /// mode (the Globe key), a switch within the mode (😀, ABC, the emoji search), anything else (a fold,
    /// coming back to the front).
    enum KeyboardCause: Equatable { case show, modeChange, sameMode, other }

    static func keyboardHintKey(mode: String?, width: CGFloat) -> String { "\(mode ?? "")@\(Int(width.rounded()))" }
    static func keyboardWidthKey(_ width: CGFloat) -> String { "@\(Int(width.rounded()))" }

    /// Two keyboard heights are the same keyboard within 1.5 pt (a look puts the emoji keyboard at 444 where
    /// a reload reads 445).
    static func sameKeyboard(_ a: Double?, _ b: Double?) -> Bool {
        guard let a, let b else { return false }
        return abs(a - b) < 1.5
    }

    /// The hints after a reading of `height`, `cause` the change before it and `before` the height read
    /// before that change: a show's or another input mode's first reading is the mode's letters keyboard
    /// (unless it is the other keyboard as last read: iOS may bring that back at a show); after a switch
    /// within the mode, a reading that is neither the keyboard before it nor the letters keyboard is the
    /// other one. Anything else teaches nothing.
    static func keyboardHints(_ hints: KeyboardHints, after height: Double, cause: KeyboardCause, before: Double?,
                              key: String, widthKey: String) -> KeyboardHints {
        var learned = hints
        switch cause {
        case .show, .modeChange:
            if sameKeyboard(height, hints.other[widthKey]), !sameKeyboard(height, hints.letters[key]) { return hints }
            learned.letters[key] = height
        case .sameMode:
            guard !sameKeyboard(height, before), !sameKeyboard(height, hints.letters[key]) else { return hints }
            learned.other[widthKey] = height
        case .other:
            return hints
        }
        return learned
    }

    /// The keyboard height to assume at once at a change, before it is read (nil: none): a show, or a switch
    /// to another input mode: that mode's letters keyboard; a switch within the mode: from its letters
    /// keyboard the other one, from anything else its letters keyboard (ABC; the emoji search, which the
    /// reading that follows closes).
    static func keyboardPrediction(cause: KeyboardCause, current: Double?, hints: KeyboardHints, key: String, widthKey: String) -> Double? {
        switch cause {
        case .show, .modeChange: return hints.letters[key]
        case .sameMode:
            guard let letters = hints.letters[key] else { return nil }
            return sameKeyboard(current, letters) ? hints.other[widthKey] : letters
        case .other: return nil
        }
    }

    /// What started the readings: a report of the keyboard animating (`animating`, a will-show or
    /// will-change with its animation's duration: the keyboard coming), the report that ends that animation
    /// (`animated`: did-show, did-change), or anything else (a switch, a fold, coming back to the front, a
    /// report without an animation).
    enum KeyboardChange: Equatable {
        case animating(Double)
        case animated
        /// The screen folded into the laptop pose with the keyboard up (or unfolded).
        case fold
        case other
    }

    /// When KeyboardFrameMonitor reloads the input views to read the keyboard after a change, in seconds
    /// after it (each change restarts them), in the world where only a reload tells.
    static func keyboardReadDelays(after change: KeyboardChange) -> [Double] {
        switch change {
        case .animating(let duration): return [duration + 0.02, duration + 0.1, 1.5, 2.5]
        case .animated: return [0.01, 0.06, 1, 2]
        case .fold: return [0.15, 0.3, 0.45, 0.6, 0.8, 1, 1.5, 2]
        case .other: return [0.05, 0.09, 0.13, 0.18, 0.25, 0.32, 1, 2]
        }
    }

    /// How long nothing settles while the first reading after a change is on its way (`keyboardSettle`;
    /// after a fold longer: the first readings there are stale, `keyboardReadingIsStale`).
    static func keyboardSettle(after change: KeyboardChange) -> Double { change == .fold ? 1.2 : keyboardSettle }

    /// After a fold (`staleUntil`, two seconds), UIKit's reload report goes on giving the keyboard as it was in
    /// the other pose for about a second: a reading within half a point of the frame UIKit reported before the
    /// fold (`staleFrame`) is that, and no reading.
    static func keyboardReadingIsStale(_ begin: CGRect, staleFrame: CGRect?, at: Double, staleUntil: Double) -> Bool {
        guard let staleFrame, at < staleUntil else { return false }
        return abs(begin.minY - staleFrame.minY) < 0.5 && abs(begin.height - staleFrame.height) < 0.5
    }
    /// The late reloads of `keyboardReadDelays` (at a second and more): always made.
    static let keyboardLateRead: Double = 1

    /// A report this soon after Sill reloaded its input views is that reload's (25–70 ms on the simulator),
    /// so its begin frame is the reading (`keyboardReportIsReading`).
    static let keyboardReadWindow: Double = 0.5
    /// How long after the first of a run of changes a reading settles.
    static let keyboardSettle: Double = 0.8

    /// Whether a keyboard report at `at` is the reading of the reload Sill made at `reloadedAt`.
    static func keyboardReportIsReading(at: Double, reloadedAt: Double?, hiding: Bool, animated: Bool, begin: CGRect?) -> Bool {
        guard !hiding, !animated, let begin, begin.height > 0, !begin.isNull, let reloadedAt, at >= reloadedAt else { return false }
        return at - reloadedAt < keyboardReadWindow
    }

    /// Whether an early reload is still needed after the readings since the last change.
    static func keyboardReadsAgain(_ readings: [CGRect], before: CGRect?) -> Bool {
        func same(_ a: CGRect, _ b: CGRect?) -> Bool {
            guard let b else { return false }
            return abs(a.minY - b.minY) < 0.5 && abs(a.height - b.height) < 0.5 && abs(a.width - b.width) < 0.5
        }
        guard let first = readings.firstIndex(where: { !same($0, before) }) else { return true }
        return readings.count - first < 2
    }
}

// MARK: - The book pose: the fold down the middle of a screen held sideways

extension DuoPosture {

    /// Something `width` wide at `x` on a screen `screenWidth` wide, kept off a vertical fold's band
    /// (a tour card): moved as little as it takes, against the fold, onto the page its middle is on
    /// (the leading one on a tie) when that page holds it within `margin` of the screen's edge, else
    /// onto the other page when that one does; unchanged when it is clear of the band, or when no
    /// page holds it.
    static func offTheFold(x: CGFloat, width: CGFloat, screenWidth: CGFloat, margin: CGFloat, fold: FoldInfo) -> CGFloat {
        guard let band = fold.verticalBand, x < band.maxX, x + width > band.minX else { return x }
        let leadingFits = width <= band.minX - margin
        let trailingFits = width <= screenWidth - margin - band.maxX
        let leading = band.minX - width, trailing = band.maxX
        if x + width / 2 <= band.midX {
            if leadingFits { return leading }
            if trailingFits { return trailing }
        } else {
            if trailingFits { return trailing }
            if leadingFits { return leading }
        }
        return x
    }

    /// Where the window lights' menu goes (WindowLightsMenu), `size` and centred on its thumbnail at
    /// `x`, on the side `below` says, `gap` from it: kept off the fold, beside a vertical one onto a
    /// page (`offTheFold`, 8 pt from the screen's edge), and below its thumbnail when above it would
    /// sit on a horizontal one (the laptop pose, whose window bar is just under the fold).
    static func lightsMenu(x: CGFloat, below: Bool, thumbnail: CGRect, size: CGSize, gap: CGFloat, screenWidth: CGFloat,
                           fold: FoldInfo) -> (x: CGFloat, y: CGFloat, below: Bool) {
        func rect(below: Bool) -> CGRect {
            CGRect(x: x - size.width / 2, y: below ? thumbnail.maxY + gap : thumbnail.minY - gap - size.height,
                   width: size.width, height: size.height)
        }
        var down = below
        if !down, let band = fold.horizontalBand, rect(below: false).intersects(band) { down = true }
        let left = offTheFold(x: x - size.width / 2, width: size.width, screenWidth: screenWidth, margin: 8, fold: fold)
        return (left + size.width / 2, rect(below: down).midY, down)
    }

    /// The page beside a vertical fold that `target`'s middle is on (the leading one on a tie, as
    /// `offTheFold` decides), less the margin at the screen's edge: the most a card about it may be
    /// wide, so that it stays beside what it points at (with the status bar's strip shown, 867 pt,
    /// the trailing page is 355.5 and a 360 pt card about Settings would otherwise go to the far
    /// page). Without a target, the wider page. Nil without a vertical fold.
    static func pageWidth(screenWidth: CGFloat, margin: CGFloat, fold: FoldInfo, for target: CGRect? = nil) -> CGFloat? {
        guard let band = fold.verticalBand else { return nil }
        let leading = max(0, band.minX - margin), trailing = max(0, screenWidth - margin - band.maxX)
        guard let target, !target.isNull else { return max(leading, trailing) }
        return target.midX <= band.midX ? leading : trailing
    }

    /// The connect screen's column across the book pose's fold: centred in the leading page while
    /// it holds the column with 16 pt each side; elsewhere, as before, centred in the screen (at
    /// least 16 pt from its leading edge).
    static func columnX(columnWidth: CGFloat, screenWidth: CGFloat, fold: FoldInfo) -> CGFloat {
        let centred = max(16, (screenWidth - columnWidth) / 2)
        guard let band = fold.verticalBand, columnWidth + 32 <= band.minX else { return centred }
        return max(16, (band.minX - columnWidth) / 2)
    }

    /// The leading page's width, for content placed on it (the pairing overlay), when a vertical
    /// fold divides the screen.
    static func leadingPage(_ fold: FoldInfo) -> CGFloat? {
        fold.verticalBand.map { max(0, $0.minX) }
    }
}

// MARK: - The harness's stand-in (ContentView's -SillLayout and -SillHinge)

extension DuoPosture {
    /// The named space a harness's fake display defines, in which its stand-in fold is given.
    static let displaySpace = "sill.display"

    /// The hinge `-SillHinge closed|half|flat` stands in for.
    static func hinge(argument: String?) -> Hinge? {
        switch argument?.lowercased() {
        case "closed"?: return .closed
        case "half"?: return .partiallyOpen
        case "flat"?: return .fullyOpen
        default: return nil
        }
    }

    /// The fold the inner display reports, for the stand-in: 40 pt (20 each side of the crease)
    /// across the middle of the screen's longer side, in the display's own space.
    static func standInFold(_ size: CGSize) -> CGRect {
        size.width > size.height ? CGRect(x: size.width / 2 - 20, y: 0, width: 40, height: size.height)
                                 : CGRect(x: 0, y: size.height / 2 - 20, width: size.width, height: 40)
    }

    /// The safe area (top, leading, bottom, trailing) each of the Duo's displays gives Sill, as the
    /// probe measured it on the iOS 27.1 simulator: the inner display with its status bar, a strip
    /// of 84 pt at the side sideways and 82 at the top upright, and the home indicator's 34; with the
    /// status bar hidden (the stream screen on the inner display, `hidesStatusBar`), the 34 alone; the cover its
    /// camera's 84 pt strip at the right upright and at the left on its side (the duorig pose
    /// closed-side), and the 34, either way. Nil for any other size.
    static func displayInsets(_ size: CGSize, statusBarHidden: Bool = false) -> (top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat)? {
        switch (size.width, size.height) {
        case (951, 669): return statusBarHidden ? (0, 0, 34, 0) : (0, 0, 34, 84)
        case (669, 951): return statusBarHidden ? (0, 0, 34, 0) : (82, 0, 34, 0)
        case (466, 678): return (0, 0, 34, 84)
        case (678, 466): return (0, 84, 34, 0)
        default: return nil
        }
    }
}
