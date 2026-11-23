# `text-focus`

**Checks:** Mac Accessibility editable text-field classification (`TextFocusRule.classify` and `needsValueSettable`: text roles, secure/search subroles, editable web content, disabled/read-only/non-text elements), debounced transition tracking (`TextFocusRule.Tracker`), and kind 48 `TextFocus` wire encode/decode (including `WindowList.textFocus` and older-client skip)

**Compiles:** `Sources/SillHost/TextFocusRule.swift` with `Sources/StreamProtocol/*.swift` (`module.txt`)
