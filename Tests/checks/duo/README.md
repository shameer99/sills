# `duo`

**Checks:** the iPhone Duo's posture and fold rules (docs/iphone-duo-plan.md): the poses as the iOS 27.1 simulator reported them, the fold's band in the screen's own space, `crease`, `paneAspect`, a tour card on one page (`offTheFold`, `pageWidth`), the connect column and its room above the laptop pose's fold (`columnX`, `leadingPage`, `roomAboveFold`), the window lights (`lightsMenu`), the stream screen's status bar, the hinge from the fold before its first report, the harness's stand-in and the displays' safe areas, and `KeyboardFrameMonitor`'s keyboard glass reading rules (`plausibleGlass`, `keyboardGlass`, `keyboardLook`, `keyboardLookIsOff`, `keyboardRowFits`, `keyboardReportIsReading`, look/reload schedules, settling, stale readings, and learned keyboard hints)

**Compiles:** `iOSClient/DuoPosture.swift`
