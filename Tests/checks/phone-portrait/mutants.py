"""Mutants of iOSClient/PhonePortraitLayout.swift (StreamLayout): each changes it in one place and must fail
the check (main.swift). usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))
OUT = os.path.join(ROOT, ".build", "checks", "phone-portrait")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/PhonePortraitLayout.swift")
DUO = os.path.join(ROOT, "iOSClient/DuoPosture.swift")
orig = open(SRC).read()
MUTANTS = {
    "M1 16:9 default aspect": ("static let defaultAspect: CGFloat = 1.6", "static let defaultAspect: CGFloat = 16.0 / 9.0"),
    "M2 minTrackpad 50": ("static let minTrackpad: CGFloat = 75", "static let minTrackpad: CGFloat = 50"),
    "M3 minTrackpad 100": ("static let minTrackpad: CGFloat = 75", "static let minTrackpad: CGFloat = 100"),
    "M4 railWidth 72": ("static let railWidth: CGFloat = 56", "static let railWidth: CGFloat = 72"),
    "M5 landscapePictureShare 0.70": ("static let landscapePictureShare: CGFloat = 0.55", "static let landscapePictureShare: CGFloat = 0.70"),
    "M6 keyboardGap 0": ("static let keyboardGap: CGFloat = 6", "static let keyboardGap: CGFloat = 0"),
    "M7 barHeight 64": ("static let barHeight: CGFloat = 54", "static let barHeight: CGFloat = 64"),
    "M8 capHeight 36": ("static let capHeight: CGFloat = 44", "static let capHeight: CGFloat = 36"),
    "M9 wideKeysMinWidth 700": ("static let wideKeysMinWidth: CGFloat = 544", "static let wideKeysMinWidth: CGFloat = 700"),
    "M10 minStripWidth 200": ("static let minStripWidth: CGFloat = 64", "static let minStripWidth: CGFloat = 200"),
    "M11 kb >= H treated as up": ("let kb: CGFloat? = keyboardTop.flatMap { ($0.isFinite && $0 < H) ? max(0, $0) : nil }",
                                  "let kb: CGFloat? = keyboardTop.flatMap { $0.isFinite ? max(0, $0) : nil }"),
    "M12 book pose vertical fold ignored": ("guard l - Self.side - Self.rowGap >= 44, W - Self.side - (r + Self.rowGap) >= 44 else { return nil }",
                                            "return nil"),
    "M13 landscape kb up keeps rail": ("self.rail = nil\n                self.appsButton = nil",
                                       "self.rail = CGRect(x: 0, y: 0, width: Self.railWidth, height: H)\n                self.appsButton = nil"),
    "M14 landscape dim covers rail": ("self.dim = [CGRect(x: railRect.maxX, y: 0, width: max(0, W - railRect.maxX), height: H)]",
                                      "self.dim = [CGRect(x: 0, y: 0, width: W, height: H)]"),
    "M15 laptop kb lift ignored": ("let floor = foldBounds.map { min(kb, $0.top) } ?? kb\n                if floor >= Self.portraitFixedUp",
                                   "let floor = kb\n                if floor >= Self.portraitFixedUp"),
    "M16 laptop short kb always lifted": ("if let f = foldBounds, kb - f.bottom >= Self.belowFoldMinForKeyboard {",
                                          "if false, let f = foldBounds, kb - f.bottom >= Self.belowFoldMinForKeyboard {"),
    "M17 portrait kb up picture ignores minTrackpad": ("let maxPicH = floor - Self.portraitFixedUp - Self.minTrackpad",
                                                       "let maxPicH = floor - Self.portraitFixedUp"),
    "M18 portrait kb down ignores fold": ("if let f = foldBounds {\n            // Laptop pose, keyboard down:",
                                          "if false, let f = foldBounds {\n            // Laptop pose, keyboard down:"),
    "M19 portrait dim covers bar": ("self.dim = [CGRect(x: 0, y: 0, width: W, height: barRect.minY),",
                                    "self.dim = [CGRect(x: 0, y: 0, width: W, height: barRect.maxY),"),
    "M20 aspectFit rounds up": ("let tall = (room.width / a).rounded(.down)",
                                "let tall = (room.width / a).rounded(.up)"),
    "M21 aspectFit skips horizontal centering": ("let x = room.minX + ((room.width - w) / 2).rounded(.down)",
                                                 "let x = room.minX"),
    "M22 split extra gap": ("(row.width - CGFloat(count - 1) * gap)", "(row.width - CGFloat(count) * gap)"),
    "M23 trackpadSpan uses height": ("self.trackpadSpan = padRect.width / a", "self.trackpadSpan = padRect.height"),
    "M24 viewportSize ignores landscape pictureRoom": ("if base.isLandscape || fold.horizontalBand != nil {\n            return base.pictureRoom.size",
                                                       "if false {\n            return base.pictureRoom.size"),
    "M25 keyboardTop ignores settling fallback": ("return glass.top ?? localReported", "return glass.top"),
    "M26 keyboardTop ignores origin offset": ("let localReported = reported.minY - origin.y", "let localReported = reported.minY"),
    "M27 extreme floor drops trackpad below 75": ("let pad = CGRect(x: Self.side, y: padTop, width: rowWidth, height: Self.minTrackpad)",
                                                  "let pad = CGRect(x: Self.side, y: padTop, width: rowWidth, height: 50)"),
    "M28 portrait bar omits Menus always": ("let menus: CGRect? = hasMenus && (menusCandidate.minX - gap - stripStart >= minStripWidth) ? menusCandidate : nil",
                                            "let menus: CGRect? = nil"),
}
caught = 0
for name, (old, new) in MUTANTS.items():
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    path = os.path.join(OUT, "mutant.swift")
    open(path, "w").write(orig.replace(old, new))
    b = subprocess.run(["swiftc", "-O", DUO, path, os.path.join(SP, "main.swift"), "-o", os.path.join(OUT, "mutant")],
                       capture_output=True, text=True)
    if b.returncode != 0:
        print(f"{name}: DOES NOT COMPILE\n{b.stderr[:600]}"); continue
    r = subprocess.run([os.path.join(OUT, "mutant")], capture_output=True, text=True, timeout=300)
    failed = [l[5:] for l in r.stdout.splitlines() if l.startswith("FAIL")]
    ok = r.returncode != 0
    caught += ok
    print(f"{'caught' if ok else 'MISSED'} {name}: {len(failed)} failing, e.g. {[f[:100] for f in failed[:2]]}")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
