# `phone-portrait`

**Checks:** the unified `StreamLayout` across every orientation and device (iPhone SE..Pro Max, iPhone Duo cover and inner displays open flat, laptop pose and book pose, iPad), across keyboard heights (0, 216, 260, 300, 396, and the laptop-pose whole lower half): trackpad never overlaps the keyboard, is never under 75 pt while the keyboard is up (when room permits), modifier row sits above the keyboard, nothing interactive sits on a fold band, picture keeps its aspect ratio, portrait target fractions on Duo cover and inner displays, landscape 56 pt leading rail (keyboard down) and 55%/45% picture+trackpad split (keyboard up, splitting cleanly around the book pose fold), `viewportSize`, and `keyboardTop`.

**Compiles:** `iOSClient/PhonePortraitLayout.swift` with `iOSClient/DuoPosture.swift`
