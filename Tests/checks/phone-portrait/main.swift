import CoreGraphics
import Foundation

// Unified StreamLayout check (iOSClient/PhonePortraitLayout.swift + iOSClient/DuoPosture.swift):
//   swiftc -O iOSClient/DuoPosture.swift iOSClient/PhonePortraitLayout.swift Tests/checks/phone-portrait/main.swift -o check
var failures = 0, checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok {
        failures += 1
        if failures <= 60 { print("FAIL (line \(line)): \(what())") }
    }
}
func sz(_ w: CGFloat, _ h: CGFloat) -> CGSize { CGSize(width: w, height: h) }
func rc(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }

func aspectMatches(_ pic: CGRect, aspect: CGFloat) -> Bool {
    guard pic.width > 0, pic.height > 0 else { return true }
    let wErr = abs(pic.width - pic.height * aspect)
    let hErr = abs(pic.height - pic.width / aspect)
    return wErr <= max(1.5, aspect + 1.0) && hErr <= max(1.5, 1.0 / aspect + 1.0)
}

func checkInvariants(_ l: StreamLayout, fold: FoldInfo, aspect: CGFloat, label: String) {
    let bounds = CGRect(origin: .zero, size: l.size)
    // Picture keeps aspect and fits inside pictureRoom and screen.
    if l.picture.width > 0 && l.picture.height > 0 {
        check(l.pictureRoom.insetBy(dx: -0.01, dy: -0.01).contains(l.picture), "\(label): picture inside pictureRoom (\(l.picture) vs \(l.pictureRoom))")
        check(bounds.insetBy(dx: -0.01, dy: -0.01).contains(l.picture), "\(label): picture inside screen")
        check(aspectMatches(l.picture, aspect: aspect), "\(label): picture aspect \(l.picture.width)/\(l.picture.height) vs \(aspect)")
    }

    // Keyboard invariants.
    if let kb = l.keyboardTop {
        check(l.bar == nil && l.rail == nil && l.appsButton == nil && l.strip == nil && l.menusButton == nil
              && l.keyboardButton == nil && l.settingsButton == nil, "\(label): bar/rail hidden while kb up")
        check(l.showsKeyboardCap, "\(label): hide-keyboard cap joins modifier row while kb up")
        if let pad = l.trackpad {
            check(pad.maxY <= kb + 0.001, "\(label): trackpad overlaps keyboard (\(pad.maxY) > \(kb))")
            let floor = l.isLandscape ? kb : (fold.horizontalBand.map { min(kb, $0.minY.rounded(.down)) } ?? kb)
            let belowFoldRoom = fold.horizontalBand.map { kb - $0.maxY.rounded(.up) } ?? 0
            let effectiveFloor = (!l.isLandscape && belowFoldRoom >= StreamLayout.belowFoldMinForKeyboard) ? belowFoldRoom : floor
            if effectiveFloor >= StreamLayout.minTrackpad + StreamLayout.capHeight {
                check(pad.height >= StreamLayout.minTrackpad - 0.001,
                      "\(label): trackpad under 75 pt (\(pad.height)) with floor \(effectiveFloor)")
            }
        } else {
            check(false, "\(label): trackpad must exist while kb up")
        }
        if let keys = l.keys {
            check(keys.maxY <= kb + 0.001, "\(label): modifier row overlaps keyboard (\(keys.maxY) > \(kb))")
            check(!l.caps.isEmpty, "\(label): caps populated")
            if let pad = l.trackpad {
                if l.isLandscape {
                    check(pad.maxY <= keys.minY + 0.001, "\(label): landscape trackpad above modifier row")
                    check(l.pictureRoom.maxY <= keys.minY + 0.001, "\(label): landscape picture above modifier row")
                } else {
                    check(pad.maxY <= keys.minY + 0.001, "\(label): portrait trackpad above modifier row")
                }
            }
        } else {
            check(false, "\(label): modifier row must exist while kb up")
        }
        if let trailing = l.keysTrailing {
            check(trailing.maxY <= kb + 0.001, "\(label): trailing modifier row overlaps keyboard")
        }
    } else {
        check(!l.showsKeyboardCap, "\(label): no hide-keyboard cap when kb down")
        if l.isLandscape {
            check(l.rail != nil && l.bar == nil && l.strip == nil && l.trackpad == nil && l.keys == nil && l.caps.isEmpty,
                  "\(label): landscape kb down has rail and direct-touch picture")
            if let rail = l.rail {
                check(rail.minX == 0 && rail.width == min(StreamLayout.railWidth, l.size.width), "\(label): leading rail width 56")
                check(l.pictureRoom.minX >= rail.maxX, "\(label): picture right of rail")
            }
        } else {
            check(l.bar != nil && l.rail == nil && l.trackpad != nil && l.keys != nil && !l.caps.isEmpty,
                  "\(label): portrait kb down has one bar, trackpad and modifier row")
            if let bar = l.bar, let pad = l.trackpad, let keys = l.keys {
                check(l.picture.maxY <= bar.minY + 0.001, "\(label): picture above bar")
                check(bar.maxY <= pad.minY + 0.001, "\(label): bar above trackpad")
                check(pad.maxY <= keys.minY + 0.001, "\(label): trackpad above modifier row")
                check(keys.maxY <= l.size.height + 0.001, "\(label): modifier row inside screen")
            }
        }
    }

    // Nothing interactive sits on a fold band.
    if let band = fold.band {
        var interactive: [(String, CGRect)] = []
        if let r = l.bar { interactive.append(("bar", r)) }
        if let r = l.rail { interactive.append(("rail", r)) }
        if let r = l.appsButton { interactive.append(("apps", r)) }
        if let r = l.strip, r.width > 0 { interactive.append(("strip", r)) }
        if let r = l.menusButton { interactive.append(("menus", r)) }
        if let r = l.keyboardButton { interactive.append(("keyboard", r)) }
        if let r = l.settingsButton { interactive.append(("settings", r)) }
        if let r = l.trackpad, !r.isEmpty { interactive.append(("trackpad", r)) }
        if let r = l.keys, !r.isEmpty { interactive.append(("keys", r)) }
        if let r = l.keysTrailing, !r.isEmpty { interactive.append(("keysTrailing", r)) }
        for (i, c) in l.caps.enumerated() where !c.isEmpty { interactive.append(("cap[\(i)]", c)) }
        if !l.drawer.isEmpty { interactive.append(("drawer", l.drawer)) }
        if !l.settings.isEmpty { interactive.append(("settings", l.settings)) }
        for (name, r) in interactive {
            check(!r.intersects(band), "\(label): \(name) \(r) intersects fold band \(band)")
        }
        // In laptop pose, picture never crosses the fold either.
        if fold.horizontalBand != nil && !l.picture.isEmpty {
            check(!l.picture.intersects(band), "\(label): picture \(l.picture) intersects horizontal fold \(band)")
        }
        // In book pose with keyboard up, picture and trackpad sit on opposite sides of the vertical fold.
        if let vBand = fold.verticalBand, l.keyboardUp {
            check(!l.pictureRoom.intersects(vBand), "\(label): book pose kb-up picture intersects fold")
            if let pad = l.trackpad {
                check(!pad.intersects(vBand), "\(label): book pose kb-up trackpad intersects fold")
                check(l.pictureRoom.maxX <= vBand.minX + 0.001 && pad.minX >= vBand.maxX - 0.001,
                      "\(label): picture on leading page, trackpad on trailing page")
            }
        }
    }

    // Trackpad span is isotropic to picture aspect.
    if let pad = l.trackpad, pad.width > 0 {
        check(abs(l.trackpadSpan - pad.width / aspect) < 0.001, "\(label): trackpadSpan \(l.trackpadSpan) != \(pad.width / aspect)")
    }
}

// MARK: - Pinned Duo and iPhone target layouts

// 1. Duo cover portrait full (466x678): target fractions ~43% picture / 8% bar / 6.5% mods / trackpad rest.
do {
    let down = StreamLayout(size: sz(466, 678), hasMenus: true)
    check(down.picture == rc(8, 8, 450, 281), "cover full kb down picture: \(down.picture)")
    check(down.bar == rc(14, 297, 438, 54), "cover full kb down bar: \(String(describing: down.bar))")
    check(down.keys == rc(14, 620, 438, 44), "cover full kb down keys: \(String(describing: down.keys))")
    check(down.trackpad == rc(14, 359, 438, 253), "cover full kb down trackpad: \(String(describing: down.trackpad))")
    check(!down.showsArrows && !down.showsKeyboardCap && down.caps.count == 6, "cover full kb down: 6 caps")
    check(down.menusButton != nil && down.strip!.width >= StreamLayout.minStripWidth, "cover full: Menus + strip fit")
    check(down.dim.count == 2 && down.dim[0].maxY == down.bar!.minY && down.dim[1].minY == down.bar!.maxY, "dim leaves bar live")
    check(down.drawer.minY == down.bar!.maxY + StreamLayout.panelGap, "drawer below bar")
    check(down.settings.minY == down.bar!.maxY + StreamLayout.panelGap, "settings below bar")
    // Keyboard up (260 pt -> top 418): picture shrinks slightly to keep trackpad >= 75.
    let up260 = StreamLayout(size: sz(466, 678), keyboardTop: 678 - 260)
    check(up260.bar == nil && up260.showsKeyboardCap && up260.caps.count == 7, "cover full kb 260: bar hidden, 7 caps")
    check(up260.picture == rc(18, 8, 430, 269), "cover full kb 260 picture shrunk aspect-fit: \(up260.picture)")
    check(up260.trackpad == rc(14, 285, 438, 75), "cover full kb 260 trackpad 75: \(String(describing: up260.trackpad))")
    check(up260.keys == rc(14, 368, 438, 44), "cover full kb 260 keys above kb: \(String(describing: up260.keys))")
    check(up260.keys!.maxY == 412 && 418 - up260.keys!.maxY == StreamLayout.keyboardGap, "6 pt above keyboard")
}

// 2. Duo cover portrait inside camera strip (382x678).
do {
    let down = StreamLayout(size: sz(382, 678), hasMenus: true)
    check(down.picture == rc(8, 8, 366, 228), "cover 382 kb down picture: \(down.picture)")
    check(down.menusButton != nil && down.strip!.width >= StreamLayout.minStripWidth, "cover 382: Menus + strip fit")
    let up300 = StreamLayout(size: sz(382, 678), keyboardTop: 678 - 300)
    check(up300.picture == rc(8, 8, 366, 228), "cover 382 kb 300: picture stays full size")
    check(up300.trackpad!.height == 76, "cover 382 kb 300: trackpad 76 >= 75")
    let up396 = StreamLayout(size: sz(382, 678), keyboardTop: 678 - 396)
    check(up396.picture == rc(85, 8, 212, 133), "cover 382 kb 396: picture shrinks cleanly: \(up396.picture)")
    check(up396.trackpad!.height == 75, "cover 382 kb 396: trackpad holds 75 pt")
}

// 3. Duo inner portrait open flat (669x951).
do {
    let flat = FoldInfo.known(nil)
    let down = StreamLayout(size: sz(669, 951), fold: flat, hasMenus: true)
    check(down.picture == rc(8, 8, 653, 408), "inner flat kb down picture: \(down.picture)")
    check(down.bar == rc(14, 424, 641, 54), "inner flat kb down bar: \(String(describing: down.bar))")
    check(down.trackpad == rc(14, 486, 641, 399), "inner flat kb down trackpad: \(String(describing: down.trackpad))")
    check(down.keys == rc(14, 893, 641, 44), "inner flat kb down keys: \(String(describing: down.keys))")
    check(down.showsArrows && !down.showsKeyboardCap && down.caps.count == 10, "inner flat kb down: 10 caps with arrows")
    check(down.drawer.width == 380 && down.settings.width == 360, "inner flat: 380 drawer, 360 settings")
    // Keyboard up (396 pt -> top 555).
    let up = StreamLayout(size: sz(669, 951), fold: flat, keyboardTop: 555)
    check(up.picture == rc(10, 8, 649, 406), "inner flat kb 396 picture: \(up.picture)")
    check(up.trackpad == rc(14, 422, 641, 75), "inner flat kb 396 trackpad 75: \(String(describing: up.trackpad))")
    check(up.keys == rc(14, 505, 641, 44), "inner flat kb 396 keys: \(String(describing: up.keys))")
    check(up.showsArrows && up.showsKeyboardCap && up.caps.count == 11, "inner flat kb up: 11 caps")
}

// 4. Duo inner portrait laptop pose (669x951, fold 455.5..495.5).
do {
    let foldBand = rc(0, 455.5, 669, 40)
    let laptop = FoldInfo.known(foldBand)
    let down = StreamLayout(size: sz(669, 951), fold: laptop, hasMenus: true)
    check(down.picture == rc(8, 8, 653, 408) && down.picture.maxY <= 455, "laptop kb down: picture above fold")
    check(down.bar!.minY == 504 && down.bar!.minY >= 496, "laptop kb down: bar below fold: \(String(describing: down.bar))")
    check(down.trackpad!.minY == 566 && down.trackpad!.height == 319, "laptop kb down: trackpad below bar")
    check(down.keys!.minY == 893, "laptop kb down: keys at bottom")

    // Laptop pose with UIKit reporting whole lower half (455.5), or read English (555), or Emoji (506):
    // all lift picture + trackpad (>= 75) + modifier row cleanly above foldTop (455).
    for kbTop: CGFloat in [455.5, 506, 555] {
        let up = StreamLayout(size: sz(669, 951), fold: laptop, keyboardTop: kbTop)
        check(up.picture == rc(90, 8, 489, 306), "laptop kb \(kbTop): picture above fold: \(up.picture)")
        check(up.trackpad == rc(14, 322, 641, 75), "laptop kb \(kbTop): trackpad 75 above fold: \(String(describing: up.trackpad))")
        check(up.keys == rc(14, 405, 641, 44), "laptop kb \(kbTop): keys above fold: \(String(describing: up.keys))")
        check(up.keys!.maxY <= 455, "laptop kb \(kbTop): all interactive above fold")
    }

    // Laptop pose with a short keyboard (kbTop = 700 -> 204 pt below fold >= 141): stays below fold!
    let shortKb = StreamLayout(size: sz(669, 951), fold: laptop, keyboardTop: 700)
    check(shortKb.picture == rc(8, 8, 653, 408), "laptop short kb: full picture above fold")
    check(shortKb.trackpad!.minY == 504 && shortKb.trackpad!.height == 138, "laptop short kb: trackpad below fold")
    check(shortKb.keys!.minY == 650 && shortKb.keys!.maxY == 694, "laptop short kb: keys above 700")
}

// 5. Landscape: slim leading rail (56 pt) kb down; 55%/45% picture + trackpad + keys kb up; Book pose splits on fold.
do {
    let flat = FoldInfo.known(nil)
    let down = StreamLayout(size: sz(951, 669), fold: flat, hasMenus: true)
    check(down.rail == rc(0, 0, 56, 669), "landscape kb down: 56 pt leading rail")
    check(down.pictureRoom == rc(64, 8, 879, 653), "landscape kb down: picture fills rest: \(down.pictureRoom)")
    check(down.appsButton != nil && down.menusButton != nil && down.keyboardButton != nil && down.settingsButton != nil, "rail has 4 buttons")
    check(down.appsButton!.maxY < down.menusButton!.minY && down.menusButton!.maxY < down.keyboardButton!.minY
          && down.keyboardButton!.maxY < down.settingsButton!.minY, "rail buttons stacked vertically")
    check(down.dim == [rc(56, 0, 895, 669)], "landscape dim leaves rail live")
    check(down.drawer.minX == 64 && down.settings.minX == 64, "landscape panels open right of rail")

    let noMenus = StreamLayout(size: sz(951, 669), fold: flat, hasMenus: false)
    check(noMenus.menusButton == nil && noMenus.appsButton!.maxY < noMenus.keyboardButton!.minY, "no menus: 3 rail buttons")

    let up = StreamLayout(size: sz(951, 669), fold: flat, keyboardTop: 669 - 300)
    check(up.rail == nil && up.bar == nil, "landscape kb up: rail hides")
    check(up.keys == rc(14, 319, 923, 44), "landscape kb up: modifier row spans above keyboard: \(String(describing: up.keys))")
    check(up.showsArrows && up.showsKeyboardCap && up.caps.count == 11, "landscape kb up: 11 caps")
    let availW: CGFloat = 951 - 8 - 14 - 8
    check(up.pictureRoom.width == (availW * 0.55).rounded(.down), "landscape kb up: pictureRoom ~55% width")
    check(up.trackpad!.minX == up.pictureRoom.maxX + 8 && up.trackpad!.maxX == 951 - 14, "landscape kb up: trackpad fills right")
    check(up.trackpad!.height == 303 && up.pictureRoom.height == 303, "landscape kb up: same height above modifier row")

    // Book pose (951x669, vertical fold 455.5..495.5) with keyboard up: splits cleanly around fold.
    let bookFold = FoldInfo.known(rc(455.5, 0, 40, 669))
    let bookDown = StreamLayout(size: sz(951, 669), fold: bookFold, hasMenus: true)
    check(bookDown.drawer.maxX <= 455 && bookDown.settings.maxX <= 455, "book kb down: panels stay on leading page")
    let bookUp = StreamLayout(size: sz(951, 669), fold: bookFold, keyboardTop: 669 - 300)
    check(bookUp.keys != nil && bookUp.keysTrailing != nil, "book kb up: modifier row splits across vertical fold")
    check(bookUp.keys!.maxX <= 455 && bookUp.keysTrailing!.minX >= 496, "book kb up: both halves clear fold")
    check(bookUp.caps.count == 11 && bookUp.caps.allSatisfy { !$0.intersects(rc(455.5, 0, 40, 669)) }, "book kb up: no cap on fold")
    check(bookUp.pictureRoom.maxX <= 455 && bookUp.trackpad!.minX >= 496, "book kb up: picture left of fold, trackpad right")
}

// 6. Helpers: viewportSize, keyboardTop, extreme short screens, edge cases.
do {
    let vpCover = StreamLayout.viewportSize(for: sz(382, 678), fold: .known(nil))
    check(vpCover == sz(366, 228), "viewportSize cover: \(vpCover)")
    let vpLandscape = StreamLayout.viewportSize(for: sz(951, 669), fold: .known(nil))
    check(vpLandscape == sz(879, 653), "viewportSize landscape: \(vpLandscape)")
    let vpLaptop = StreamLayout.viewportSize(for: sz(669, 951), fold: .known(rc(0, 455.5, 669, 40)))
    check(vpLaptop == sz(653, 439), "viewportSize laptop: \(vpLaptop)")

    // keyboardTop helper.
    let laptopFold = FoldInfo.known(rc(0, 455.5, 669, 40))
    check(StreamLayout.keyboardTop(reported: nil, read: nil, size: sz(669, 951), origin: .zero, fold: laptopFold) == nil, "kb down -> nil")
    check(StreamLayout.keyboardTop(reported: rc(0, 951, 669, 0), read: nil, size: sz(669, 951), origin: .zero, fold: laptopFold) == nil, "kb at bottom -> nil")
    check(StreamLayout.keyboardTop(reported: rc(0, 640, 669, 311), read: nil, size: sz(669, 951), origin: .zero, fold: .known(nil)) == 640, "flat -> reported")
    check(StreamLayout.keyboardTop(reported: rc(0, 455.5, 669, 495.5), read: rc(0, 555, 669, 396), size: sz(669, 951), origin: .zero, fold: laptopFold) == 555, "laptop read -> 555")
    check(StreamLayout.keyboardTop(reported: rc(0, 455.5, 669, 495.5), read: nil, size: sz(669, 951), origin: .zero, fold: laptopFold) == 455.5, "laptop settling -> reported fold top 455.5")
    check(StreamLayout.keyboardTop(reported: rc(0, 600, 393, 300), read: nil, size: sz(393, 793), origin: CGPoint(x: 0, y: 59), fold: .inferred) == 541, "origin offset subtracted")

    // Extreme short floor in portrait (130 pt: picture drops to 0, trackpad holds 75 pt, keys 44 pt) and landscape (130 pt).
    let extremeP = StreamLayout(size: sz(375, 667), keyboardTop: 130)
    check(extremeP.picture.isEmpty && extremeP.trackpad!.height == 75 && extremeP.keys!.height == 44 && extremeP.keys!.maxY <= 130,
          "extreme portrait floor 130: trackpad 75, keys 44")
    let tinyP = StreamLayout(size: sz(375, 667), keyboardTop: 100)
    check(tinyP.picture.isEmpty && tinyP.keys!.maxY <= 100 && tinyP.trackpad!.maxY <= tinyP.keys!.minY, "tiny portrait floor 100: no overlap")
    let extremeL = StreamLayout(size: sz(667, 375), keyboardTop: 130)
    check(extremeL.trackpad!.height == 75 && extremeL.keys!.height == 44 && extremeL.keys!.maxY <= 130,
          "extreme landscape floor 130: trackpad 75, keys 44")

    // Narrow portrait where Menus would crowd strip below minStripWidth.
    let veryNarrow = StreamLayout(size: sz(240, 500), hasMenus: true)
    check(veryNarrow.menusButton == nil && veryNarrow.strip!.width >= 0, "very narrow bar omits Menus to preserve strip")
    // Zero size / invalid aspect / kbTop >= H.
    let zero = StreamLayout(size: .zero, keyboardTop: 100, aspect: -2)
    check(zero.keyboardTop == nil && zero.picture.size == .zero, "zero size guarded")
    check(StreamLayout.split(rc(0, 0, 100, 44), count: 0, gap: 6).isEmpty, "split count 0")
    let sp = StreamLayout.split(rc(14, 0, 438, 44), count: 6, gap: 6)
    check(sp.count == 6 && sp.first!.minX == 14 && abs(sp.last!.maxX - 452) < 0.001, "split fills row exactly")
}

// MARK: - Broad sweep across devices, orientations, folds, keyboard heights, and aspects

let scenarios: [(String, CGSize, FoldInfo)] = [
    ("SE zoomed portrait", sz(320, 568), .inferred),
    ("SE zoomed landscape", sz(568, 320), .inferred),
    ("SE portrait", sz(375, 667), .inferred),
    ("SE landscape", sz(667, 375), .inferred),
    ("13 mini portrait", sz(375, 812), .inferred),
    ("13 mini landscape", sz(812, 375), .inferred),
    ("15 Pro portrait", sz(393, 852), .inferred),
    ("15 Pro landscape", sz(852, 393), .inferred),
    ("18 Pro portrait", sz(402, 812), .inferred),
    ("18 Pro landscape", sz(812, 402), .inferred),
    ("18 Pro Max portrait", sz(440, 894), .inferred),
    ("18 Pro Max landscape", sz(894, 440), .inferred),
    ("Duo cover upright (382)", sz(382, 678), .known(nil)),
    ("Duo cover upright (466)", sz(466, 678), .known(nil)),
    ("Duo cover sideways (594)", sz(594, 466), .known(nil)),
    ("Duo cover sideways (678)", sz(678, 466), .known(nil)),
    ("Duo inner flat portrait", sz(669, 951), .known(nil)),
    ("Duo inner laptop pose", sz(669, 951), .known(rc(0, 455.5, 669, 40))),
    ("Duo inner flat landscape", sz(951, 669), .known(nil)),
    ("Duo inner book pose", sz(951, 669), .known(rc(455.5, 0, 40, 669))),
    ("iPad mini portrait", sz(744, 1133), .inferred),
    ("iPad mini landscape", sz(1133, 744), .inferred),
    ("iPad Pro 13 portrait", sz(1032, 1376), .inferred),
    ("iPad Pro 13 landscape", sz(1376, 1032), .inferred),
]

let kbHeights: [CGFloat] = [0, 216, 260, 300, 396]
let aspects: [CGFloat] = [1.6, 16.0 / 9.0, 4.0 / 3.0, 0.8, 2.4]

for (name, size, fold) in scenarios {
    var kbTops: [CGFloat?] = [nil]
    for kh in kbHeights where kh > 0 && kh < size.height {
        kbTops.append(size.height - kh)
    }
    if fold.horizontalBand != nil {
        kbTops.append(455.5)   // laptop-pose whole lower half
        kbTops.append(506)     // laptop-pose emoji glass
        kbTops.append(700)     // short keyboard below fold
    }
    for kbTop in kbTops {
        for aspect in aspects {
            for hasMenus in [false, true] {
                let l = StreamLayout(size: size, fold: fold, keyboardTop: kbTop, aspect: aspect, hasMenus: hasMenus)
                checkInvariants(l, fold: fold, aspect: aspect, label: "\(name) kb=\(String(describing: kbTop)) a=\(String(format: "%.2f", aspect)) m=\(hasMenus)")
            }
        }
    }
}

print("phone-portrait: \(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
