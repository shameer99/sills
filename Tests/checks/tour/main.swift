import Foundation
import CoreGraphics

// TourPolicy (iOSClient/TourPolicy.swift) on its own, using StreamLayout (PhonePortraitLayout.swift)
// and DuoPosture (DuoPosture.swift):
//   swiftc -O iOSClient/TourPolicy.swift iOSClient/PhonePortraitLayout.swift iOSClient/DuoPosture.swift Tests/checks/tour/main.swift -o check
var failures = 0, checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok {
        failures += 1
        if failures <= 60 { print("FAIL (line \(line)): \(what())") }
    }
}

let L = TourLayout.landscape, P = TourLayout.portrait, F = TourLayout.phone
let all: [TourTopic] = [.touch, .bar, .sharing, .settings, .laptop]
let sidewaysSteps: [TourTopic] = [.touch, .bar, .sharing, .settings]

// MARK: - Steps and targets

check(TourTopic.allCases == all, "the tour's order")
check(TourTopic.touch < .bar && TourTopic.bar < .sharing && TourTopic.sharing < .settings && TourTopic.settings < .laptop
      && !(TourTopic.laptop < .touch) && !(TourTopic.settings < .sharing), "Comparable follows the order")
check(TourTopic.sharing.rawValue == "sharing", "the new card's saved name")
check(TourPolicy.steps(L, voiceOver: false) == sidewaysSteps, "landscape: four cards")
check(TourPolicy.steps(P, voiceOver: false) == all && TourPolicy.steps(F, voiceOver: false) == all, "upright: five cards")
check(TourPolicy.steps(L, voiceOver: true) == [.bar, .sharing, .settings], "landscape under VoiceOver: no touch")
check(TourPolicy.steps(P, voiceOver: true) == [.bar, .sharing, .settings, .laptop]
      && TourPolicy.steps(F, voiceOver: true) == [.bar, .sharing, .settings, .laptop], "upright under VoiceOver: no touch, laptop kept")
check(TourPolicy.only(P) == [.laptop] && TourPolicy.only(F) == [.laptop] && TourPolicy.only(L) == [], "only(): laptop is upright's alone")
check(P.upright && F.upright && !L.upright, "upright")
check(TourPolicy.targets(.touch, L) == [.stream] && TourPolicy.targets(.touch, P) == [.stream] && TourPolicy.targets(.touch, F) == [.stream], "touch lights stream")
check(TourPolicy.targets(.bar, L) == [.apps, .menus, .keyboard], "landscape rail: Apps, Menus, Keyboard")
check(TourPolicy.targets(.bar, P) == [.strip, .menus, .keyboard] && TourPolicy.targets(.bar, F) == [.strip, .menus, .keyboard],
      "upright one-bar: strip, Menus, Keyboard")
check([L, P, F].allSatisfy { TourPolicy.targets(.sharing, $0) == [.settings] && TourPolicy.targets(.settings, $0) == [.settings] },
      "sharing and settings light Settings")
check(TourPolicy.targets(.laptop, P) == [.keys, .trackpad] && TourPolicy.targets(.laptop, F) == [.keys, .trackpad], "laptop: keys and trackpad")
check(TourTarget.allCases.count == 8 && TourTarget.allCases.contains(.apps) && TourTarget.allCases.contains(.menus), "eight targets")

// MARK: - Memory and what is owed

let fresh = TourMemory()
let sideways = TourMemory(seen: Set(TourPolicy.steps(L, voiceOver: false)))
let everything = TourMemory(seen: Set(all))
let skipped = TourMemory(skipped: true)
let v1Done = TourMemory(seen: [.touch, .bar, .settings, .laptop])
let v1Sideways = TourMemory(seen: [.touch, .bar, .settings])
let v1Skipped = TourMemory(seen: [.touch], skipped: true)

check(TourPolicy.owed(L, voiceOver: false, fresh) == sidewaysSteps, "fresh, landscape")
check(TourPolicy.owed(P, voiceOver: false, fresh) == all, "fresh, portrait")
check(TourPolicy.owed(P, voiceOver: false, sideways) == [.laptop], "sideways leaves laptop owed")
check(TourPolicy.owed(L, voiceOver: false, sideways) == [], "nothing new sideways after it")
check(TourPolicy.owed(P, voiceOver: false, everything) == [] && TourPolicy.owed(L, voiceOver: false, everything) == [], "all seen")
check(TourPolicy.owed(P, voiceOver: false, skipped) == [] && TourPolicy.owed(L, voiceOver: true, skipped) == [], "skipped: nothing")
check(TourPolicy.owed(P, voiceOver: false, v1Done) == [.sharing] && TourPolicy.owed(L, voiceOver: false, v1Sideways) == [.sharing], "v1 memory: sharing owed")
check(TourMemory(names: ["touch", "settings", "gestures", ""], skipped: false) == TourMemory(seen: [.touch, .settings]), "unknown names ignored")
check(TourMemory(seen: [.laptop, .touch, .settings, .sharing]).names == ["touch", "sharing", "settings", "laptop"], "saved in order")
check(TourPolicy.passed(.bar, fresh) == TourMemory(seen: [.bar]), "passed saves")
check(TourPolicy.skipped(sideways) == TourMemory(seen: Set(sidewaysSteps), skipped: true), "skipped keeps seen")
let automaticRun = TourRun(steps: sidewaysSteps, at: .touch, replay: false)
let replayRun = TourRun(steps: sidewaysSteps, at: .touch, replay: true)
check(TourPolicy.skip(automaticRun, fresh) == TourMemory(skipped: true), "Skip in automatic turns tour off")
check(TourPolicy.skip(replayRun, sideways) == sideways, "Skip in Take the Tour saves nothing")

// MARK: - Automatic rule

func moment(now: Double, picture: Double? = 10, layoutAt: Double = 5, decided: Bool = false, activity: Double? = nil,
            down: Int = 0, busy: Bool = false, offered: Bool = false, voiceOver: Bool = false, enabled: Bool = true) -> TourMoment {
    TourMoment(now: now, pictureAt: picture, layoutAt: layoutAt, decided: decided, lastActivityAt: activity,
               touchesDown: down, busy: busy, offered: offered, voiceOver: voiceOver, enabled: enabled)
}
func decide(_ m: TourMoment, _ layout: TourLayout = L, _ memory: TourMemory = fresh) -> TourDecision {
    TourPolicy.automatic(m, layout, memory)
}
check(TourPolicy.beat == 1.0, "beat is 1 s")
check(decide(moment(now: 20, enabled: false)) == .pass(.nothingOwed), "disabled")
check(decide(moment(now: 20, offered: true)) == .pass(.nothingOwed), "already offered")
check(decide(moment(now: 20, picture: nil)) == .wait(until: nil), "no picture yet")
check(decide(moment(now: 10.99)) == .wait(until: 11), "in beat")
check(decide(moment(now: 11.0)) == .show(sidewaysSteps), "shows after beat")
check(decide(moment(now: 11.0), P) == .show(all) && decide(moment(now: 11.0), F) == .show(all), "upright: all five")
check(decide(moment(now: 11, activity: 9.99)) == .show(sidewaysSteps), "touch before picture ignored")
check(decide(moment(now: 11, activity: 10)) == .pass(.used), "touch at picture counts")
check(decide(moment(now: 11, down: 1)) == .pass(.busy) && decide(moment(now: 11, busy: true)) == .pass(.busy), "busy")
check(decide(moment(now: 11), L, skipped) == .pass(.nothingOwed), "skipped")
check(decide(moment(now: 11, layoutAt: 10.6), P) == .wait(until: 11.6) && decide(moment(now: 11.6, layoutAt: 10.6), P) == .show(all), "turn restarts beat")
check(decide(moment(now: 40, layoutAt: 39, decided: true), P) == .show([.laptop]) && decide(moment(now: 40, layoutAt: 39, decided: true), F) == .show([.laptop]), "turn offers only laptop")
check(decide(moment(now: 40, layoutAt: 39, decided: true, activity: 38.9), P) == .show([.laptop])
      && decide(moment(now: 40, layoutAt: 39, decided: true, activity: 39.2), P) == .pass(.used), "activity measured from turn")
check(decide(moment(now: 10.5, decided: true), P) == .wait(until: 11) && decide(moment(now: 11, decided: true), P) == .show([.laptop]), "reconnect beat from picture")

// MARK: - Tour version upgrade

func upgrade(_ m: TourMemory, _ v: Int?) -> (memory: TourMemory, write: Bool) { TourPolicy.upgraded(m, savedVersion: v) }
check(TourPolicy.version == 2, "version 2")
check(upgrade(v1Done, nil) == (TourMemory(), true) && upgrade(v1Skipped, nil) == (TourMemory(), true) && upgrade(everything, 1) == (TourMemory(), true), "older cleared and written")
check(upgrade(everything, 2) == (everything, false) && upgrade(skipped, 2) == (skipped, false) && upgrade(everything, 3) == (everything, false), "v2+ kept")

// MARK: - Sessions and runs

let decidedHere = TourSession(decided: true, offered: [L], running: false)
check(TourPolicy.nextSession(after: decidedHere, reconnected: true) == decidedHere, "reconnect keeps session")
check(TourPolicy.nextSession(after: decidedHere, reconnected: false) == TourSession(), "user session fresh")
check(TourPolicy.nextSession(after: TourSession(decided: true, offered: [L], running: true), reconnected: true) == TourSession(), "cut-short run restarts")
check(TourPolicy.nextSession(after: TourSession(decided: false, offered: [], running: false), reconnected: true) == TourSession(), "undecided restarts")

let replayL = TourPolicy.replay(L, voiceOver: false)!
check(replayL == TourRun(steps: sidewaysSteps, at: .touch, replay: true), "replay sideways")
check(TourPolicy.run(owed: []) == nil, "no owed -> nil")
let r2 = TourPolicy.next(replayL)!
check(r2.at == .bar && r2.passed == [.touch], "next advances")
func run(_ steps: [TourTopic], at: TourTopic, passed: Set<TourTopic> = [], replay: Bool = false) -> TourRun {
    TourRun(steps: steps, at: at, passed: passed, replay: replay)
}
check(TourPolicy.carry(run(all, at: .laptop, passed: [.touch, .bar, .sharing, .settings]), to: L, voiceOver: false, memory: sideways) == nil, "laptop sideways ends")
check(TourPolicy.carry(run(sidewaysSteps, at: .touch), to: L, voiceOver: true, memory: fresh) == run([.bar, .sharing, .settings], at: .bar), "VO skips touch to bar")
check(TourPolicy.carry(run(all, at: .laptop, replay: true), to: L, voiceOver: false, memory: fresh) == nil, "carry does not wrap to first")

// MARK: - Crease, width, cutout, placement (with StreamLayout)

func topHalf(_ size: CGSize) -> Bool {
    size.height > size.width && size.width >= 600 && size.width < 740 && size.height < 1100
}
for s in [CGSize(width: 710, height: 1000), CGSize(width: 1000, height: 710), CGSize(width: 669, height: 951), CGSize(width: 744, height: 1133), CGSize(width: 375, height: 667)] {
    check((TourPolicy.crease(s) != nil) == topHalf(s), "crease at \(s)")
    if let c = TourPolicy.crease(s) { check(c == (s.height / 2).rounded(), "inferred crease rounded at \(s)") }
}
let bookBand = CGRect(x: 455.5, y: 0, width: 40, height: 669), laptopBand = CGRect(x: 0, y: 455.5, width: 669, height: 40)
let bookInfo = FoldInfo.known(bookBand), laptopInfo = FoldInfo.known(laptopBand), flatInfo = FoldInfo.known(nil)
check(TourPolicy.crease(CGSize(width: 669, height: 951), laptopInfo) == 455.5, "known crease unrounded")
check(TourPolicy.crease(CGSize(width: 669, height: 951), flatInfo) == nil, "flat upright no crease")

check(TourPolicy.width(screen: CGSize(width: 1000, height: 710), layout: L, accessibilityText: false) == 360, "360 regular")
check(TourPolicy.width(screen: CGSize(width: 710, height: 500), layout: L, accessibilityText: false) == 480, "480 short sideways")
check(TourPolicy.width(screen: CGSize(width: 1000, height: 710), layout: L, accessibilityText: true) == 560, "560 accessibility")
check(TourPolicy.width(screen: CGSize(width: 375, height: 667), layout: F, accessibilityText: false) == 343, "screen - 2*margin")
check(TourPolicy.width(screen: CGSize(width: 951, height: 669), layout: L, accessibilityText: true, fold: bookInfo,
                       targets: CGRect(x: 5, y: 12, width: 46, height: 154)) == 392.5, "book pose rail-beside width: 455.5 - (51 + 12) = 392.5")
check(TourPolicy.width(screen: CGSize(width: 951, height: 669), layout: L, accessibilityText: true, fold: bookInfo) == 439.5, "book pose page width")
check(TourPolicy.width(screen: CGSize(width: 867, height: 669), layout: L, accessibilityText: false, fold: bookInfo,
                       targets: CGRect(x: 781, y: 10, width: 64, height: 66)) == 355.5, "book pose trailing target page width")
check(TourPolicy.cutout([CGRect(x: 100, y: 10, width: 50, height: 60), CGRect(x: 170, y: 20, width: 30, height: 30)], screen: CGSize(width: 1000, height: 710))
      == CGRect(x: 96, y: 6, width: 108, height: 68), "cutout union + 4")
check(TourPolicy.radius(.touch) == 16 && TourPolicy.radius(.bar) == 20, "radii")

struct Screen {
    let size: CGSize
    let layout: TourLayout
    let stream: CGRect
    let targets: [TourTarget: CGRect]
    let fold: FoldInfo
    func union(_ topic: TourTopic) -> CGRect? {
        let rects = TourPolicy.targets(topic, layout).compactMap { targets[$0] }
        guard let first = rects.first else { return nil }
        return rects.dropFirst().reduce(first) { $0.union($1) }
    }
}

func makeScreen(_ w: CGFloat, _ h: CGFloat, fold: FoldInfo = .inferred, menus: Bool = true, phone: Bool? = nil) -> Screen {
    let size = CGSize(width: w, height: h)
    let l = StreamLayout(size: size, fold: fold, keyboardTop: nil, aspect: 1.6, hasMenus: menus)
    let layout: TourLayout = l.isLandscape ? .landscape : ((phone ?? (w < 600)) ? .phone : .portrait)
    let stream = l.isLandscape ? l.pictureRoom : l.picture
    var targets: [TourTarget: CGRect] = [.stream: stream]
    if let r = l.appsButton { targets[.apps] = r }
    if let r = l.strip { targets[.strip] = r }
    if let r = l.menusButton { targets[.menus] = r }
    if let r = l.keyboardButton { targets[.keyboard] = r }
    if let r = l.settingsButton { targets[.settings] = r }
    if let r = l.keys { targets[.keys] = r }
    if let r = l.trackpad { targets[.trackpad] = r }
    return Screen(size: size, layout: layout, stream: stream, targets: targets, fold: fold)
}

func place(_ s: Screen, _ topic: TourTopic, height h: CGFloat, ax: Bool = false, inset: CGFloat = 0) -> TourPlacement {
    let t = s.union(topic)
    let w = TourPolicy.width(screen: s.size, layout: s.layout, accessibilityText: ax, fold: s.fold, targets: t)
    return TourPolicy.place(card: CGSize(width: w, height: h), targets: t, isStream: topic == .touch,
                            screen: s.size, layout: s.layout, stream: s.stream, bottomInset: inset, fold: s.fold)
}

// Landscape rail placement: card sits 12 pt to the right of the 56 pt leading rail, vertically centered on targets.
do {
    let flatL = makeScreen(951, 669, fold: flatInfo)
    let pBar = place(flatL, .bar, height: 230)
    let tBar = flatL.union(.bar)!
    check(pBar.card.minX == tBar.maxX + 12 && pBar.card.width == 360 && pBar.card.height == 230 && pBar.tail == nil && !pBar.coversTargets,
          "landscape rail .bar beside rail: \(pBar)")
    let pSettings = place(flatL, .settings, height: 200)
    let tSet = flatL.union(.settings)!
    check(pSettings.card.minX == tSet.maxX + 12 && !pSettings.coversTargets, "landscape rail .settings beside rail: \(pSettings)")
    let pTall = place(flatL, .bar, height: 900, inset: 20)
    check(pTall.card.minY == 16 && pTall.card.maxY == 669 - 16 - 20, "landscape tall card respects margins and home indicator")
    // Book pose: card stays completely off the vertical fold AND clear of the rail, even at accessibility sizes.
    let bookL = makeScreen(951, 669, fold: bookInfo)
    for ax in [false, true] {
        for topic in sidewaysSteps {
            let p = place(bookL, topic, height: 240, ax: ax)
            check(p.card.maxX <= bookBand.minX + 0.001 || p.card.minX >= bookBand.maxX - 0.001, "book pose \(topic) ax \(ax): off fold: \(p)")
            if topic != .touch {
                check(!p.coversTargets && p.card.minX >= bookL.union(topic)!.maxX + 12 - 0.001, "book pose \(topic) ax \(ax): clear of rail: \(p)")
            }
        }
    }
    // Tiny landscape screen where room beside rail cannot hold card: falls back and sets coversTargets.
    let tiny = TourPolicy.place(card: CGSize(width: 240, height: 180), targets: CGRect(x: 5, y: 12, width: 46, height: 150),
                                isStream: false, screen: CGSize(width: 260, height: 220), layout: L,
                                stream: CGRect(x: 64, y: 8, width: 188, height: 204), bottomInset: 0)
    check(tiny.coversTargets && tiny.tail == nil, "tiny landscape covers targets with no tail: \(tiny)")
    // Target in Book pose where beside + w crosses fold with midpoint on trailing side: offTheFold moves it past fold.
    let crossBook = TourPolicy.place(card: CGSize(width: 360, height: 200), targets: CGRect(x: 300, y: 100, width: 50, height: 50),
                                     isStream: false, screen: CGSize(width: 951, height: 669), layout: L,
                                     stream: CGRect(x: 64, y: 8, width: 879, height: 653), bottomInset: 0, fold: bookInfo)
    check(crossBook.card.minX >= bookBand.maxX - 0.001, "book pose crossing target pushed past fold: \(crossBook)")
}

// Portrait & phone placement: above bar / under bar on phone when taller / above crease in laptop pose.
do {
    let laptopP = makeScreen(669, 951, fold: laptopInfo)
    let pLap = place(laptopP, .laptop, height: 600)
    check(pLap.card.maxY <= laptopBand.minY - 16 + 0.001 && pLap.tail == nil, "laptop pose card stays above fold: \(pLap)")
    let pBar = place(laptopP, .bar, height: 200)
    check(pBar.card.maxY <= laptopP.stream.maxY - 12 + 0.001 && pBar.tail == nil, "laptop pose bar card has no tail across fold: \(pBar)")
    // Target within 48 pt of card bottom across a horizontal fold still gets no tail.
    let acrossFold = TourPolicy.place(card: CGSize(width: 360, height: 200), targets: CGRect(x: 100, y: 470, width: 300, height: 40),
                                      isStream: false, screen: CGSize(width: 669, height: 951), layout: P,
                                      stream: CGRect(x: 8, y: 8, width: 653, height: 440), bottomInset: 0, fold: laptopInfo)
    check(acrossFold.tail == nil, "no tail across horizontal fold: \(acrossFold)")
    // Open flat upright (669x951, known(nil)) has no crease: tall touch card grows past inferred 476.
    let flatUpright = makeScreen(669, 951, fold: flatInfo, phone: false)
    let tallFlatTouch = place(flatUpright, .touch, height: 600)
    check(tallFlatTouch.card.height == 600, "flat upright ignores inferred crease: \(tallFlatTouch)")

    let proMax = makeScreen(440, 894, fold: flatInfo, phone: true)
    let pSmall = place(proMax, .bar, height: 200)
    check(pSmall.card.maxY == proMax.stream.maxY - 12 && pSmall.tail?.edge == .down, "phone small card in picture with tail down: \(pSmall)")
    let pUnder = place(proMax, .bar, height: 320)
    check(pUnder.card.minY == proMax.union(.bar)!.maxY + 12 && pUnder.tail?.edge == .up, "phone tall bar card goes under bar with tail up: \(pUnder)")
    let pLapPhone = place(proMax, .laptop, height: 300)
    check(pLapPhone.card.maxY == proMax.union(.laptop)!.minY - 12 && pLapPhone.tail?.edge == .down, "phone laptop card stands on targets: \(pLapPhone)")

    // Halves never put a card under their bar, only phone does.
    let highBarP = TourPolicy.place(card: CGSize(width: 360, height: 300), targets: CGRect(x: 100, y: 150, width: 300, height: 50), isStream: false,
                                    screen: CGSize(width: 500, height: 900), layout: P, stream: CGRect(x: 8, y: 8, width: 484, height: 100), bottomInset: 0)
    check(highBarP.coversTargets && highBarP.tail == nil, "halves never go under bar: \(highBarP)")
    let highBarF = TourPolicy.place(card: CGSize(width: 360, height: 300), targets: CGRect(x: 100, y: 150, width: 300, height: 50), isStream: false,
                                    screen: CGSize(width: 500, height: 900), layout: F, stream: CGRect(x: 8, y: 8, width: 484, height: 100), bottomInset: 0)
    check(highBarF.card.minY == 212 && highBarF.tail?.edge == .up && !highBarF.coversTargets, "phone goes under bar: \(highBarF)")
    // Grown card: halves from top margin, phone standing on targets.
    let grownP = TourPolicy.place(card: CGSize(width: 360, height: 220), targets: CGRect(x: 100, y: 360, width: 300, height: 50), isStream: false,
                                  screen: CGSize(width: 500, height: 900), layout: P, stream: CGRect(x: 8, y: 8, width: 484, height: 150), bottomInset: 0)
    check(grownP.card.minY == 16 && grownP.tail == nil, "halves grown card from top margin: \(grownP)")
    let grownF = TourPolicy.place(card: CGSize(width: 360, height: 220), targets: CGRect(x: 100, y: 360, width: 300, height: 50), isStream: false,
                                  screen: CGSize(width: 500, height: 900), layout: F, stream: CGRect(x: 8, y: 8, width: 484, height: 150), bottomInset: 0)
    check(grownF.card.maxY == 348 && grownF.tail?.edge == .down, "phone grown card stands on targets: \(grownF)")
    // Tail reach check (within 48 pt only).
    let farTarget = TourPolicy.place(card: CGSize(width: 360, height: 180), targets: CGRect(x: 100, y: 400, width: 300, height: 50), isStream: false,
                                     screen: CGSize(width: 500, height: 900), layout: P, stream: CGRect(x: 8, y: 8, width: 484, height: 300), bottomInset: 0)
    check(farTarget.tail == nil, "target > 48 pt below card gets no tail")
    // Targets not measured yet: centred in stream.
    let noTargets = TourPolicy.place(card: CGSize(width: 360, height: 200), targets: nil, isStream: false,
                                     screen: CGSize(width: 951, height: 669), layout: L, stream: CGRect(x: 64, y: 8, width: 879, height: 653), bottomInset: 0)
    check(noTargets.tail == nil && abs(noTargets.card.midY - 334.5) < 0.01, "no targets centred in stream")
    // Phone picture card grows past picture when no crease.
    let tallTouchF = place(proMax, .touch, height: 600)
    check(tallTouchF.card.height == 600, "phone picture card grows past picture")
}

// Grid across real devices and folds.
let gridScreens: [Screen] = [
    makeScreen(375, 667, phone: true), makeScreen(667, 375),
    makeScreen(393, 852, phone: true), makeScreen(852, 393),
    makeScreen(440, 894, phone: true), makeScreen(894, 440),
    makeScreen(382, 678, fold: flatInfo, phone: true), makeScreen(594, 466, fold: flatInfo),
    makeScreen(669, 951, fold: flatInfo, phone: false), makeScreen(669, 951, fold: laptopInfo, phone: false),
    makeScreen(951, 669, fold: flatInfo), makeScreen(951, 669, fold: bookInfo),
    makeScreen(744, 1133, phone: false), makeScreen(1133, 744),
    makeScreen(1032, 1376, phone: false), makeScreen(1376, 1032),
]
var gridCount = 0
for s in gridScreens {
    for ax in [false, true] {
        for topic in TourPolicy.steps(s.layout, voiceOver: false) {
            for h: CGFloat in [120, 230, 360, 620] {
                for inset: CGFloat in [0, 34] {
                    gridCount += 1
                    let p = place(s, topic, height: h, ax: ax, inset: inset)
                    let c = p.card
                    let bottom = s.size.height - 16 - inset
                    check(c.minX >= 16 - 0.001 && c.maxX <= s.size.width - 16 + 0.001 && c.minY >= 16 - 0.001 && c.maxY <= bottom + 0.001,
                          "\(s.size) \(topic) ax \(ax) h \(h): within margins: \(c)")
                    if let band = s.fold.verticalBand {
                        check(c.maxX <= band.minX + 0.001 || c.minX >= band.maxX - 0.001, "\(s.size) \(topic): off vertical fold: \(c)")
                    }
                    if let band = s.fold.horizontalBand, !p.coversTargets {
                        check(c.maxY <= band.minY - 16 + 0.001, "\(s.size) \(topic): above horizontal fold: \(c)")
                    }
                    if let tail = p.tail {
                        check(tail.x >= c.minX + 28 - 0.001 && tail.x <= c.maxX - 28 + 0.001, "\(s.size) \(topic): tail on straight edge")
                    }
                    // Idempotent when placed again at laid-out height.
                    check(place(s, topic, height: c.height, ax: ax, inset: inset) == p, "\(s.size) \(topic): idempotent")
                }
            }
        }
    }
}
check(gridCount >= 500, "grid checked \(gridCount) placements")

// MARK: - The words (all 64 combinations of TourFeatures)

let allOn = TourFeatures(menus: true, gestures: true, virtualDisplay: true, clipboard: true, pasteRightAway: true, sound: true)
let allOff = TourFeatures(menus: false, gestures: false, virtualDisplay: false, clipboard: false, pasteRightAway: false, sound: false)
let everyFeatures: [TourFeatures] = (0..<64).map { i in
    TourFeatures(menus: i & 1 != 0, gestures: i & 2 != 0, virtualDisplay: i & 4 != 0,
                 clipboard: i & 8 != 0, pasteRightAway: i & 16 != 0, sound: i & 32 != 0)
}
func with(_ base: TourFeatures = allOn, _ change: (inout TourFeatures) -> Void) -> TourFeatures {
    var f = base; change(&f); return f
}
func words(_ t: TourTopic, _ layout: TourLayout, mac: String = "Mac mini", device: String = "iPad", voiceOver: Bool = false,
           first: Bool = false, onItsSide: Bool = false, features: TourFeatures = allOn) -> TourCopy {
    TourPolicy.copy(t, layout, mac: mac, device: device, voiceOver: voiceOver, firstOfRun: first, keysOnItsSide: onItsSide, features: features)
}

let touchPad = words(.touch, L, first: true)
check(touchPad.title == "Tap, Hold, Drag and Pinch" && touchPad.subtitle == "What you do here happens on Mac mini.", "touch title")
check(touchPad.hint == "The picture of Mac mini fills the screen beside the rail.", "touch landscape hint")
check(words(.touch, P).hint == "The picture of Mac mini is at the top of the screen.", "touch upright hint")
check(words(.touch, L, device: "iPhone").rows.count == 5 && touchPad.rows.count == 6, "Pencil row on iPad only")
check(words(.touch, L, features: with { $0.gestures = false }).rows.count == 5, "gestures row conditional")
check(words(.touch, L, mac: "").subtitle == "What you do here happens on your Mac.", "your Mac fallback")

let barL = words(.bar, L)
check(barL.title == "Windows and Menus" && barL.rows[0].symbol == "magnifyingglass", "landscape bar starts with Apps")
check(barL.rows[0].text.contains("Apps lists the apps on Mac mini and the Desktop: tap"), "landscape Apps row")
check(words(.bar, L, voiceOver: true).rows[0].text.contains("Choose an open app again"), "landscape Apps row under VoiceOver")
check(barL.hint == "In the rail on the left: Apps, Menus and Keyboard.", "landscape bar hint with Menus")
check(words(.bar, L, features: with { $0.menus = false }).hint == "In the rail on the left: Apps and Keyboard.", "landscape bar hint without Menus")
check(words(.bar, P).rows[0].symbol == "hand.point.up.left" && words(.bar, P).hint == "In the bar below the picture, after Apps.", "upright bar thumbnails + hint")
check(words(.bar, P).rows.contains { $0.symbol == "keyboard" } && words(.bar, P).rows.contains { $0.symbol == "keyboard.badge.ellipsis" }, "Keyboard rows in portrait bar too")
check(words(.bar, L).rows.first { $0.symbol == "display" }!.text.contains("Text Size in Settings"), "Text Size in Settings named")
check(words(.bar, L, features: with { $0.virtualDisplay = false }).rows.first { $0.symbol == "display" }!.isNew, "VD off form marked New")
check(words(.bar, L, features: with { $0.menus = false }).title == "Windows"
      && !words(.bar, L, features: with { $0.menus = false }).rows.contains { $0.symbol == "filemenu.and.selection" },
      "no Menus -> title Windows and no Menus row")

let sharingL = words(.sharing, L)
check(sharingL.title == "Clipboard and Sound" && sharingL.hint == "In Settings, at the bottom of the rail on the left.", "sharing landscape")
check(words(.sharing, P).hint == "In Settings, the last button in the bar below the picture.", "sharing portrait")
check(words(.sharing, L, features: with { $0.sound = false }).title == "Clipboard"
      && words(.sharing, L, features: with { $0.clipboard = false }).title == "Sound"
      && words(.sharing, L, features: allOff).rows[0].symbol == "arrow.down.circle", "sharing adapts to Mac")
check(words(.sharing, L, features: with { $0.pasteRightAway = false }).rows[1].text.contains("sends it to Mac mini’s clipboard."), "paste right away off")

let settingsL = words(.settings, L)
check(settingsL.hint == "At the bottom of the rail on the left." && words(.settings, P).hint == "The last button in the bar below the picture.", "settings hints")
check(settingsL.rows.count == 5 && words(.settings, P).rows.count == 4, "upright row sideways only")
check(words(.settings, L, device: "iPhone", onItsSide: true).rows.last!.text == "Turn your iPhone on its side for a trackpad and keys.", "Duo onItsSide wording")
check(words(.settings, L, device: "iPhone", onItsSide: false).rows.last!.text == "Hold your iPhone upright for a trackpad and keys.", "iPhone upright wording")
check(words(.settings, L, voiceOver: true).rows.count == 3, "VO drops Reverse Scrolling and hold")

let laptopFirst = words(.laptop, P, first: true)
check(laptopFirst.title == "Keys and Trackpad" && laptopFirst.subtitle == "Upright, Sill adds keys and a trackpad.", "laptop first")
check(words(.laptop, P, first: false).subtitle == nil, "laptop subtitle firstOfRun only")
check(words(.laptop, P, first: true, onItsSide: true).subtitle == "On its side, Sill adds keys and a trackpad.", "Duo laptop subtitle")
check(laptopFirst.rows.count == 3 && laptopFirst.rows.map(\.symbol) == ["command", "cursorarrow.click.2", "hand.draw"], "laptop rows (no duplicate keyboard or Larger Picture)")
check(laptopFirst.rows[0].spoken.hasPrefix("Command, Option, Control and Shift"), "caps spoken by name")
check(laptopFirst.hint == "Below the bar: the trackpad, then the row of keys.", "laptop hint")
check(words(.laptop, P, voiceOver: true).rows.count == 1, "laptop VO drops trackpad rows")

// Check all 64 TourFeatures combinations, "New:" marks, and VoiceOver safety.
let expectedNewSymbols: Set<String> = [
    "plus.magnifyingglass", "hand.raised.fingers.spread", "filemenu.and.selection", "display",
    "keyboard.badge.ellipsis", "doc.on.clipboard", "doc.on.doc", "speaker.wave.2", "arrow.down.circle",
    "arrow.up.arrow.down", "timer"
]
check(TourPolicy.newPrefix == "New:", "newPrefix")
for layout in [L, P, F] {
    for vo in [false, true] {
        for f in everyFeatures {
            for step in TourPolicy.steps(layout, voiceOver: vo) {
                let c = words(step, layout, voiceOver: vo, first: true, features: f)
                check(c.rows.count <= 6, "at most 6 rows")
                for r in c.rows {
                    check(r.isNew == expectedNewSymbols.contains(r.symbol), "\(step) \(r.symbol): isNew")
                    if r.isNew {
                        check(r.spans.first == TourSpan(text: "New:", strong: true, isNew: true)
                              && r.spans[1] == TourSpan(text: " ", strong: false, isNew: false)
                              && r.spoken.hasPrefix("New: "), "New mark format")
                    }
                    if vo {
                        let s = r.spoken.lowercased()
                        check(!s.contains("tap") && !s.contains("touch and hold") && !s.contains("drag"), "no gestures in VO: \(r.spoken)")
                    }
                }
            }
        }
    }
}

check(TourPolicy.spokenTitle(barL, index: 1, count: 4) == "Windows and Menus, step 2 of 4", "spokenTitle multi")
check(TourPolicy.spokenTitle(laptopFirst, index: 0, count: 1) == "Keys and Trackpad", "spokenTitle single")
check(TourPolicy.takeTourFootnote(device: "iPad") == "A short tour of Sill’s controls on this iPad.", "takeTourFootnote")
check(TourPolicy.takeTourHint(device: "iPhone") == "Shows how to use Sill on this iPhone.", "takeTourHint")

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
