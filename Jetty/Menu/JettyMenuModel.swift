import AppKit
import Combine

/// Backing state for the Jetty Menu: the search query, the ranked results, and the
/// keyboard selection. Ranking goes through the pure `AppSearch`. The owning
/// controller's key monitor drives selection/launch so it works on macOS 13+
/// (`onKeyPress` is 14+). See PLAN.md §8.2.
@MainActor
final class JettyMenuModel: ObservableObject {

    @Published var query: String = "" { didSet { recompute() } }
    @Published private(set) var results: [AppSearchItem] = []
    @Published var selectedIndex: Int = 0

    let maxResults = 12

    private let appIndex: AppIndex
    private var cancellable: AnyCancellable?

    var onLaunch: ((AppSearchItem) -> Void)?
    var onRunPower: ((PowerCommand) -> Void)?
    var onClose: (() -> Void)?

    init(appIndex: AppIndex) {
        self.appIndex = appIndex
        cancellable = appIndex.$apps
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.recompute() }
        recompute()
    }

    func recompute() {
        results = Array(AppSearch.rank(query, in: appIndex.apps).prefix(maxResults))
        if selectedIndex >= results.count { selectedIndex = 0 }
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
