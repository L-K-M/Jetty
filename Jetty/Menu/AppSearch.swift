import Foundation

/// A searchable application entry (value type, so ranking is pure and testable).
/// The folded representations of `name` are precomputed here, once, at construction
/// (i.e. at index/scan time), so `AppSearch.rank` never re-folds candidate names on
/// a keystroke — names only change on `AppIndex.reload()` (FAB-P4).
struct AppSearchItem: Equatable, Identifiable {
    let name: String
    let bundleID: String?
    let url: URL

    /// `name` folded as a whole string, for the exact/prefix fast paths.
    let foldedName: String
    /// The original characters of `name`, index-aligned with `foldedNameChars` —
    /// the word-boundary / camelCase bonuses read the *original* neighbors.
    let nameChars: [Character]
    /// Each character of `name` folded independently. See `AppSearch.score` for why
    /// per-character folding (not whole-string folding) keeps the arrays aligned.
    let foldedNameChars: [String]

    init(name: String, bundleID: String?, url: URL) {
        self.name = name
        self.bundleID = bundleID
        self.url = url
        let chars = Array(name)
        self.nameChars = chars
        self.foldedName = AppSearch.fold(name)
        self.foldedNameChars = chars.map { AppSearch.fold(String($0)) }
    }

    var id: String { bundleID ?? url.path }
}

/// Pure fuzzy filter/rank for the Jetty Menu's app search. A query matches a name
/// if its characters appear in order (subsequence); a contiguous prefix and
/// word-boundary hits score higher. No state, so it's unit-tested. See PLAN.md §8.2.
enum AppSearch {

    /// Items whose name matches `query`, best first. An empty query returns all
    /// items sorted by name.
    ///
    /// The query is tokenized on whitespace so multi-word queries are word-order-
    /// insensitive: "studio visual" finds "Visual Studio Code" (F-L5). Every token
    /// must match (AND); an item's score is the sum of its per-token scores. A
    /// single-token query behaves exactly as a whole-query match did before. Each
    /// token is folded once per call, not once per candidate (FAB-P4 / L6).
    static func rank(_ query: String, in items: [AppSearchItem]) -> [AppSearchItem] {
        let tokens = query.split(whereSeparator: \.isWhitespace).map { FoldedQuery(String($0)) }
        guard !tokens.isEmpty else {
            return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        let scored = items.compactMap { item -> (AppSearchItem, Int)? in
            var total = 0
            for token in tokens {
                guard let s = score(token, against: item) else { return nil }
                total += s
            }
            return (item, total)
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
    /// (H4). Folding is locale-*neutral* (`locale: nil`): a locale-aware fold under
    /// Turkish/Azerbaijani maps "I" to dotless "ı", so "IINA" could never match the
    /// query "iina" (FAB-B11).
    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                  locale: nil)
    }

    /// A query token with its folded forms, computed once per `rank` call so scoring
    /// doesn't re-fold the query for every candidate (FAB-P4).
    private struct FoldedQuery {
        /// Character count of the original token (the prefix score depends on it).
        let count: Int
        /// The whole token folded, for the exact/prefix fast paths.
        let folded: String
        /// Each character folded independently, for the subsequence scan.
        let foldedChars: [String]

        init(_ token: String) {
            count = token.count
            folded = AppSearch.fold(token)
            foldedChars = token.map { AppSearch.fold(String($0)) }
        }
    }

    /// A match score (higher = better), or `nil` when `query` isn't a subsequence of
    /// `candidate` (case-, diacritic-, and width-insensitive). Exact/prefix matches and
    /// matches that start on word boundaries (after a space, `-`, `_`, or a case bump)
    /// score higher.
    ///
    /// Convenience for tests and one-off checks: folds both sides on the spot.
    /// `rank` instead scores against the folds precomputed on `AppSearchItem`.
    static func score(_ query: String, _ candidate: String) -> Int? {
        let nameChars = Array(candidate)
        return score(FoldedQuery(query),
                     nameChars: nameChars,
                     foldedName: fold(candidate),
                     foldedNameChars: nameChars.map { fold(String($0)) })
    }

    private static func score(_ query: FoldedQuery, against item: AppSearchItem) -> Int? {
        score(query, nameChars: item.nameChars,
              foldedName: item.foldedName, foldedNameChars: item.foldedNameChars)
    }

    /// The core scorer. `foldedNameChars` holds each candidate character folded
    /// *independently* so it stays index-aligned with the original `nameChars` —
    /// the word-boundary / camelCase bonuses read the *original* neighbors, and
    /// whole-string folding could change the length (ligatures) and break that
    /// alignment. Diacritic/width folds are 1:1 in practice, so per-character
    /// folding matches the whole-string fast paths.
    private static func score(_ query: FoldedQuery, nameChars: [Character],
                              foldedName: String, foldedNameChars: [String]) -> Int? {
        guard !query.folded.isEmpty else { return 0 }

        // Exact / prefix fast paths, folded on both sides.
        if foldedName == query.folded { return 1000 }
        if foldedName.hasPrefix(query.folded) { return 800 - (nameChars.count - query.count) }

        guard query.foldedChars.count <= foldedNameChars.count else { return nil }

        var qi = 0
        var score = 0
        var lastMatch = -2
        for ci in 0..<foldedNameChars.count where qi < query.foldedChars.count {
            if foldedNameChars[ci] == query.foldedChars[qi] {
                var bonus = 10
                if ci == lastMatch + 1 { bonus += 15 }                 // consecutive run
                if ci == 0 { bonus += 20 }                              // at the start
                else {
                    let prev = nameChars[ci - 1]
                    if prev == " " || prev == "-" || prev == "_" { bonus += 18 }   // word boundary
                    else if prev.isLowercase && nameChars[ci].isUppercase { bonus += 12 } // camelCase bump
                }
                score += bonus
                lastMatch = ci
                qi += 1
            }
        }
        guard qi == query.foldedChars.count else { return nil }
        // Prefer shorter candidates among equal matches.
        return score - nameChars.count / 4
    }

    /// Wraps a selection index by `delta` over `count` items (for ↑/↓ in the menu).
    static func nextIndex(current: Int, delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((current + delta) % count + count) % count
    }
}
