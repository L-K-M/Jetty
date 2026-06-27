import Foundation

/// A searchable application entry (value type, so ranking is pure and testable).
struct AppSearchItem: Equatable, Identifiable {
    let name: String
    let bundleID: String?
    let url: URL

    var id: String { bundleID ?? url.path }
}

/// Pure fuzzy filter/rank for the Jetty Menu's app search. A query matches a name
/// if its characters appear in order (subsequence); a contiguous prefix and
/// word-boundary hits score higher. No state, so it's unit-tested. See PLAN.md §8.2.
enum AppSearch {

    /// Items whose name matches `query`, best first. An empty query returns all
    /// items sorted by name.
    static func rank(_ query: String, in items: [AppSearchItem]) -> [AppSearchItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        let scored = items.compactMap { item -> (AppSearchItem, Int)? in
            guard let s = score(q, item.name) else { return nil }
            return (item, s)
        }
        return scored
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                return $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending
            }
            .map { $0.0 }
    }

    /// A match score (higher = better), or `nil` when `query` isn't a subsequence of
    /// `candidate` (case-insensitive). Exact/prefix matches and matches that start on
    /// word boundaries (after a space, `-`, `_`, or a case bump) score higher.
    static func score(_ query: String, _ candidate: String) -> Int? {
        let lowerQuery = Array(query.lowercased())
        let cand = Array(candidate)
        let lowerCand = Array(candidate.lowercased())
        guard !lowerQuery.isEmpty else { return 0 }
        guard lowerQuery.count <= lowerCand.count else { return nil }

        // Exact / prefix fast paths.
        let candLower = candidate.lowercased()
        if candLower == query.lowercased() { return 1000 }
        if candLower.hasPrefix(query.lowercased()) { return 800 - (candidate.count - query.count) }

        var qi = 0
        var score = 0
        var lastMatch = -2
        for ci in 0..<lowerCand.count where qi < lowerQuery.count {
            if lowerCand[ci] == lowerQuery[qi] {
                var bonus = 10
                if ci == lastMatch + 1 { bonus += 15 }                 // consecutive run
                if ci == 0 { bonus += 20 }                              // at the start
                else {
                    let prev = cand[ci - 1]
                    if prev == " " || prev == "-" || prev == "_" { bonus += 18 }   // word boundary
                    else if prev.isLowercase && cand[ci].isUppercase { bonus += 12 } // camelCase bump
                }
                score += bonus
                lastMatch = ci
                qi += 1
            }
        }
        guard qi == lowerQuery.count else { return nil }
        // Prefer shorter candidates among equal matches.
        return score - candidate.count / 4
    }

    /// Wraps a selection index by `delta` over `count` items (for ↑/↓ in the menu).
    static func nextIndex(current: Int, delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((current + delta) % count + count) % count
    }
}
