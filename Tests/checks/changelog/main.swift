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

print("changelog: \(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
