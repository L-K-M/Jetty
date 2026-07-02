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

    /// Folds a string so matching is case-, diacritic-, and width-insensitive:
    /// "cafe" matches "Café", "resume" matches "Résumé", "n" matches "ñ", and a
    /// full-width "Ａ" matches "A" — the default behavior in Spotlight/Alfred/Raycast
    /// (H4).
    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                  locale: .current)
    }

    /// A match score (higher = better), or `nil` when `query` isn't a subsequence of
    /// `candidate` (case-, diacritic-, and width-insensitive). Exact/prefix matches and
    /// matches that start on word boundaries (after a space, `-`, `_`, or a case bump)
    /// score higher.
    static func score(_ query: String, _ candidate: String) -> Int? {
        let queryFolded = fold(query)
        guard !queryFolded.isEmpty else { return 0 }

        // Exact / prefix fast paths, folded on both sides.
        let candFolded = fold(candidate)
        if candFolded == queryFolded { return 1000 }
        if candFolded.hasPrefix(queryFolded) { return 800 - (candidate.count - query.count) }

        // Fold each character independently so the folded arrays stay index-aligned
        // with the original `cand` chars — the word-boundary / camelCase bonuses read
        // the *original* neighbors, and whole-string folding could change the length
        // (ligatures) and break that alignment. Diacritic/width folds are 1:1 in
        // practice, so per-character folding matches the whole-string fast paths.
        let cand = Array(candidate)
        let foldedCand = cand.map { fold(String($0)) }
        let foldedQuery = Array(query).map { fold(String($0)) }
        guard foldedQuery.count <= foldedCand.count else { return nil }

        var qi = 0
        var score = 0
        var lastMatch = -2
        for ci in 0..<foldedCand.count where qi < foldedQuery.count {
            if foldedCand[ci] == foldedQuery[qi] {
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
        guard qi == foldedQuery.count else { return nil }
        // Prefer shorter candidates among equal matches.
        return score - candidate.count / 4
    }

    /// Wraps a selection index by `delta` over `count` items (for ↑/↓ in the menu).
    static func nextIndex(current: Int, delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((current + delta) % count + count) % count
    }
}
