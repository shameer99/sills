import Foundation

/// What changed, newest first, as the Settings panel's version line opens it (a tap on "Sill 0.6.3 (8)").
/// This array is the one source: the sheet draws it as written. Each release has two lists, this fork's own
/// changes (`ours`) and what came from upstream Sill (`upstream`, saffer's main).
///
/// The rule (docs/changelog.md): every build handed out adds its release here first, with the build number the
/// project says (CURRENT_PROJECT_VERSION), and any pull or merge from upstream main adds the upstream items it
/// brings to that release's `upstream` list, one line per merged pull request, in plain words.
///
/// Pure: Foundation only, checked in Tests/checks/changelog.
struct Changelog {
    struct Release: Equatable {
        /// The app version (CFBundleShortVersionString).
        let version: String
        /// The build (CFBundleVersion).
        let build: String
        /// A day, yyyy-mm-dd.
        let date: String
        /// A few words for the release; empty for none.
        let title: String
        let ours: [String]
        let upstream: [String]

        /// "0.6.3 (8)".
        var label: String { "\(version) (\(build))" }
    }

    static let releases: [Release] = [
        Release(version: "0.6.3", build: "9", date: "2026-11-25", title: "SillS: the redesign", ours: [
            "Redesign from SillE folded into SillS; SillE retired.",
            "One app again: Copy Settings to SillE is gone. You can delete SillE.",
        ], upstream: []),
        Release(version: "0.6.3", build: "8", date: "2026-11-25", title: "SillE: the redesign", ours: [
            "SillE: a separate app with its own teal icon, next to SillS, for trying the redesign.",
            "The keyboard is part of the layout: picture, one bar, trackpad, modifier keys, then the keyboard. The trackpad stays usable (at least 75 pt) with the keyboard up, in every orientation.",
            "Hold the keyboard's space bar and drag to move the Mac's pointer.",
            "One bar: Apps, the window thumbnails, Menus, Keyboard and Settings. Desktop is the first row of Apps; text size (Aa) is in Settings.",
            "Landscape: a slim rail on the side instead of the top bar; with the keyboard up the picture sits on the left and a trackpad on the right.",
            "Larger Picture is gone: the new layout replaces it.",
            "Tap the version number in Settings to see this list.",
        ], upstream: []),
        Release(version: "0.6.3", build: "7", date: "2026-11-24", title: "SillS", ours: [
            "While zoomed in, the picture follows the Mac's pointer near its edges.",
            "New name and icon: SillS, to tell it from Sill.",
        ], upstream: []),
        Release(version: "0.6.3", build: "6", date: "2026-11-23", title: "", ours: [
            "A two-finger tap still right-clicks while zoomed in.",
        ], upstream: []),
        Release(version: "0.6.3", build: "5", date: "2026-11-23", title: "", ours: [
            "Two-finger drag pans the zoomed picture on the trackpad.",
        ], upstream: []),
        Release(version: "0.6.3", build: "4", date: "2026-11-22", title: "Zoom and keyboard", ours: [
            "Pinch with two fingers on the trackpad to zoom the picture.",
            "The keyboard comes up by itself when a text field on the Mac takes focus, and goes when it leaves.",
        ], upstream: [
            "Sill 0.6.3 from upstream main (c33d105, 2026-11-20).",
            "Privacy: the Mac locks itself when the last device leaves (#402).",
            "Audio: a staged window's sound is captured on Sill's display, and an ended capture retries by itself (#396).",
            "Host: follows macOS's own tab switches in a streamed window (#399).",
        ]),
    ]
}
