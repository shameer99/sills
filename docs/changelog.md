# The changelog (SillS fork)

A tap on the version line ("Sill 0.6.3 (8)") at the bottom of the Settings panel or the connect screen
opens What's New: `ChangelogView` (iOSClient/ContentView.swift) drawing `Changelog.releases`
(iOSClient/Changelog.swift), newest first. That array is the one source; nothing else lists changes.

Each release has two lists:

- **Our changes** (`ours`): this fork's own work, in plain words, one line each.
- **From upstream** (`upstream`): what a pull or merge from upstream Sill (saffer's `main`) brought.

## The rules

1. Every build handed out (OTA, TestFlight) adds its release at the top first, with the version and build
   the Xcode project says (MARKETING_VERSION, CURRENT_PROJECT_VERSION). `Tests/checks/changelog` fails
   when the newest release and the project disagree, so a bumped build without an entry does not pass.
2. **Any pull or merge from upstream** adds one line per merged upstream pull request it brings to that
   release's `upstream` list, with its number (`"Host: follows macOS's own tab switches (#399)."`), and
   names the upstream commit it is at. Find them with
   `git log --merges --format='%h %s' <last upstream commit>..upstream/main`.
3. Lines are what a person notices, not how it was built.

SillE (me.saffer.sill.e, builds 8) was a separate app for trying the redesign; build 9 folds it into SillS
and drops the settings copy between the two (SettingsTransfer.swift).
