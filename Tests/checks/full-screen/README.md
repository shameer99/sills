# `full-screen`

**Checks:** full screen's rules (docs/full-screen-plan.md): the swipe in's start at the left edge (EdgeSwipe) by cases at each number's edge, sampled at 60, 120 and 240 Hz, and 30,000 seeded random strokes against an independent model and invariants; the rest of the swipe in (EdgeReveal); the swipe in's preview cut (`RevealCut` with `StreamLayout`: right of the 56 pt leading rail in landscape, over the controls block in portrait across iPhones, Duo cover, Duo inner flat and laptop pose, and iPads, plus edge cases and 5,000 random lines); the pointer's dwell at the edge (EdgeDwell); when full screen is offered and must show; Shake to Show Controls and Shake to Undo; Settings rows' place; the hint's count; the picture's room for each choice; the levels and the words

**Compiles:** `iOSClient/FullScreenPolicy.swift` with `iOSClient/DuoPosture.swift` and `iOSClient/PhonePortraitLayout.swift` (`swiftc`), whose layouts the preview's cut is checked against
