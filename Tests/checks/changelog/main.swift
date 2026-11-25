import Foundation

var passed = 0, failed = 0
func check(_ ok: Bool, _ what: String) {
    if ok { passed += 1; print("ok: \(what)") } else { failed += 1; print("FAIL: \(what)") }
}

// The changelog.
let releases = Changelog.releases
check(!releases.isEmpty, "there is a release")
for (a, b) in zip(releases, releases.dropFirst()) {
    check((Int(a.build) ?? 0) > (Int(b.build) ?? 0), "builds fall: \(a.label) before \(b.label)")
    check(a.date >= b.date, "dates never rise: \(a.date) before \(b.date)")
}
let day = try! NSRegularExpression(pattern: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
for r in releases {
    check(day.firstMatch(in: r.date, range: NSRange(r.date.startIndex..., in: r.date)) != nil, "\(r.label): a day, yyyy-mm-dd (\(r.date))")
    check(!r.ours.isEmpty || !r.upstream.isEmpty, "\(r.label): something in it")
    check((r.ours + r.upstream).allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }, "\(r.label): no blank line")
    check(Set(r.ours + r.upstream).count == (r.ours + r.upstream).count, "\(r.label): no line twice")
    check(r.label == "\(r.version) (\(r.build))", "\(r.label): its label")
}
check(releases.contains { !$0.upstream.isEmpty }, "an upstream item somewhere")
if CommandLine.arguments.count > 1, let project = try? String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8) {
    func setting(_ key: String) -> Set<String> {
        let re = try! NSRegularExpression(pattern: "\(key) = ([^;]+);")
        return Set(re.matches(in: project, range: NSRange(project.startIndex..., in: project)).compactMap {
            Range($0.range(at: 1), in: project).map { String(project[$0]) }
        })
    }
    check(setting("CURRENT_PROJECT_VERSION") == [releases.first?.build ?? ""], "the newest release is the project's build (\(setting("CURRENT_PROJECT_VERSION")))")
    check(setting("MARKETING_VERSION") == [releases.first?.version ?? ""], "the newest release is the project's version (\(setting("MARKETING_VERSION")))")
} else {
    check(false, "the project file given and read")
}

// SettingsTransfer.
typealias T = SettingsTransfer
check(T.scheme(forSiblingOf: "me.saffer.sill.e") == "sill", "SillE sends to SillS")
check(T.scheme(forSiblingOf: "me.saffer.sill.FQ46J98RC9") == "sille", "SillS sends to SillE")
check(T.scheme(forSiblingOf: "me.saffer.sill") == "sille", "Sill sends to SillE")
let all: [String: Any] = ["Sill.savedMacs": Data([1, 2, 3]), "Sill.keyboardHints": Data((0...255).map { UInt8($0) } + (0...255).map { UInt8(255 - $0) }), "Sill.reverseScroll": true, "Sill.connectionStyle": "list",
                          "Sill.macGroups": ["a", "b"], "SillConnect": "1.2.3.4:5", "AppleLanguages": ["en"], "other": 1]
let picked = T.pick(all)
check(Set(picked.keys) == ["Sill.savedMacs", "Sill.keyboardHints", "Sill.reverseScroll", "Sill.connectionStyle", "Sill.macGroups"], "only Sill. keys picked (\(picked.keys.sorted()))")
if let link = T.link(picked, scheme: "sille") {
    check(link.scheme == "sille" && link.host == "settings", "the link: sille://settings (\(link.absoluteString.prefix(40)))")
    let query = link.query ?? ""
    check(!query.contains("+") && !query.contains("/") && query.filter({ $0 == "=" }).count == 1, "URL-safe: no + or / and only the query's =")
    let back = T.settings(from: link)
    check(back?["Sill.savedMacs"] as? Data == Data([1, 2, 3]), "data back")
    check(back?["Sill.reverseScroll"] as? Bool == true, "a Boolean back")
    check(back?["Sill.connectionStyle"] as? String == "list", "a string back")
    check(back?["Sill.macGroups"] as? [String] == ["a", "b"], "an array back")
    check(back?.count == 5, "nothing more back")
    check(back?["Sill.keyboardHints"] as? Data == all["Sill.keyboardHints"] as? Data, "every byte back")
    let other = URL(string: link.absoluteString.replacingOccurrences(of: "sille://settings", with: "sille://pair"))!
    check(T.settings(from: other) == nil, "the same data under another link (sille://pair) is not settings")
} else {
    check(false, "a link made")
}
check(T.link([:], scheme: "sille") == nil, "nothing to send: no link")
check(T.link(["Sill.big": Data(count: 60_000)], scheme: "sille") == nil, "too large: no link")
check(T.settings(from: URL(string: "sill://pair?code=123456&host=1.2.3.4")!) == nil, "a pairing link is not settings")
check(T.settings(from: URL(string: "sille://settings?d=abc")!) == nil, "a damaged link refused (not a plist)")
check(T.settings(from: URL(string: "sille://settings")!) == nil, "no data: refused")
if let foreign = try? PropertyListSerialization.data(fromPropertyList: ["AppleLanguages": ["fr"]], format: .binary, options: 0) {
    let text = foreign.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    check(T.settings(from: URL(string: "sille://settings?d=\(text)")!) == nil, "a link of other keys only: refused")
}

print("changelog: \(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
