"""Mutants of iOSClient/DuoPosture.swift (docs/iphone-duo-plan.md): each changes it in one place and must
fail the check (main.swift). usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "duo")          # the mutants' sources and binaries
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/DuoPosture.swift")
orig = open(SRC).read()
MUTANTS = {
    # The posture.
    "M1 the fold in the way open flat too": ("var foldActive: Bool { hinge == .partiallyOpen && fold != nil }",
                                             "var foldActive: Bool { hinge != .closed && fold != nil }"),
    "M2 known without a hinge": ("guard hinge != .unknown else { return .inferred }", "guard hinge != .closed else { return .inferred }"),
    "M3 the band not clipped": ("let band = fold.intersection(CGRect(origin: .zero, size: size))", "let band = fold"),
    "M4 a fold off the screen kept": ("return .known(band.isNull || band.isEmpty ? nil : band)", "return .known(band.isNull ? nil : band)"),
    "M5 the book pose upright": ("case .partiallyOpen: return sideways ? .book : .laptop", "case .partiallyOpen: return sideways ? .laptop : .book"),
    "M6 the cover's poses swapped": ("case .closed: return sideways ? .closedSide : .closedUpright", "case .closed: return sideways ? .closedUpright : .closedSide"),
    "M7 the status bar hidden on the cover": ("pose == .laptop || pose == .flatPortrait || pose == .book || pose == .flatLandscape\n    }",
                                              "pose == .laptop || pose == .flatPortrait || pose == .book || pose == .flatLandscape || pose == .closedUpright\n    }"),
    "M7b the status bar kept sideways (the rule before Noah's pick)": ("pose == .laptop || pose == .flatPortrait || pose == .book || pose == .flatLandscape\n    }",
                                                                       "pose == .laptop || pose == .flatPortrait\n    }"),
    "M7c the status bar shown open flat upright": ("pose == .laptop || pose == .flatPortrait || pose == .book || pose == .flatLandscape\n    }",
                                                   "pose == .laptop || pose == .book || pose == .flatLandscape\n    }"),
    "M7d the status bar shown open flat sideways": ("pose == .laptop || pose == .flatPortrait || pose == .book || pose == .flatLandscape\n    }",
                                                    "pose == .laptop || pose == .flatPortrait || pose == .book\n    }"),
    "M7d the inner display closed": ("var onInnerDisplay: Bool { hinge == .partiallyOpen || hinge == .fullyOpen }",
                                     "var onInnerDisplay: Bool { hinge != .unknown }"),
    "M7e no fold before the first report": ("guard reported == .unknown, let regionActive else { return reported }",
                                            "guard reported == .unknown, let regionActive, false else { return reported }"),
    "M7f the fold over a report": ("guard reported == .unknown, let regionActive else { return reported }",
                                   "guard let regionActive else { return reported }"),
    "M7g an active fold read as flat": ("return regionActive ? .partiallyOpen : .fullyOpen", "return regionActive ? .fullyOpen : .partiallyOpen"),
    "M8 a vertical fold read as across": ("guard let band, band.width >= band.height else { return nil }", "guard let band else { return nil }"),
    "M9 a fold across read as vertical": ("guard let band, band.height > band.width else { return nil }", "guard let band, band.height >= band.width else { return nil }"),
    # The crease, as before iOS 27.1, and the laptop pose's.
    "M10 the inferred crease to 750 pt wide": ("size.width >= 600, size.width < 740, size.height < 1100", "size.width >= 600, size.width < 750, size.height < 1100"),
    "M11 the inferred crease rounded": ("return (size.height / 2, size.height / 2)", "return ((size.height / 2).rounded(), (size.height / 2).rounded())"),
    "M12 the laptop pose's crease at the fold's middle": ("return (band.minY, band.maxY)", "return (band.midY, band.midY)"),
    # Pane aspect.
    "M23 16:9 for no picture": ("static let defaultAspect: CGFloat = 1.6", "static let defaultAspect: CGFloat = 16.0 / 9.0"),
    "M24 the pane follows a fitted window": ("guard !fitsWindowToPane, video.width > 0", "guard video.width > 0"),
    "M25 the picture's shape upside down": ("return video.width / video.height", "return video.height / video.width"),
    # The connect screen's room above the laptop pose's fold.
    "M45b the inferred crease bounds the column": ("guard case .known = fold, let crease = crease(size, fold) else { return nil }",
                                                   "guard let crease = crease(size, fold) else { return nil }"),
    "M45c the room to the fold's bottom": ("        return max(0, crease.top)\n", "        return max(0, crease.bottom)\n"),
    # One page.
    "M37 a card left across the fold": ("guard let band = fold.verticalBand, x < band.maxX, x + width > band.minX else { return x }",
                                        "guard let band = fold.verticalBand, false, x < band.maxX else { return x }"),
    "M38 the leading page ignores the margin": ("let leadingFits = width <= band.minX - margin", "let leadingFits = width <= band.minX"),
    "M39 the trailing page left across": ("let leading = band.minX - width, trailing = band.maxX", "let leading = band.minX - width, trailing = x"),
    "M39b the leading page with a margin from the fold": ("let leading = band.minX - width, trailing = band.maxX", "let leading = band.minX - width - margin, trailing = band.maxX"),
    "M40 a tie to the trailing page": ("if x + width / 2 <= band.midX {", "if x + width / 2 < band.midX {"),
    "M41 the other page never tried": ("            if trailingFits { return trailing }\n        } else {", "        } else {"),
    "M42 the page as wide as the screen": ("guard let target, !target.isNull else { return max(leading, trailing) }",
                                           "guard let target, !target.isNull else { return max(0, screenWidth - 2 * margin) }"),
    "M42b the wider page whatever the target": ("return target.midX <= band.midX ? leading : trailing", "return max(leading, trailing)"),
    "M42c a tie to the trailing page": ("return target.midX <= band.midX ? leading : trailing", "return target.midX < band.midX ? leading : trailing"),
    "M42d the trailing page without its margin": ("trailing = max(0, screenWidth - margin - band.maxX)", "trailing = max(0, screenWidth - band.maxX)"),
    "M43 the column on a page without its margins": ("guard let band = fold.verticalBand, columnWidth + 32 <= band.minX else { return centred }",
                                                      "guard let band = fold.verticalBand, columnWidth <= band.minX else { return centred }"),
    "M44 the column at the page's edge": ("return max(16, (band.minX - columnWidth) / 2)", "return 16"),
    "M45 the leading page for a fold across": ("fold.verticalBand.map { max(0, $0.minX) }", "fold.band.map { max(0, $0.minX) }"),
    # The window lights' menu.
    "M50 the lights left on the laptop pose's fold": ("if !down, let band = fold.horizontalBand, rect(below: false).intersects(band) { down = true }",
                                                      "if false, let band = fold.horizontalBand, rect(below: false).intersects(band) { down = true }"),
    "M51 the lights flipped wherever a fold is": ("if !down, let band = fold.horizontalBand, rect(below: false).intersects(band) { down = true }",
                                                  "if !down, fold.horizontalBand != nil { down = true }"),
    "M52 the lights left across the book pose's fold": ("let left = offTheFold(x: x - size.width / 2, width: size.width, screenWidth: screenWidth, margin: 8, fold: fold)",
                                                        "let left = x - size.width / 2"),
    "M53 the lights' gap dropped": ("y: below ? thumbnail.maxY + gap : thumbnail.minY - gap - size.height,", "y: below ? thumbnail.maxY : thumbnail.minY - gap - size.height,"),
    # The harness.
    "M46 half for flat": ('case "flat"?: return .fullyOpen', 'case "flat"?: return .partiallyOpen'),
    "M47 the stand-in 30 pt": ("CGRect(x: size.width / 2 - 20, y: 0, width: 40, height: size.height)", "CGRect(x: size.width / 2 - 15, y: 0, width: 30, height: size.height)"),
    "M48 the cover's strip on the right on its side": ("case (678, 466): return (0, 84, 34, 0)", "case (678, 466): return (0, 0, 34, 84)"),
    "M49 the inner display's status bar at the top sideways": ("case (951, 669): return statusBarHidden ? (0, 0, 34, 0) : (0, 0, 34, 84)",
                                                               "case (951, 669): return statusBarHidden ? (0, 0, 34, 0) : (84, 0, 34, 0)"),
    "M49b the status bar never hidden upright": ("case (669, 951): return statusBarHidden ? (0, 0, 34, 0) : (82, 0, 34, 0)",
                                                 "case (669, 951): return (82, 0, 34, 0)"),
    "M49c the cover's strip gone with the status bar": ("case (466, 678): return (0, 0, 34, 84)", "case (466, 678): return statusBarHidden ? (0, 0, 34, 0) : (0, 0, 34, 84)"),
    # The inner display upright with the software keyboard up (#215): whether a frame can be the glass.
    "G1 a frame of no height taken": ("guard let frame, frame.height > 0, abs(frame.width - size.width) <= 1,",
                                      "guard let frame, frame.height >= 0, abs(frame.width - size.width) <= 1,"),
    "G2 a frame of any width taken": ("guard let frame, frame.height > 0, abs(frame.width - size.width) <= 1, abs(frame.maxY - size.height) <= 1,",
                                      "guard let frame, frame.height > 0, abs(frame.maxY - size.height) <= 1,"),
    "G3 two points of width": ("guard let frame, frame.height > 0, abs(frame.width - size.width) <= 1,",
                               "guard let frame, frame.height > 0, abs(frame.width - size.width) <= 2,"),
    "G4 a frame short of the foot taken": ("abs(frame.width - size.width) <= 1, abs(frame.maxY - size.height) <= 1,\n              frame.minY > controlsTop",
                                           "abs(frame.width - size.width) <= 1,\n              frame.minY > controlsTop"),
    "G5 a glass at the controls' top taken": ("frame.minY > controlsTop, frame.minY < size.height else { return nil }",
                                              "frame.minY >= controlsTop, frame.minY < size.height else { return nil }"),
    "G6 the page taken for the glass": ("frame.minY > controlsTop, frame.minY < size.height else { return nil }",
                                        "frame.minY < size.height else { return nil }"),
    "G7 a frame at the foot taken": ("frame.minY > controlsTop, frame.minY < size.height else { return nil }",
                                     "frame.minY > controlsTop, frame.minY <= size.height else { return nil }"),
    # The glass: open flat as reported, in the laptop pose as read.
    "G8 a keyboard at the foot kept": ("guard let reported, reported < size.height else { return nil }\n        guard laptop",
                                       "guard let reported, reported <= size.height else { return nil }\n        guard laptop"),
    "G9 open flat read as the laptop pose": ("guard laptop else { return KeyboardGlass(top: reported) }",
                                             "guard laptop || true else { return KeyboardGlass(top: reported) }"),
    "G10 the laptop pose as reported (the page)": ("return KeyboardGlass(top: plausibleGlass(read, size: size, controlsTop: controlsTop))",
                                                   "return KeyboardGlass(top: reported)"),
    "G11 any reading taken as it is": ("return KeyboardGlass(top: plausibleGlass(read, size: size, controlsTop: controlsTop))",
                                       "return KeyboardGlass(top: read?.minY)"),
    # A look: the keyboard's own views.
    "K1 the page taken for a look": ("&& frame.minY > reported.minY + 1 && frame.minY < screen.height",
                                     "&& frame.minY > reported.minY && frame.minY < screen.height"),
    "K2 the innermost view first": ("return frames.first { frame in", "return frames.last { frame in"),
    "K3 a look with no keyboard reported": ("guard let reported else { return nil }\n        return frames.first",
                                            "let reported = reported ?? .zero\n        return frames.first"),
    "K4 a view of any width taken": ("frame.height > 0 && abs(frame.width - screen.width) <= 1 && abs(frame.maxY - screen.height) <= 1\n",
                                     "frame.height > 0 && abs(frame.maxY - screen.height) <= 1\n"),
    "K5 a view short of the foot taken": ("frame.height > 0 && abs(frame.width - screen.width) <= 1 && abs(frame.maxY - screen.height) <= 1\n",
                                         "frame.height > 0 && abs(frame.width - screen.width) <= 1\n"),
    "K6 looks within half a point": ("return abs(lastLook.minY - begin.minY) > 1.5", "return abs(lastLook.minY - begin.minY) > 0.5"),
    "K7 looks never off": ("return abs(lastLook.minY - begin.minY) > 1.5", "return abs(lastLook.minY - begin.minY) > 1000"),
    "K8 a report with no begin frame compared": ("guard let lastLook, let begin, begin.height > 0, !begin.isNull else { return false }",
                                                 "guard let lastLook, let begin else { return false }"),
    "K9 the first look later": ("static let keyboardLookDelays: [Double] = [0.02, 0.06, 0.15, 0.4, 1, 2]",
                                "static let keyboardLookDelays: [Double] = [0.1, 0.2, 0.4, 1, 2]"),
    "K10 a second for a switch's report (4e9f412's wait)": ("static let keyboardSwitchReportWait: Double = 0.4", "static let keyboardSwitchReportWait: Double = 1"),
    # Whether the row fits.
    "F1 52 pt taken for too little": ("glassTop - controlsTop >= keyboardRowLeast + keyboardRowMargins", "glassTop - controlsTop > keyboardRowLeast + keyboardRowMargins"),
    "F2 the row's black forgotten": ("glassTop - controlsTop >= keyboardRowLeast + keyboardRowMargins", "glassTop - controlsTop >= keyboardRowLeast"),
    # The hints: what readings teach, what to assume.
    "H1 a show bringing the other keyboard back taken for the letters": (
        "            if sameKeyboard(height, hints.other[widthKey]), !sameKeyboard(height, hints.letters[key]) { return hints }\n", ""),
    "H2 a show's reading of both keyboards' height left untaught": ("if sameKeyboard(height, hints.other[widthKey]), !sameKeyboard(height, hints.letters[key]) { return hints }",
                                                                   "if sameKeyboard(height, hints.other[widthKey]) { return hints }"),
    "H3 a reading still of the keyboard before a switch taught": ("guard !sameKeyboard(height, before), !sameKeyboard(height, hints.letters[key]) else { return hints }",
                                                                 "guard !sameKeyboard(height, hints.letters[key]) else { return hints }"),
    "H4 the letters keyboard taught as the other": ("guard !sameKeyboard(height, before), !sameKeyboard(height, hints.letters[key]) else { return hints }",
                                                    "guard !sameKeyboard(height, before) else { return hints }"),
    "H5 a fold's reading taught": ("        case .other:\n            return hints\n", "        case .other:\n            learned.other[widthKey] = height\n"),
    "H6 one keyboard within half a point": ("return abs(a - b) < 1.5", "return abs(a - b) < 0.5"),
    "H7 one keyboard within 1.5 pt inclusive": ("return abs(a - b) < 1.5", "return abs(a - b) <= 1.5"),
    "H8 the hint's width unrounded": ('"\\(mode ?? "")@\\(Int(width.rounded()))"', '"\\(mode ?? "")@\\(Int(width))"'),
    "H9 the width key unrounded": ('"@\\(Int(width.rounded()))"', '"@\\(Int(width))"'),
    "Q1 a show assumes nothing": ("case .show, .modeChange: return hints.letters[key]", "case .show, .modeChange: return nil"),
    "Q2 😀 assumes the letters keyboard": ("return sameKeyboard(current, letters) ? hints.other[widthKey] : letters", "return letters"),
    "Q3 ABC assumes the other keyboard": ("return sameKeyboard(current, letters) ? hints.other[widthKey] : letters",
                                          "return sameKeyboard(current, letters) ? hints.other[widthKey] : hints.other[widthKey]"),
    "Q4 a switch with no letters known assumes the other": ("guard let letters = hints.letters[key] else { return nil }",
                                                            "guard let letters = hints.letters[key] else { return hints.other[widthKey] }"),
    "Q5 a fold assumes the letters keyboard": ("        case .other: return nil\n        }\n    }", "        case .other: return hints.letters[key]\n        }\n    }"),
    # When readings come, and which reports are readings.
    "R1 a coming keyboard read before its animation ends": ("case .animating(let duration): return [duration + 0.02, duration + 0.1, 1.5, 2.5]",
                                                           "case .animating(let duration): return [0.02, 0.1, 1.5, 2.5]"),
    "R2 one late reload after the animation": ("case .animated: return [0.01, 0.06, 1, 2]", "case .animated: return [0.01, 0.06, 1]"),
    "R3 a switch read from 150 ms": ("case .other: return [0.05, 0.09, 0.13, 0.18, 0.25, 0.32, 1, 2]", "case .other: return [0.15, 0.18, 0.25, 0.32, 1, 2]"),
    "R4 a fold read as a switch": ("case .fold: return [0.15, 0.3, 0.45, 0.6, 0.8, 1, 1.5, 2]", "case .fold: return [0.05, 0.09, 0.13, 0.18, 0.25, 0.32, 1, 2]"),
    "R5 a fold's settling as short": ("change == .fold ? 1.2 : keyboardSettle", "change == .fold ? keyboardSettle : keyboardSettle"),
    "R6 the settling 0.6 s": ("static let keyboardSettle: Double = 0.8", "static let keyboardSettle: Double = 0.6"),
    "R7 stale for ever after a fold": ("guard let staleFrame, at < staleUntil else { return false }", "guard let staleFrame else { return false }"),
    "R8 stale at the end of the two seconds": ("guard let staleFrame, at < staleUntil else { return false }", "guard let staleFrame, at <= staleUntil else { return false }"),
    "R9 a stale reading's height not compared": ("return abs(begin.minY - staleFrame.minY) < 0.5 && abs(begin.height - staleFrame.height) < 0.5",
                                                 "return abs(begin.minY - staleFrame.minY) < 0.5"),
    "R10 a stale reading within 1.5 pt": ("return abs(begin.minY - staleFrame.minY) < 0.5 && abs(begin.height - staleFrame.height) < 0.5",
                                          "return abs(begin.minY - staleFrame.minY) < 1.5 && abs(begin.height - staleFrame.height) < 0.5"),
    "R11 late from two seconds": ("static let keyboardLateRead: Double = 1", "static let keyboardLateRead: Double = 2"),
    "R12 a hide read as a reading": ("guard !hiding, !animated, let begin,", "guard !animated, let begin,"),
    "R13 a show's report read as a reading": ("guard !hiding, !animated, let begin,", "guard !hiding, let begin,"),
    "R14 a report before the reload read": ("let reloadedAt, at >= reloadedAt else { return false }", "let reloadedAt else { return false }"),
    "R15 the window's end included": ("return at - reloadedAt < keyboardReadWindow", "return at - reloadedAt <= keyboardReadWindow"),
    "R16 a begin frame of no height read": ("let begin, begin.height > 0, !begin.isNull, let reloadedAt,", "let begin, !begin.isNull, let reloadedAt,"),
    "R17 the window a second": ("static let keyboardReadWindow: Double = 0.5", "static let keyboardReadWindow: Double = 1"),
    "R18 a new keyboard never confirmed": ("return readings.count - first < 2", "return readings.count - first < 1"),
    "R19 a new keyboard confirmed twice": ("return readings.count - first < 2", "return readings.count - first < 3"),
    "R20 a glass a point away taken for the same": ("return abs(a.minY - b.minY) < 0.5 && abs(a.height - b.height) < 0.5 && abs(a.width - b.width) < 0.5",
                                                    "return abs(a.minY - b.minY) < 1.5 && abs(a.height - b.height) < 0.5 && abs(a.width - b.width) < 0.5"),
    "R21 nothing before taken for the glass read": ("            guard let b else { return false }\n", "            guard let b else { return true }\n"),
}
caught = 0
for name, (old, new) in MUTANTS.items():
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    path = os.path.join(OUT, "mutant.swift")
    open(path, "w").write(orig.replace(old, new))
    b = subprocess.run(["swiftc", "-O", path, os.path.join(SP, "main.swift"), "-o", os.path.join(OUT, "mutant")],
                       capture_output=True, text=True)
    if b.returncode != 0:
        print(f"{name}: DOES NOT COMPILE\n{b.stderr[:600]}"); continue
    r = subprocess.run([os.path.join(OUT, "mutant")], capture_output=True, text=True, timeout=300)
    failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
    ok = r.returncode != 0
    caught += ok
    print(f"{'caught' if ok else 'MISSED'} {name}: {len(failed)} failing, e.g. {[f[:110] for f in failed[:2]]}")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
