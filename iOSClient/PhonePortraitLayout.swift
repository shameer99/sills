import CoreGraphics

/// One unified pure layout for the stream screen in every orientation and on every device (iPhone,
/// iPhone Duo cover and inner displays open flat or half-folded, iPad). Pure (CoreGraphics + `FoldInfo`),
/// so `Tests/checks/phone-portrait` compiles it with swiftc and verifies every invariant across all
/// screen sizes, folds and keyboard heights.
///
/// One rule, every orientation: the software keyboard is part of the layout; nothing interactive ever
/// sits under the keyboard or on a fold band.
///
/// Portrait (`size.height >= size.width`):
/// - Top to bottom: picture (aspect-fit), one bar (Apps | scrolling window thumbnails | Menus | Keyboard |
///   Settings; hidden while the keyboard is up), trackpad (takes the slack, minimum 75 pt), modifier row
///   (esc, tab, ctrl, opt, cmd, shift, plus arrows where width allows and a hide-keyboard cap while the
///   keyboard is up), then the keyboard's top edge (or bottom margin).
/// - The picture shrinks (letterboxed, aspect-fit) before the trackpad drops under 75 pt.
/// - In the Duo's laptop pose (a horizontal fold across the screen): keyboard down puts the picture above
///   the fold and the bar, trackpad and modifier row below it; keyboard up keeps them below the fold if
///   the trackpad (75 pt) and modifier row fit there, otherwise lifts picture, trackpad and modifier row
///   above the fold (including when UIKit reports the keyboard as the whole lower half).
///
/// Landscape (`size.width > size.height`):
/// - Keyboard down: a slim 56 pt leading vertical rail (Apps, Menus, Keyboard, Settings stacked), and the
///   picture fills the rest with direct touch.
/// - Keyboard up: the rail hides; above the modifier row and keyboard, the picture aspect-fits on the left
///   (~55% of width) and the trackpad fills the width to its right (never under 75 pt while room allows);
///   the modifier row spans above the keyboard with a hide-keyboard cap. In the Duo's book pose (a vertical
///   fold), the picture takes the leading page, the trackpad takes the trailing page, and the modifier row
///   splits cleanly across the fold band so no cap sits on the fold.
struct StreamLayout: Equatable {
    static let defaultAspect: CGFloat = 1.6
    static let margin: CGFloat = 8
    static let side: CGFloat = 14
    static let bottom: CGFloat = 14
    static let keyboardGap: CGFloat = 6
    static let rowGap: CGFloat = 8
    static let barHeight: CGFloat = 54
    static let barButtonHeight: CGFloat = 50
    static let railWidth: CGFloat = 56
    static let railButtonSize: CGFloat = 46
    static let railGap: CGFloat = 8
    static let railTop: CGFloat = 12
    static let capHeight: CGFloat = 44
    static let keyGap: CGFloat = 6
    static let minTrackpad: CGFloat = 75
    static let landscapePictureShare: CGFloat = 0.55
    static let panelGap: CGFloat = 8
    /// Eleven 44 pt caps with ten 6 pt gaps: esc, tab, ctrl, opt, cmd, shift, 4 arrows, keyboard.
    static let wideKeysMinWidth: CGFloat = 544
    static let minStripWidth: CGFloat = 64
    static let baseCapCount = 6
    static let arrowCapCount = 4

    let size: CGSize
    let isLandscape: Bool
    /// Normalized keyboard top edge in this screen's space; nil while the keyboard is down.
    let keyboardTop: CGFloat?
    /// The room allocated for the picture pane.
    let pictureRoom: CGRect
    /// The aspect-fit picture rect inside `pictureRoom`.
    let picture: CGRect
    /// Portrait one-bar (hidden while the keyboard is up, and nil in landscape).
    let bar: CGRect?
    /// Landscape leading vertical rail (hidden while the keyboard is up, and nil in portrait).
    let rail: CGRect?
    /// Individual controls inside `bar` or `rail` (nil while the keyboard is up).
    let appsButton: CGRect?
    let strip: CGRect?
    let menusButton: CGRect?
    let keyboardButton: CGRect?
    let settingsButton: CGRect?
    /// Trackpad surface (always present in portrait; present in landscape while the keyboard is up).
    let trackpad: CGRect?
    /// Vertical pointer span matching the picture's aspect so pointer travel is isotropic.
    let trackpadSpan: CGFloat
    /// Modifier row (leading half when split across a vertical fold in the book pose).
    let keys: CGRect?
    /// Trailing half of the modifier row in the book pose with the keyboard up; nil elsewhere.
    let keysTrailing: CGRect?
    let showsArrows: Bool
    let showsKeyboardCap: Bool
    /// Every individual cap rect in `keys` (and `keysTrailing` if split).
    let caps: [CGRect]
    /// Apps drawer and Settings panel rects (kept clear of fold bands and the keyboard).
    let drawer: CGRect
    let settings: CGRect
    /// Transition anchor for the Settings panel as fractions of `size`.
    let settingsAnchor: CGPoint
    /// Regions covered by the drawer's dim / Settings tap catcher (leaving the active bar or rail live).
    let dim: [CGRect]

    var keyboardUp: Bool { keyboardTop != nil }

    /// Portrait fixed height (everything except picture and trackpad) when the keyboard is down: 144 pt.
    static var portraitFixedDown: CGFloat {
        margin + rowGap + barHeight + rowGap + rowGap + capHeight + bottom
    }

    /// Portrait fixed height above the keyboard (everything except picture and trackpad) when up: 74 pt.
    static var portraitFixedUp: CGFloat {
        margin + rowGap + rowGap + capHeight + keyboardGap
    }

    /// Room required below a horizontal fold to hold the trackpad (min 75 pt) and modifier row above the keyboard: 141 pt.
    static var belowFoldMinForKeyboard: CGFloat {
        rowGap + minTrackpad + rowGap + capHeight + keyboardGap
    }

    init(size: CGSize, fold: FoldInfo = .inferred, keyboardTop: CGFloat? = nil,
         aspect: CGFloat = StreamLayout.defaultAspect, hasMenus: Bool = false) {
        let W = max(0, size.width), H = max(0, size.height)
        self.size = CGSize(width: W, height: H)
        let landscape = W > H
        self.isLandscape = landscape
        let a = (aspect.isFinite && aspect > 0) ? aspect : Self.defaultAspect
        let kb: CGFloat? = keyboardTop.flatMap { ($0.isFinite && $0 < H) ? max(0, $0) : nil }
        self.keyboardTop = kb

        if landscape {
            // MARK: Landscape
            self.bar = nil
            self.strip = nil
            if let kb {
                // Keyboard up: rail hides; picture on the left (~55%) and trackpad on the right above the modifier row.
                self.rail = nil
                self.appsButton = nil
                self.menusButton = nil
                self.keyboardButton = nil
                self.settingsButton = nil

                let (topM, rGap, kbG) = Self.landscapeKeyboardGaps(floor: kb)
                let keysH = min(Self.capHeight, max(0, kb - kbG))
                let keysY = max(0, kb - kbG - keysH)
                let areaH = max(0, keysY - rGap - topM)

                let vBand = fold.verticalBand
                let splitFold: (left: CGFloat, right: CGFloat)? = vBand.flatMap { band in
                    let l = max(0, band.minX.rounded(.down))
                    let r = min(W, band.maxX.rounded(.up))
                    guard l - Self.side - Self.rowGap >= 44, W - Self.side - (r + Self.rowGap) >= 44 else { return nil }
                    return (l, r)
                }

                if let split = splitFold {
                    let leadKeys = CGRect(x: Self.side, y: keysY, width: max(0, split.left - Self.side - Self.rowGap), height: keysH)
                    let trailKeys = CGRect(x: split.right + Self.rowGap, y: keysY,
                                           width: max(0, W - Self.side - (split.right + Self.rowGap)), height: keysH)
                    self.keys = leadKeys
                    self.keysTrailing = trailKeys
                    self.showsArrows = true
                    self.showsKeyboardCap = true
                    self.caps = Self.split(leadKeys, count: Self.baseCapCount, gap: Self.keyGap)
                        + Self.split(trailKeys, count: Self.arrowCapCount + 1, gap: Self.keyGap)

                    let room = CGRect(x: Self.margin, y: topM, width: max(0, split.left - 2 * Self.margin), height: areaH)
                    self.pictureRoom = room
                    self.picture = Self.aspectFit(a, in: room, centerVertically: true)
                    let pad = CGRect(x: split.right + Self.rowGap, y: topM,
                                     width: max(0, W - Self.side - (split.right + Self.rowGap)), height: areaH)
                    self.trackpad = pad
                    self.trackpadSpan = pad.width / a

                    let panelH = max(0, keysY - Self.panelGap - Self.margin)
                    self.drawer = CGRect(x: Self.margin, y: Self.margin, width: min(380, room.width), height: panelH)
                    self.settings = CGRect(x: Self.margin, y: Self.margin, width: min(360, room.width), height: panelH)
                } else {
                    let keysRect = CGRect(x: Self.side, y: keysY, width: max(0, W - 2 * Self.side), height: keysH)
                    self.keys = keysRect
                    self.keysTrailing = nil
                    let arrows = keysRect.width >= Self.wideKeysMinWidth
                    self.showsArrows = arrows
                    self.showsKeyboardCap = true
                    let count = Self.baseCapCount + (arrows ? Self.arrowCapCount : 0) + 1
                    self.caps = Self.split(keysRect, count: count, gap: Self.keyGap)

                    let availW = max(0, W - Self.margin - Self.side - Self.rowGap)
                    let picRoomW = (availW * Self.landscapePictureShare).rounded(.down)
                    let room = CGRect(x: Self.margin, y: topM, width: picRoomW, height: areaH)
                    self.pictureRoom = room
                    self.picture = Self.aspectFit(a, in: room, centerVertically: true)
                    let padX = room.maxX + Self.rowGap
                    let pad = CGRect(x: padX, y: topM, width: max(0, W - Self.side - padX), height: areaH)
                    self.trackpad = pad
                    self.trackpadSpan = pad.width / a

                    let panelH = max(0, keysY - Self.panelGap - Self.margin)
                    self.drawer = CGRect(x: Self.side, y: Self.margin, width: min(380, max(0, W - 2 * Self.side)), height: panelH)
                    self.settings = CGRect(x: max(Self.side, W - Self.side - min(360, max(0, W - 2 * Self.side))),
                                           y: Self.margin, width: min(360, max(0, W - 2 * Self.side)), height: panelH)
                }
                self.settingsAnchor = CGPoint(x: W > 0 ? self.settings.minX / W : 0, y: H > 0 ? self.settings.minY / H : 0)
                self.dim = [CGRect(origin: .zero, size: CGSize(width: W, height: H))]
            } else {
                // Keyboard down: slim leading vertical rail + full picture with direct touch.
                let railRect = CGRect(x: 0, y: 0, width: min(Self.railWidth, W), height: H)
                self.rail = railRect
                let buttons = Self.railButtons(in: railRect, hasMenus: hasMenus)
                self.appsButton = buttons.apps
                self.menusButton = buttons.menus
                self.keyboardButton = buttons.keyboard
                self.settingsButton = buttons.settings

                let room = CGRect(x: railRect.maxX + Self.margin, y: Self.margin,
                                  width: max(0, W - railRect.maxX - 2 * Self.margin),
                                  height: max(0, H - 2 * Self.margin))
                self.pictureRoom = room
                self.picture = Self.aspectFit(a, in: room, centerVertically: true)
                self.trackpad = nil
                self.trackpadSpan = 0
                self.keys = nil
                self.keysTrailing = nil
                self.showsArrows = false
                self.showsKeyboardCap = false
                self.caps = []

                let panelX = railRect.maxX + Self.panelGap
                let maxLeading = fold.verticalBand.map { max(0, $0.minX.rounded(.down) - Self.panelGap - panelX) }
                    ?? max(0, W - Self.margin - panelX)
                let panelH = max(0, H - 2 * Self.margin)
                self.drawer = CGRect(x: panelX, y: Self.margin, width: min(380, maxLeading), height: panelH)
                self.settings = CGRect(x: panelX, y: Self.margin, width: min(360, maxLeading), height: panelH)
                self.settingsAnchor = CGPoint(x: W > 0 ? panelX / W : 0,
                                              y: H > 0 ? (buttons.settings.midY) / H : 0)
                self.dim = [CGRect(x: railRect.maxX, y: 0, width: max(0, W - railRect.maxX), height: H)]
            }
            return
        }

        // MARK: Portrait
        self.rail = nil
        self.keysTrailing = nil
        let rowWidth = max(0, W - 2 * Self.side)
        let pictureMaxWidth = max(0, W - 2 * Self.margin)
        let hBand = fold.horizontalBand
        let foldBounds: (top: CGFloat, bottom: CGFloat)? = hBand.map {
            let t = max(0, $0.minY.rounded(.down))
            let b = min(H, $0.maxY.rounded(.up))
            return (t, max(t, b))
        }

        if let kb {
            // Keyboard up: bar hides; hide-keyboard cap joins the modifier row.
            self.bar = nil
            self.appsButton = nil
            self.strip = nil
            self.menusButton = nil
            self.keyboardButton = nil
            self.settingsButton = nil

            let arrows = rowWidth >= Self.wideKeysMinWidth
            self.showsArrows = arrows
            self.showsKeyboardCap = true
            let capCount = Self.baseCapCount + (arrows ? Self.arrowCapCount : 0) + 1

            if let f = foldBounds, kb - f.bottom >= Self.belowFoldMinForKeyboard {
                // Laptop pose with a short keyboard: picture above the fold, trackpad + modifier row below it.
                let room = CGRect(x: Self.margin, y: Self.margin, width: pictureMaxWidth,
                                  height: max(0, f.top - 2 * Self.margin))
                self.pictureRoom = room
                self.picture = Self.aspectFit(a, in: room, centerVertically: false)
                let keysRect = CGRect(x: Self.side, y: kb - Self.keyboardGap - Self.capHeight,
                                      width: rowWidth, height: Self.capHeight)
                let padTop = f.bottom + Self.rowGap
                let pad = CGRect(x: Self.side, y: padTop, width: rowWidth,
                                 height: max(0, keysRect.minY - Self.rowGap - padTop))
                self.keys = keysRect
                self.caps = Self.split(keysRect, count: capCount, gap: Self.keyGap)
                self.trackpad = pad
                self.trackpadSpan = pad.width / a
            } else {
                // Continuous portrait (or laptop pose lifted above the fold when lower half cannot hold trackpad + keys).
                let floor = foldBounds.map { min(kb, $0.top) } ?? kb
                if floor >= Self.portraitFixedUp + Self.minTrackpad {
                    let maxPicH = floor - Self.portraitFixedUp - Self.minTrackpad
                    let maxRoom = CGRect(x: Self.margin, y: Self.margin, width: pictureMaxWidth, height: maxPicH)
                    let pic = Self.aspectFit(a, in: maxRoom, centerVertically: false)
                    self.pictureRoom = CGRect(x: Self.margin, y: Self.margin, width: pictureMaxWidth, height: pic.height)
                    self.picture = pic
                    let keysRect = CGRect(x: Self.side, y: floor - Self.keyboardGap - Self.capHeight,
                                          width: rowWidth, height: Self.capHeight)
                    let padTop = pic.maxY + Self.rowGap
                    let pad = CGRect(x: Self.side, y: padTop, width: rowWidth,
                                     height: max(0, keysRect.minY - Self.rowGap - padTop))
                    self.keys = keysRect
                    self.caps = Self.split(keysRect, count: capCount, gap: Self.keyGap)
                    self.trackpad = pad
                    self.trackpadSpan = pad.width / a
                } else {
                    // Extreme short floor: picture drops to zero, shrink gaps before trackpad goes under 75 pt.
                    self.pictureRoom = CGRect(x: Self.margin, y: Self.margin, width: pictureMaxWidth, height: 0)
                    self.picture = CGRect(x: Self.margin, y: Self.margin, width: 0, height: 0)
                    if floor >= Self.minTrackpad + Self.capHeight {
                        let slack = floor - Self.minTrackpad - Self.capHeight
                        let kbG = min(Self.keyboardGap, (slack / 2).rounded(.down))
                        let rGap = min(Self.rowGap, slack - kbG)
                        let keysRect = CGRect(x: Self.side, y: floor - kbG - Self.capHeight,
                                              width: rowWidth, height: Self.capHeight)
                        let padTop = max(0, keysRect.minY - rGap - Self.minTrackpad)
                        let pad = CGRect(x: Self.side, y: padTop, width: rowWidth, height: Self.minTrackpad)
                        self.keys = keysRect
                        self.caps = Self.split(keysRect, count: capCount, gap: Self.keyGap)
                        self.trackpad = pad
                        self.trackpadSpan = pad.width / a
                    } else {
                        let keysH = min(Self.capHeight, floor)
                        let keysRect = CGRect(x: Self.side, y: max(0, floor - keysH), width: rowWidth, height: keysH)
                        let pad = CGRect(x: Self.side, y: 0, width: rowWidth, height: max(0, keysRect.minY))
                        self.keys = keysRect
                        self.caps = Self.split(keysRect, count: capCount, gap: Self.keyGap)
                        self.trackpad = pad
                        self.trackpadSpan = pad.width / a
                    }
                }
            }

            let floor = foldBounds.map { min(kb, $0.top) } ?? kb
            let panelTop = Self.margin
            let panelBottom = max(panelTop, min(self.keys?.minY ?? floor, floor) - Self.panelGap)
            let drawerW = min(380, rowWidth)
            let settingsW = min(360, rowWidth)
            self.drawer = CGRect(x: Self.side, y: panelTop, width: drawerW, height: panelBottom - panelTop)
            self.settings = CGRect(x: Self.side + rowWidth - settingsW, y: panelTop, width: settingsW, height: panelBottom - panelTop)
            self.settingsAnchor = CGPoint(x: W > 0 ? self.settings.maxX / W : 1, y: H > 0 ? self.settings.minY / H : 0)
            self.dim = [CGRect(origin: .zero, size: CGSize(width: W, height: H))]
            return
        }

        // Portrait, keyboard down: picture, one bar, trackpad, modifier row.
        let arrows = rowWidth >= Self.wideKeysMinWidth
        self.showsArrows = arrows
        self.showsKeyboardCap = false
        let capCount = Self.baseCapCount + (arrows ? Self.arrowCapCount : 0)

        let barRect: CGRect
        let keysRect: CGRect
        let padRect: CGRect

        if let f = foldBounds {
            // Laptop pose, keyboard down: picture above the fold; bar, trackpad and modifier row below it.
            let room = CGRect(x: Self.margin, y: Self.margin, width: pictureMaxWidth,
                              height: max(0, f.top - 2 * Self.margin))
            self.pictureRoom = room
            self.picture = Self.aspectFit(a, in: room, centerVertically: false)
            barRect = CGRect(x: Self.side, y: f.bottom + Self.rowGap, width: rowWidth, height: Self.barHeight)
            keysRect = CGRect(x: Self.side, y: max(barRect.maxY + Self.rowGap, H - Self.bottom - Self.capHeight),
                              width: rowWidth, height: Self.capHeight)
            let padTop = barRect.maxY + Self.rowGap
            padRect = CGRect(x: Self.side, y: padTop, width: rowWidth,
                             height: max(0, keysRect.minY - Self.rowGap - padTop))
        } else {
            let maxPicH = max(0, H - Self.portraitFixedDown - Self.minTrackpad)
            let maxRoom = CGRect(x: Self.margin, y: Self.margin, width: pictureMaxWidth, height: maxPicH)
            let pic = Self.aspectFit(a, in: maxRoom, centerVertically: false)
            self.pictureRoom = CGRect(x: Self.margin, y: Self.margin, width: pictureMaxWidth, height: pic.height)
            self.picture = pic
            barRect = CGRect(x: Self.side, y: pic.maxY + Self.rowGap, width: rowWidth, height: Self.barHeight)
            keysRect = CGRect(x: Self.side, y: max(barRect.maxY + Self.rowGap, H - Self.bottom - Self.capHeight),
                              width: rowWidth, height: Self.capHeight)
            let padTop = barRect.maxY + Self.rowGap
            padRect = CGRect(x: Self.side, y: padTop, width: rowWidth,
                             height: max(0, keysRect.minY - Self.rowGap - padTop))
        }

        self.bar = barRect
        let barParts = Self.portraitBarParts(in: barRect, hasMenus: hasMenus)
        self.appsButton = barParts.apps
        self.strip = barParts.strip
        self.menusButton = barParts.menus
        self.keyboardButton = barParts.keyboard
        self.settingsButton = barParts.settings

        self.keys = keysRect
        self.caps = Self.split(keysRect, count: capCount, gap: Self.keyGap)
        self.trackpad = padRect
        self.trackpadSpan = padRect.width / a

        let panelTop = barRect.maxY + Self.panelGap
        let panelH = max(0, H - Self.bottom - panelTop)
        let drawerW = rowWidth >= 520 ? min(380, rowWidth) : rowWidth
        let settingsW = rowWidth >= 520 ? min(360, rowWidth) : rowWidth
        self.drawer = CGRect(x: Self.side, y: panelTop, width: drawerW, height: panelH)
        self.settings = CGRect(x: Self.side + rowWidth - settingsW, y: panelTop, width: settingsW, height: panelH)
        self.settingsAnchor = CGPoint(x: W > 0 ? self.settings.maxX / W : 1, y: H > 0 ? self.settings.minY / H : 0)
        self.dim = [CGRect(x: 0, y: 0, width: W, height: barRect.minY),
                    CGRect(x: 0, y: barRect.maxY, width: W, height: max(0, H - barRect.maxY))]
    }

    /// The stable viewport size to send the Mac (keyboard-down picture pane, so showing or hiding the
    /// software keyboard never resizes the Mac window or restarts the stream).
    static func viewportSize(for size: CGSize, fold: FoldInfo) -> CGSize {
        let base = StreamLayout(size: size, fold: fold, keyboardTop: nil, aspect: defaultAspect)
        if base.isLandscape || fold.horizontalBand != nil {
            return base.pictureRoom.size
        }
        return base.picture.size
    }

    /// Resolves the screen-local keyboard top edge from `KeyboardFrameMonitor` and `DuoPosture.keyboardGlass`.
    /// Nil while the keyboard is down. In the Duo's laptop pose, falls back to the reported fold-top edge
    /// while a reload reading settles, so picture, trackpad and modifier row sit cleanly above the fold
    /// immediately without flashing.
    static func keyboardTop(reported: CGRect?, read: CGRect?, size: CGSize, origin: CGPoint, fold: FoldInfo) -> CGFloat? {
        guard let reported else { return nil }
        let localReported = reported.minY - origin.y
        guard localReported < size.height else { return nil }
        let laptop = fold.horizontalBand != nil && size.height >= size.width
        let controlsTop = fold.horizontalBand.map { min(size.height, $0.maxY.rounded(.up)) } ?? 0
        let localRead = read.map { $0.offsetBy(dx: -origin.x, dy: -origin.y) }
        guard let glass = DuoPosture.keyboardGlass(reported: localReported, read: localRead, size: size,
                                                   controlsTop: controlsTop, laptop: laptop) else { return nil }
        return glass.top ?? localReported
    }

    /// Aspect-fit rectangle of shape `aspect` (width / height) inside `room`, in whole points.
    static func aspectFit(_ aspect: CGFloat, in room: CGRect, centerVertically: Bool = false) -> CGRect {
        guard room.width > 0, room.height > 0 else { return CGRect(origin: room.origin, size: .zero) }
        let a = (aspect.isFinite && aspect > 0) ? aspect : defaultAspect
        let tall = (room.width / a).rounded(.down)
        if tall <= room.height {
            let h = max(1, min(room.height, tall))
            let y = centerVertically ? room.minY + ((room.height - h) / 2).rounded(.down) : room.minY
            return CGRect(x: room.minX, y: y, width: room.width, height: h)
        }
        let w = min(room.width, max(1, (room.height * a).rounded(.down)))
        let x = room.minX + ((room.width - w) / 2).rounded(.down)
        return CGRect(x: x, y: room.minY, width: w, height: room.height)
    }

    /// Portrait bar parts: Apps | scrolling window thumbnails | [Menus] | Keyboard | Settings.
    private static func portraitBarParts(in bar: CGRect, hasMenus: Bool)
    -> (apps: CGRect, strip: CGRect, menus: CGRect?, keyboard: CGRect, settings: CGRect) {
        let btnW: CGFloat = bar.width >= 520 ? 56 : (bar.width >= 320 ? 48 : 44)
        let gap: CGFloat = bar.width >= 520 ? 8 : 6
        let btnH = min(barButtonHeight, bar.height)
        let btnY = bar.minY + ((bar.height - btnH) / 2).rounded(.down)

        let apps = CGRect(x: bar.minX, y: btnY, width: btnW, height: btnH)
        let settings = CGRect(x: max(bar.minX, bar.maxX - btnW), y: btnY, width: btnW, height: btnH)
        let keyboard = CGRect(x: max(bar.minX, settings.minX - gap - btnW), y: btnY, width: btnW, height: btnH)

        let menusCandidate = CGRect(x: keyboard.minX - gap - btnW, y: btnY, width: btnW, height: btnH)
        let stripStart = apps.maxX + gap
        let menus: CGRect? = hasMenus && (menusCandidate.minX - gap - stripStart >= minStripWidth) ? menusCandidate : nil
        let stripEnd = (menus ?? keyboard).minX - gap
        let strip = CGRect(x: stripStart, y: bar.minY, width: max(0, stripEnd - stripStart), height: bar.height)
        return (apps, strip, menus, keyboard, settings)
    }

    /// Landscape leading rail buttons: Apps, [Menus], Keyboard, Settings stacked vertically.
    private static func railButtons(in rail: CGRect, hasMenus: Bool)
    -> (apps: CGRect, menus: CGRect?, keyboard: CGRect, settings: CGRect) {
        let count = hasMenus ? 4 : 3
        let maxBtnW = min(railButtonSize, max(0, rail.width - 8))
        let availH = max(0, rail.height - 2 * railTop)
        let gap = min(railGap, availH > CGFloat(count) * maxBtnW ? railGap : 4)
        let btnSize = min(maxBtnW, max(0, ((availH - CGFloat(count - 1) * gap) / CGFloat(count)).rounded(.down)))
        let x = rail.minX + ((rail.width - btnSize) / 2).rounded(.down)
        var y = rail.minY + railTop
        func next() -> CGRect {
            let r = CGRect(x: x, y: y, width: btnSize, height: btnSize)
            y += btnSize + gap
            return r
        }
        let apps = next()
        let menus = hasMenus ? next() : nil
        let keyboard = next()
        let settings = next()
        return (apps, menus, keyboard, settings)
    }

    /// Adaptive vertical margins in landscape with keyboard up so trackpad stays >= 75 pt whenever
    /// `floor >= minTrackpad + capHeight`.
    private static func landscapeKeyboardGaps(floor: CGFloat) -> (top: CGFloat, rowGap: CGFloat, keyboardGap: CGFloat) {
        if floor >= margin + minTrackpad + rowGap + capHeight + keyboardGap {
            return (margin, rowGap, keyboardGap)
        }
        guard floor >= minTrackpad + capHeight else { return (0, 0, 0) }
        let slack = floor - minTrackpad - capHeight
        let kbG = min(keyboardGap, (slack / 3).rounded(.down))
        let rGap = min(rowGap, ((slack - kbG) / 2).rounded(.down))
        let topM = min(margin, slack - kbG - rGap)
        return (topM, rGap, kbG)
    }

    /// `count` equal parts of `row`, `gap` apart, filling it.
    static func split(_ row: CGRect, count: Int, gap: CGFloat) -> [CGRect] {
        guard count > 0 else { return [] }
        let each = max(0, (row.width - CGFloat(count - 1) * gap) / CGFloat(count))
        return (0..<count).map { i in
            CGRect(x: row.minX + CGFloat(i) * (each + gap), y: row.minY, width: each, height: row.height)
        }
    }
}
