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
    /// An inline unit conversion (e.g. `10 km in miles`), else `nil` (ND-9).
    @Published private(set) var conversion: UnitConverter.Result?
    /// An inline currency conversion (e.g. `100 usd to eur`), else `nil` (ND-9).
    @Published private(set) var currency: String?
    /// A matched quick toggle (e.g. typing "dark"), else `nil` (ND-9).
    @Published private(set) var command: MenuCommand?
    @Published var selectedIndex: Int = 0

    let maxResults = 12

    private let appIndex: AppIndex
    private var cancellable: AnyCancellable?

    var onLaunch: ((AppSearchItem) -> Void)?
    var onRunPower: ((PowerCommand) -> Void)?
    var onClose: (() -> Void)?
    /// Opens a web search for the query when there are no app results (ND-9).
    var onWebSearch: ((String) -> Void)?
    /// Runs a matched quick toggle (ND-9).
    var onRunCommand: ((MenuCommand) -> Void)?
    /// Supplies recently-launched apps to surface first on an empty query (MF-5).
    var recentsProvider: (() -> [AppSearchItem])?

    private var currencyCancellable: AnyCancellable?

    init(appIndex: AppIndex) {
        self.appIndex = appIndex
        cancellable = appIndex.$apps
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.recompute() }
        // Recompute when currency rates arrive so a pending conversion fills in (ND-9).
        currencyCancellable = CurrencyService.shared.$rates
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.recompute() }
        recompute()
    }

    func recompute() {
        calculation = ExpressionEvaluator.evaluate(query)
        conversion = (calculation == nil) ? UnitConverter.convert(query) : nil
        currency = computeCurrency()
        command = MenuCommand.match(query)
        results = Array(Self.rankedResults(query: query, apps: appIndex.apps,
                                           recents: recentsProvider?() ?? []).prefix(maxResults))
        if selectedIndex >= results.count { selectedIndex = 0 }
    }

    /// A currency conversion result string, when the query parses as one and the
    /// rates for both currencies are loaded (ND-9).
    private func computeCurrency() -> String? {
        guard calculation == nil, conversion == nil,
              let parsed = CurrencyService.parseQuery(query),
              CurrencyService.shared.known(parsed.from), CurrencyService.shared.known(parsed.to),
              let value = CurrencyService.shared.convert(amount: parsed.amount, from: parsed.from, to: parsed.to)
        else { return nil }
        return "\(UnitConverter.format(value)) \(parsed.to)"
    }

    /// The trimmed query to offer as a web search (nil when empty).
    var webSearchQuery: String? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
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

    private var iconCache: [String: NSImage] = [:]

    /// App icon for a result row, cached by item id so fast typing/scrolling doesn't
    /// re-fetch the icon every frame (BUG-10).
    func icon(for item: AppSearchItem) -> NSImage {
        if let cached = iconCache[item.id] { return cached }
        let image = NSWorkspace.shared.icon(forFile: item.url.path)
        iconCache[item.id] = image
        return image
    }

    func moveSelection(_ delta: Int) {
        selectedIndex = AppSearch.nextIndex(current: selectedIndex, delta: delta, count: results.count)
    }

    func activateSelection() {
        if let command {
            onRunCommand?(command)
        } else if results.indices.contains(selectedIndex) {
            onLaunch?(results[selectedIndex])
        } else if let query = webSearchQuery {
            // No app results → Enter searches the web for the query (ND-9).
            onWebSearch?(query)
        }
    }

    func reset() {
        query = ""
        selectedIndex = 0
    }
}
