// Asserts that every .swift file under a SwiftPM target's directory is accounted
// for in Package.swift — named in `sources:`, or excluded in `exclude:`, or living
// under a directory named in either.
//
// This exists because the Linux CI gate it accompanies is a *negative* check: it
// greps SwiftPM's "found N file(s) which are unhandled" warning, so a pass and a
// gate that has quietly stopped firing look identical. If SwiftPM ever rewords or
// drops that diagnostic, the grep matches nothing and reports green. This audit
// asks the manifest directly instead, so it fails closed.
//
// Usage:  swift package dump-package | swift scripts/audit-manifest-coverage.swift

import Foundation

let data = FileHandle.standardInput.readDataToEndOfFile()
guard
    let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
    let targets = root["targets"] as? [[String: Any]]
else {
    FileHandle.standardError.write(Data("audit: could not parse `swift package dump-package` output\n".utf8))
    exit(2)
}

let fm = FileManager.default
var failures: [String] = []
var audited = 0

for target in targets {
    let name = target["name"] as? String ?? "?"
    // A target without an explicit `path` uses SwiftPM's conventional layout. This
    // package declares paths for both targets, but resolving the conventional ones
    // anyway is what keeps the audit fail-closed: skipping such a target would let
    // it report "all accounted for" over a directory it never opened, which is the
    // exact failure this script exists to catch. If neither an explicit path nor a
    // conventional directory resolves, that is a failure, not a skip.
    let conventional = ["Sources/\(name)", "Tests/\(name)", name]
    guard let path = (target["path"] as? String)
        ?? conventional.first(where: { fm.fileExists(atPath: $0) })
    else {
        failures.append("\(name): no explicit path and none of \(conventional) exists — cannot audit this target")
        continue
    }

    let sources = target["sources"] as? [String] ?? []
    let excludes = target["exclude"] as? [String] ?? []
    let listed = Set(sources + excludes)

    // A file in BOTH lists is worse than one in neither: `exclude:` silently wins, so
    // the file is dropped from the build with no diagnostic anywhere, and the symptom
    // surfaces far away as "cannot find X in scope". Caught exactly this way while
    // adding WeatherService in JP-02.
    for duplicate in Set(sources).intersection(excludes).sorted() {
        failures.append("\(path)/\(duplicate) is in BOTH sources: and exclude: for target \(name) — exclude: wins, so it will not build")
    }

    // The commoner form of the same bug: a `sources:` file nested under an excluded
    // *directory*. `exclude: ["Icons"]` swallows `sources: ["Icons/New.swift"]` with
    // no diagnostic, and an exact-match check never sees it. This target still carries
    // eight directory excludes, so it is a live hazard rather than a hypothetical —
    // it is what forced splitting "Common" into per-file entries for the JP-02 shim.
    for source in Set(sources).sorted() {
        for excluded in excludes where source.hasPrefix(excluded + "/") {
            failures.append("\(path)/\(source) is in sources: but sits under the excluded directory \(excluded) for target \(name) — exclude: wins, so it will not build. Split \(excluded) into per-file excludes.")
        }
    }

    guard let walker = fm.enumerator(atPath: path) else {
        failures.append("\(name): cannot read directory \(path)")
        continue
    }

    for case let relative as String in walker where relative.hasSuffix(".swift") {
        audited += 1
        // Covered directly, or by any ancestor directory that is itself listed.
        var candidate = relative
        var covered = false
        while true {
            if listed.contains(candidate) { covered = true; break }
            let parent = (candidate as NSString).deletingLastPathComponent
            if parent.isEmpty || parent == candidate { break }
            candidate = parent
        }
        if !covered {
            failures.append("\(path)/\(relative) is in neither sources: nor exclude: for target \(name)")
        }
    }
}

// Specific failures first: "target X cannot be audited" is far more useful than
// the generic "nothing was checked" it would otherwise be reported as.
if !failures.isEmpty {
    for failure in failures {
        print("::error::\(failure)")
    }
    FileHandle.standardError.write(Data("audit: \(failures.count) problem(s) across \(audited) file(s). Add each unaccounted file to sources: if it is portable, or to exclude: deliberately.\n".utf8))
    exit(1)
}

if audited == 0 {
    FileHandle.standardError.write(Data("audit: found no .swift files to check — the manifest or layout changed\n".utf8))
    exit(2)
}

print("audit: \(audited) .swift files, all accounted for in Package.swift")
exit(0)
