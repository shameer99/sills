"""Mutants of HardwareKeyboardPolicy.swift (iOSClient): each changes it in one place and must make the check
(main.swift) fail. usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "hardware-keyboard")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/HardwareKeyboardPolicy.swift")
orig = open(SRC).read()
MUTANTS = [
    ("M1 a keyboard's hold with something open", "var wantsAutomatic: Bool { onScreen && attached && takers.isEmpty }",
     "var wantsAutomatic: Bool { onScreen && attached }"),
    ("M2 a keyboard's hold with no keyboard", "var wantsAutomatic: Bool { onScreen && attached && takers.isEmpty }",
     "var wantsAutomatic: Bool { onScreen && takers.isEmpty }"),
    ("M3 a keyboard's hold with no view in a window", "var wantsAutomatic: Bool { onScreen && attached && takers.isEmpty }",
     "var wantsAutomatic: Bool { attached && takers.isEmpty }"),
    ("M4 taking it whoever holds it", "private var takeIfWanted: [Action] { hold == .none && wantsAutomatic ? [.take(automatic: true)] : [] }",
     "private var takeIfWanted: [Action] { wantsAutomatic ? [.take(automatic: true)] : [] }"),
    ("M5 a joining view keeps the old one's hold", "        onScreen = true\n        hold = .none\n        lastHeld = .none\n",
     "        onScreen = true\n        lastHeld = .none\n"),
    ("M6 a joining view keeps the old one's last hold", "        onScreen = true\n        hold = .none\n        lastHeld = .none\n",
     "        onScreen = true\n        hold = .none\n"),
    ("M7 a joining view takes nothing", "        let actions = takeIfWanted\n        return actions.isEmpty ? takeSoftIfWanted() : actions\n    }\n\n    /// The current input view left",
     "        return []\n    }\n\n    /// The current input view left"),
    ("M8 a leaving view still counts as on screen", "        onScreen = false\n        hold = .none\n        autoSoft = false",
     "        hold = .none\n        autoSoft = false"),
    ("M9 a repeated attach acts (it fights another responder)", "        guard now != attached else { return [] }\n", ""),
    ("M10 an attach takes nothing", "            return takeIfWanted\n        }\n        if hold == .automatic {",
     "            return []\n        }\n        if hold == .automatic {"),
    ("M11 a detach keeps the keyboard's hold", "            return releaseHold()\n        }\n        return []\n    }\n\n    /// What is open changed.",
     "            return []\n        }\n        return []\n    }\n\n    /// What is open changed."),
    ("M12 a detach lets the person's go too", "        if hold == .automatic {\n            if wantsSoftAutomatic {",
     "        if hold != .none {\n            if wantsSoftAutomatic {"),
    ("M13 a taker opening keeps the keyboard's hold", "            if hold == .automatic { return releaseHold() }",
     "            if hold == .automatic { return [] }"),
    ("M14 a taker opening lets the person's go too (the drawer and Menus did not)", "            if hold == .own && autoSoft {\n                autoSoft = false\n                return releaseHold()\n            }",
     "            if hold == .own {\n                autoSoft = false\n                return releaseHold()\n            }"),
    ("M15 the last taker closing takes nothing", "        guard !was.isEmpty else { return [] }\n        let actions = takeIfWanted\n        return actions.isEmpty ? takeSoftIfWanted() : actions",
     "        return []"),
    ("M16 nothing open again takes it on every repeat (it fights)", "        guard !was.isEmpty else { return [] }\n        let actions = takeIfWanted\n        return actions.isEmpty ? takeSoftIfWanted() : actions",
     "        let actions = takeIfWanted\n        return actions.isEmpty ? takeSoftIfWanted() : actions"),
    ("M17 the button over nothing takes it for the keyboard", "        case .none:\n            guard onScreen else { return [] }\n            softDismissed = false\n            pendingAutoSoft = false\n            return [.take(automatic: false)]\n        case .automatic:\n            softDismissed = false\n            autoSoft = false\n            hold = .own\n            return [.makeOwn]\n        case .own:\n            autoSoft = false\n            if textFocus",
     "        case .none:\n            guard onScreen else { return [] }\n            softDismissed = false\n            pendingAutoSoft = false\n            return [.take(automatic: true)]\n        case .automatic:\n            softDismissed = false\n            autoSoft = false\n            hold = .own\n            return [.makeOwn]\n        case .own:\n            autoSoft = false\n            if textFocus"),
    ("M18 the button over nothing with no view asks anyway", "        case .none:\n            guard onScreen else { return [] }\n            softDismissed = false\n            pendingAutoSoft = false\n            return [.take(automatic: false)]\n        case .automatic:\n            softDismissed = false\n            autoSoft = false\n            hold = .own\n            return [.makeOwn]\n        case .own:\n            autoSoft = false\n            if textFocus",
     "        case .none:\n            softDismissed = false\n            pendingAutoSoft = false\n            return [.take(automatic: false)]\n        case .automatic:\n            softDismissed = false\n            autoSoft = false\n            hold = .own\n            return [.makeOwn]\n        case .own:\n            autoSoft = false\n            if textFocus"),
    ("M19 the button over the keyboard's hold lets go", "        case .automatic:\n            softDismissed = false\n            autoSoft = false\n            hold = .own\n            return [.makeOwn]\n        case .own:\n            autoSoft = false\n            if textFocus",
     "        case .automatic:\n            return releaseHold()\n        case .own:\n            autoSoft = false\n            if textFocus"),
    ("M20 the button over the keyboard's hold lights nothing", "        case .automatic:\n            softDismissed = false\n            autoSoft = false\n            hold = .own\n            return [.makeOwn]\n        case .own:\n            autoSoft = false\n            if textFocus",
     "        case .automatic:\n            return [.makeOwn]\n        case .own:\n            autoSoft = false\n            if textFocus"),
    ("M21 the button over the person's always lets go (keys stop with a keyboard attached)", "            guard wantsAutomatic else { return releaseHold() }\n",
     "            return releaseHold()\n"),
    ("M22 the button over the person's keeps it theirs", "            hold = .automatic\n            return [.makeAutomatic]\n        }\n    }\n\n    /// `setKeyboard(shown:)`",
     "            return [.makeAutomatic]\n        }\n    }\n\n    /// `setKeyboard(shown:)`"),
    ("M23 a restore over the keyboard's hold keeps it the keyboard's", "        case .automatic:\n            softDismissed = false\n            autoSoft = false\n            hold = .own\n            return [.makeOwn]\n        case .own:\n            autoSoft = false\n            return []",
     "        case .automatic: return []\n        case .own:\n            autoSoft = false\n            return []"),
    ("M24 taking it down lets go of nothing", "            return hold == .none ? [] : releaseHold()", "            return []"),
    ("M25 a restore takes it for the keyboard", "        case .none:\n            guard onScreen else { return [] }\n            softDismissed = false\n            pendingAutoSoft = false\n            return [.take(automatic: false)]\n        case .automatic:\n            softDismissed = false\n            autoSoft = false\n            hold = .own\n            return [.makeOwn]\n        case .own:\n            autoSoft = false\n            return []",
     "        case .none:\n            guard onScreen else { return [] }\n            softDismissed = false\n            pendingAutoSoft = false\n            return [.take(automatic: true)]\n        case .automatic:\n            softDismissed = false\n            autoSoft = false\n            hold = .own\n            return [.makeOwn]\n        case .own:\n            autoSoft = false\n            return []"),
    ("M26 given back: the keyboard's whenever it is wanted", "        if lastHeld != .none { return lastHeld }\n        return wantsAutomatic ? .automatic : .own",
     "        if wantsAutomatic { return .automatic }\n        return lastHeld != .none ? lastHeld : .own"),
    ("M27 given back: always the person's", "            hold = unpromptedKind", "            hold = .own"),
    ("M28 a keyboard's hold given back with something open is kept", "        if hold == .automatic && !wantsAutomatic { return releaseHold() }", ""),
    ("M29 what was asked ignored: always the keyboard's", "            hold = automatic ? .automatic : .own", "            hold = .automatic"),
    ("M30 a resignation forgets what was held", "            lastHeld = hold\n", ""),
    ("M31 a resignation keeps the hold", "        hold = .none\n        autoSoft = false\n        pendingAutoSoft = false\n    }",
     "        autoSoft = false\n        pendingAutoSoft = false\n    }"),
    # Mac text focus auto soft keyboard (kind 48)
    ("F1 soft auto-show ignores hardware keyboard", "var wantsSoftAutomatic: Bool { onScreen && !attached && takers.isEmpty && textFocus && !softDismissed }",
     "var wantsSoftAutomatic: Bool { onScreen && takers.isEmpty && textFocus && !softDismissed }"),
    ("F2 soft auto-show ignores takers", "var wantsSoftAutomatic: Bool { onScreen && !attached && takers.isEmpty && textFocus && !softDismissed }",
     "var wantsSoftAutomatic: Bool { onScreen && !attached && textFocus && !softDismissed }"),
    ("F3 soft auto-show ignores manual dismiss override", "var wantsSoftAutomatic: Bool { onScreen && !attached && takers.isEmpty && textFocus && !softDismissed }",
     "var wantsSoftAutomatic: Bool { onScreen && !attached && takers.isEmpty && textFocus }"),
    ("F4 repeated textFocus clears manual dismiss", "        guard now != textFocus else { return [] }\n", ""),
    ("F5 leaving focus does not dismiss auto-soft", "        if hold == .own && autoSoft {\n            autoSoft = false\n            return releaseHold()\n        }", ""),
    ("F6 leaving focus dismisses manually opened keyboard too", "        if hold == .own && autoSoft {\n            autoSoft = false\n            return releaseHold()\n        }",
     "        if hold == .own {\n            autoSoft = false\n            return releaseHold()\n        }"),
    ("F7 Keyboard button dismiss does not set softDismissed", "            if textFocus { softDismissed = true }\n", ""),
    ("F8 external dismiss during focus does not set softDismissed", "        if external && hold == .own && textFocus && takers.isEmpty && !attached {\n            softDismissed = true\n        }\n", ""),
    ("F9 hardware attach over auto-soft does not switch to invisible hold", "            if hold == .own && autoSoft && wantsAutomatic {\n                autoSoft = false\n                hold = .automatic\n                return [.makeAutomatic]\n            }\n", ""),
    ("F10 hardware detach while focused drops instead of handing over to auto-soft", "            if wantsSoftAutomatic {\n                autoSoft = true\n                hold = .own\n                return [.makeOwn]\n            }\n", ""),
    # PointerScroll (#130, PR #217)
    ("P1 a pointer scroll goes where the pan's location ran to", "        at = CGPoint(x: location.x - reading.x, y: location.y - reading.y)\n",
     "        at = location\n"),
    ("P2 a pointer scroll's place follows its readings", "        total = CGPoint(x: total.x + reading.x, y: total.y + reading.y)\n",
     "        total = CGPoint(x: total.x + reading.x, y: total.y + reading.y)\n        at = CGPoint(x: at.x + reading.x, y: at.y + reading.y)\n"),
    ("P3 the first reading lost (a lone notch sends nothing)", "        total = reading\n", "        total = .zero\n"),
    ("P4 the readings not added up (each taken as the total so far)", "        total = CGPoint(x: total.x + reading.x, y: total.y + reading.y)\n",
     "        total = reading\n"),
    ("P5 the first reading added to the pointer, not taken off", "        at = CGPoint(x: location.x - reading.x, y: location.y - reading.y)\n",
     "        at = CGPoint(x: location.x - reading.x, y: location.y + reading.y)\n"),
    ("P6 a new scroll keeps the last one's total", "        total = reading\n",
     "        total = CGPoint(x: total.x + reading.x, y: total.y + reading.y)\n"),
]
caught = 0
for name, old, new in MUTANTS:
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    src = os.path.join(OUT, "HardwareKeyboardPolicy.swift")
    open(src, "w").write(orig.replace(old, new, 1))
    exe = os.path.join(OUT, "mutant")
    if os.path.exists(exe): os.remove(exe)
    c = subprocess.run(["swiftc", "-O", src, os.path.join(SP, "main.swift"), "-o", exe], capture_output=True, text=True)
    if c.returncode != 0:
        print(f"{name}: did not compile: {c.stderr.strip().splitlines()[0] if c.stderr.strip() else ''}"); continue
    r = subprocess.run([exe], capture_output=True, text=True, timeout=600)
    failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
    if r.returncode != 0:
        caught += 1
        print(f"{name}: caught ({len(failed)} FAIL lines; first: {failed[0][:160] if failed else ''})")
    else:
        print(f"{name}: SURVIVED")
print(f"{caught} of {len(MUTANTS)} mutants caught")
