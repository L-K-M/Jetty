import AppKit
import Combine

/// Backing state for the Jetty Menu: the search query, the ranked results, and the
/// keyboard selection. Ranking goes through the pure `AppSearch`. The owning
/// controller's key monitor drives selection/launch so it works on macOS 13+
/// (`onKeyPress` is 14+). See PLAN.md §8.2.
final class JettyMenuModel: ObservableObject {

    @Published var query: String = "" { didSet { recompute() } }
    @Published private(set) var results: [AppSearchItem] = []
    /// An inline calculator result when the query is an arithmetic expression
    /// (e.g. `2+2`), else `nil`. See `ExpressionEvaluator` / improvement ND-1.
    @Published private(set) var calculation: ExpressionEvaluator.Result?
    @Published var selectedIndex: Int = 0

    let maxResults = 12

    private let appIndex: AppIndex
    private var cancellable: AnyCancellable?

    var onLaunch: ((AppSearchItem) -> Void)?
    var onRunPower: ((PowerCommand) -> Void)?
    var onClose: (() -> Void)?
    /// Supplies recently-launched apps to surface first on an empty query (MF-5).
    var recentsProvider: (() -> [AppSearchItem])?

    init(appIndex: AppIndex) {
        self.appIndex = appIndex
        cancellable = appIndex.$apps
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.recompute() }
        recompute()
    }

    func recompute() {
        calculation = ExpressionEvaluator.evaluate(query)
        results = Array(Self.rankedResults(query: query, apps: appIndex.apps,
                                           recents: recentsProvider?() ?? []).prefix(maxResults))
        if selectedIndex >= results.count { selectedIndex = 0 }
    }

    /// Pure ranking: an empty query lists recents first (then the rest, de-duplicated);
    /// a non-empty query is fuzzy-ranked over all apps. Unit-tested.
    static func rankedResults(query: String, apps: [AppSearchItem],
                              recents: [AppSearchItem]) -> [AppSearchItem] {
        guard query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return AppSearch.rank(query, in: apps)
        }
        let recentIDs = Set(recents.map(\.id))
        let rest = AppSearch.rank("", in: apps).filter { !recentIDs.contains($0.id) }
        return recents + rest
    }

    func moveSelection(_ delta: Int) {
        selectedIndex = AppSearch.nextIndex(current: selectedIndex, delta: delta, count: results.count)
    }

    func activateSelection() {
        guard results.indices.contains(selectedIndex) else { return }
        onLaunch?(results[selectedIndex])
    }

    func reset() {
        query = ""
        selectedIndex = 0
    }
}
