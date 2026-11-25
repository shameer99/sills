"""Mutants of iOSClient/TourPolicy.swift: each changes it in one place, is compiled with the check
and must make it fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(WT, "iOSClient/TourPolicy.swift")
LAYOUT = os.path.join(WT, "iOSClient/PhonePortraitLayout.swift")
DUO = os.path.join(WT, "iOSClient/DuoPosture.swift")
PINCH = 'rows.append(row("plus.magnifyingglass", [strong("Pinch"), plain(" to zoom the picture here, up to 5×. Zoomed in, two fingers move it, and one finger still taps, holds and drags on \\(mac).")], new: true))'
MUTANTS = [
    # When it shows by itself.
    ("the beat dropped", "if m.now < opens + beat { return .wait(until: opens + beat) }", "if false { return .wait(until: opens + beat) }"),
    ("activity since the picture ignored", "if let activity = m.lastActivityAt, activity >= opens { return .pass(.used) }", "if let activity = m.lastActivityAt, activity >= opens, false { return .pass(.used) }"),
    ("activity measured from the picture, not from a turn", "if let activity = m.lastActivityAt, activity >= opens {", "if let activity = m.lastActivityAt, activity >= picture {"),
    ("a rotation in the beat does not start it again", "let opens = max(picture, m.layoutAt)", "let opens = m.decided ? max(picture, m.layoutAt) : picture"),
    ("an inherited decision opens at the screen's start, not its picture", "let opens = max(picture, m.layoutAt)", "let opens = m.decided ? m.layoutAt : max(picture, m.layoutAt)"),
    ("a touch down ignored", "if m.touchesDown > 0 { return .pass(.busy) }", "if m.touchesDown > 99 { return .pass(.busy) }"),
    ("busy ignored", "if m.busy { return .pass(.busy) }", "if m.busy && false { return .pass(.busy) }"),
    ("offered ignored", "guard !m.offered else { return .pass(.nothingOwed) }", "guard !m.offered || true else { return .pass(.nothingOwed) }"),
    ("skipped ignored", "if m.skipped { return [] }", "if m.skipped && false { return [] }"),
    ("enabled inverted", "guard m.enabled else { return .pass(.nothingOwed) }", "guard !m.enabled else { return .pass(.nothingOwed) }"),
    ("a turn offers every owed step", "let list = m.decided ? owedHere.filter { only(layout).contains($0) } : owedHere", "let list = owedHere"),
    # Steps, targets and memory.
    ("touch kept under VoiceOver", "return voiceOver ? all.filter { $0 != .touch } : all", "return all"),
    ("laptop owed in landscape", "let all: [TourTopic] = layout == .landscape ? [.touch, .bar, .sharing, .settings] : [.touch, .bar, .sharing, .settings, .laptop]",
     "let all: [TourTopic] = layout == .landscape ? [.touch, .bar, .sharing, .settings, .laptop] : [.touch, .bar, .sharing, .settings, .laptop]"),
    ("landscape bar lights strip instead of apps", "case .bar: return layout == .landscape ? [.apps, .menus, .keyboard] : [.strip, .menus, .keyboard]",
     "case .bar: return [.strip, .menus, .keyboard]"),
    ("Menus dropped from bar targets", "case .bar: return layout == .landscape ? [.apps, .menus, .keyboard] : [.strip, .menus, .keyboard]",
     "case .bar: return layout == .landscape ? [.apps, .keyboard] : [.strip, .keyboard]"),
    ("sharing lighting stream", "case .sharing: return [.settings]", "case .sharing: return [.stream]"),
    ("Next not saving", "memory.seen.insert(t)", "_ = t"),
    ("Skip not saving", "memory.skipped = true", "memory.skipped = m.skipped"),
    ("Skip in Take the Tour turns the tour off", "run.replay ? m : skipped(m)", "skipped(m)"),
    # Version upgrade.
    ("the version not raised", "static let version = 2", "static let version = 1"),
    ("this version's memory cleared again (>= is >)", "guard let v = savedVersion, v >= version else", "guard let v = savedVersion, v > version else"),
    ("a later build's memory cleared (>= is ==)", "guard let v = savedVersion, v >= version else", "guard let v = savedVersion, v == version else"),
    ("a cleared memory that keeps Skip", "else { return (TourMemory(), true) }", "else { return (TourMemory(skipped: saved.skipped), true) }"),
    ("the upgrade not written", "else { return (TourMemory(), true) }", "else { return (TourMemory(), false) }"),
    ("a write when the memory is this version's", "return (saved, false)   // this version's", "return (saved, true)   // this version's"),
    # Sessions & runs.
    ("a reconnect decides afresh", "guard reconnected, last.decided, !last.running else { return TourSession() }", "guard reconnected && false, last.decided, !last.running else { return TourSession() }"),
    ("a session the person starts goes on with the last decision", "guard reconnected, last.decided, !last.running else { return TourSession() }", "guard last.decided, !last.running else { return TourSession() }"),
    ("a run cut short is not resumed at a reconnect", "guard reconnected, last.decided, !last.running else { return TourSession() }", "guard reconnected, last.decided else { return TourSession() }"),
    ("Next not advancing", "moved.at = run.steps[i + 1]", "moved.at = run.steps[i]"),
    ("carry goes to the first step, not the next one owed", "guard let next = list.first(where: { $0 > run.at && !run.passed.contains($0) }) else { return nil }", "guard let next = list.first(where: { !run.passed.contains($0) }) else { return nil }"),
    ("carry keeps a step the new layout lacks", "if list.contains(run.at) { return carried }", "if true { return carried }"),
    # Where the card goes.
    ("the crease ignored", "guard let band = DuoPosture.crease(screen, fold) else { return nil }", "guard let band = DuoPosture.crease(screen, fold), false else { return nil }"),
    ("the inferred crease unrounded", "if case .inferred = fold { return band.top.rounded() }", "if case .inferred = fold { return band.top }"),
    ("the fold's crease rounded", "return band.top.rounded() }\n        return band.top\n", "return band.top.rounded() }\n        return band.top.rounded()\n"),
    ("a card placed without the fold", "let fold = crease(screen, info)", "let fold = crease(screen)"),
    ("the book pose's card across the fold", "DuoPosture.offTheFold(x: clamped(mid), width: w, screenWidth: screen.width, margin: margin, fold: info)", "clamped(mid)"),
    ("a card wider than the book pose's page", "let page = DuoPosture.pageWidth(screenWidth: screen.width, margin: margin, fold: fold, for: targets) ?? .infinity", "let page = CGFloat.infinity"),
    ("a card as wide as the wider page whatever its targets", "fold: fold, for: targets) ?? .infinity", "fold: fold, for: nil) ?? .infinity"),
    ("landscape rail besideRail ignores fold", "let rightEdge = fold.verticalBand.map { min(screen.width - margin, $0.minX) } ?? (screen.width - margin)", "let rightEdge = screen.width - margin"),
    ("landscape card covers rail", "let beside = t.maxX + gap", "let beside = t.minX"),
    ("landscape card ignores book fold", "let placedX = DuoPosture.offTheFold(x: beside, width: w, screenWidth: screen.width, margin: margin, fold: info)", "let placedX = beside"),
    ("landscape coversTargets always false", "let rect = CGRect(x: cardX, y: y, width: w, height: cardH)\n            return TourPlacement(card: rect, tail: nil, coversTargets: rect.intersects(lit))",
     "let rect = CGRect(x: cardX, y: y, width: w, height: cardH)\n            return TourPlacement(card: rect, tail: nil, coversTargets: false)"),
    ("a tail across the crease", "let noFold = fold.map { !(rect.maxY <= $0 && $0 <= t.minY) } ?? true", "let noFold = true"),
    ("a portrait tail at any distance", "let reaches = t.minY >= rect.maxY && t.minY - rect.maxY <= tailReach", "let reaches = t.minY >= rect.maxY"),
    ("the card 360 pt wide on a short screen held sideways", "let preferred: CGFloat = accessibilityText ? 560 : (short ? 480 : 360)", "let preferred: CGFloat = accessibilityText ? 560 : (short ? 360 : 360)"),
    ("the home indicator ignored", "let bottom = max(top, screen.height - margin - max(0, bottomInset))", "let bottom = max(top, screen.height - margin)"),
    ("a phone's card never under its targets", "if layout == .phone && h > above - top {", "if false && h > above - top {"),
    ("the halves' card under its targets too", "if layout == .phone && h > above - top {", "if layout.upright && h > above - top {"),
    ("a phone's grown card from the top margin", "let y = layout == .phone ? max(top, above - h) : top", "let y = top"),
    ("the halves' grown card standing on its targets", "let y = layout == .phone ? max(top, above - h) : top", "let y = max(top, above - h)"),
    ("a phone's picture card not growing past the picture", "let reach = layout.upright && fold == nil ? bottom : lowest", "let reach = layout == .portrait && fold == nil ? bottom : lowest"),
    # Words & features.
    ("the Pencil row on iPhone", "if iPad { rows.append(row(\"applepencil\"", "if true { rows.append(row(\"applepencil\""),
    ("the upright row in portrait", "if layout == .landscape {\n                let turn = keysOnItsSide", "if true {\n                let turn = keysOnItsSide"),
    ("the Duo told to hold it upright", 'let turn = keysOnItsSide ? "Turn your \\(device) on its side" : "Hold your \\(device) upright"', 'let turn = "Hold your \\(device) upright"'),
    ("the Duo's laptop card says upright", 'let subtitle = keysOnItsSide ? "On its side, Sill adds keys and a trackpad." : "Upright, Sill adds keys and a trackpad."',
     'let subtitle = "Upright, Sill adds keys and a trackpad."'),
    ("a gesture word in a VoiceOver row", "else if voiceOver {\n                rows = [row(\"hand.point.up.left\"", "else if false {\n                rows = [row(\"hand.point.up.left\""),
    ("the trackpad's rows under VoiceOver", "if !voiceOver {\n                rows.append(row(\"cursorarrow.click.2\"", "if true {\n                rows.append(row(\"cursorarrow.click.2\""),
    ("laptop's subtitle on a card that is not the run's first", "subtitle: firstOfRun ? subtitle : nil", "subtitle: subtitle"),
    ("the caps not spoken by name", "spoken: \"Command, Option, Control and Shift stay on for the next key or trackpad click: tap Command, then C, to copy.\")", "spoken: nil)"),
    ("the swipe row with gestures off", "if features.gestures {", "if features.gestures || true {"),
    ("the Menus row without the button", "if features.menus {\n                rows.append(row(\"filemenu.and.selection\"", "if true {\n                rows.append(row(\"filemenu.and.selection\""),
    ("the title Windows with Menus", 'let title = features.menus ? "Windows and Menus" : "Windows"', 'let title = "Windows"'),
    ("Virtual Display off unmarked", 'something covers it")] + textSize, new: true))\n            }\n', 'something covers it")] + textSize))\n            }\n'),
    ("the clipboard's rows without clipboard", "if features.clipboard {", "if features.clipboard || true {"),
    ("the sound's row without sound", "if features.sound {", "if features.sound || true {"),
    ("Paste right away ignored", 'plain(features.pasteRightAway ? " puts it where \\(mac)’s cursor is." : " sends it to \\(mac)’s clipboard.")', 'plain(" puts it where \\(mac)’s cursor is.")'),
    ("Reverse Scrolling under VoiceOver", "if !voiceOver {\n                rows.append(row(\"arrow.up.arrow.down\"", "if true {\n                rows.append(row(\"arrow.up.arrow.down\""),
    ("New: dropped", 'let mark = new ? [TourSpan(text: newPrefix, strong: true, isNew: true), TourSpan(text: " ")] : []', "let mark: [TourSpan] = []"),
    ("the mark not marked", "TourSpan(text: newPrefix, strong: true, isNew: true)", "TourSpan(text: newPrefix, strong: true, isNew: false)"),
    ("the mark's word changed", 'static let newPrefix = "New:"', 'static let newPrefix = "NEW:"'),
    ("VoiceOver reads a New row without its mark", "?? all.map(\\.text).joined())", "?? spans.map(\\.text).joined())"),
    ("the pinch row unmarked", 'one finger still taps, holds and drags on \\(mac).")], new: true))', 'one finger still taps, holds and drags on \\(mac).")]))'),
    ("the pinch row on iPad only", PINCH, "if iPad { " + PINCH + " }"),
]
caught = 0
for name, old, new in MUTANTS:
    src = open(F, encoding="utf-8").read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, "TourPolicy.swift"); open(mf, "w", encoding="utf-8").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        r = subprocess.run(["swiftc", "-O", mf, LAYOUT, DUO, os.path.join(HERE, "main.swift"), "-o", exe], capture_output=True, text=True)
        if not os.path.exists(exe): print(f"{name}: did not compile ({r.stderr.strip().splitlines()[:1]})"); continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=300)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode != 0:
            caught += 1
            print(f"{name}: caught ({failed[0][:100] if failed else f'exit status {r.returncode}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
