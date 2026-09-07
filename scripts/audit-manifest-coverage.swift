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
    // Targets without an explicit path fall back to SwiftPM's conventional layout,
    // which this package does not use; skipping them keeps the audit honest rather
    // than silently passing a directory it never looked at.
    guard let path = target["path"] as? String else { continue }

    let sources = target["sources"] as? [String] ?? []
    let excludes = target["exclude"] as? [String] ?? []
    let listed = Set(sources + excludes)

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

if audited == 0 {
    FileHandle.standardError.write(Data("audit: found no .swift files to check — the manifest or layout changed\n".utf8))
    exit(2)
}

if failures.isEmpty {
    print("audit: \(audited) .swift files, all accounted for in Package.swift")
    exit(0)
}

for failure in failures {
    print("::error::\(failure)")
}
FileHandle.standardError.write(Data("audit: \(failures.count) of \(audited) file(s) unaccounted for. Add each to sources: if it is portable, or to exclude: deliberately.\n".utf8))
exit(1)
