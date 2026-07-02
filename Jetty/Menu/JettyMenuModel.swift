import AppKit
import Combine

/// Backing state for the Jetty Menu: the search query, the ranked results, and the
/// keyboard selection. Ranking goes through the pure `AppSearch`. The owning
/// controller's key monitor drives selection/launch so it works on macOS 13+
/// (`onKeyPress` is 14+). See PLAN.md §8.2.
final class JettyMenuModel: ObservableObject {

    @Published var query: String = "" { didSet { userMovedSelection = false; recompute() } }
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
    /// Whether the user has explicitly arrow-keyed the selection since the query last
    /// changed. When they have, Return launches that app rather than being hijacked by a
    /// matched command or a calc banner (F-H4). Reset on every query edit.
    private(set) var userMovedSelection = false

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
    /// Copies a calc/conversion/currency result to the clipboard on Return (H2).
    var onCopyValue: ((String) -> Void)?
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
        // Preserve the selection across a recompute by *identity*, not position, so
        // narrowing the results (or an async apps/rates update) doesn't jump the
        // highlight back to row 0 (M18).
        let previouslySelectedID = results.indices.contains(selectedIndex) ? results[selectedIndex].id : nil
        calculation = ExpressionEvaluator.evaluate(query)
        conversion = (calculation == nil) ? UnitConverter.convert(query) : nil
        currency = computeCurrency()
        command = MenuCommand.match(query)
        results = Array(Self.rankedResults(query: query, apps: appIndex.apps,
                                           recents: recentsProvider?() ?? []).prefix(maxResults))
        if let previouslySelectedID, let idx = results.firstIndex(where: { $0.id == previouslySelectedID }) {
            selectedIndex = idx
        } else if selectedIndex >= results.count {
            selectedIndex = 0
        }
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
        userMovedSelection = true
        selectedIndex = AppSearch.nextIndex(current: selectedIndex, delta: delta, count: results.count)
    }

    /// The Return key. Priority:
    /// 1. An app the user explicitly arrow-selected — never hijacked (F-H4).
    /// 2. A calc/conversion/currency banner — copy it, the universal "use this answer"
    ///    gesture, instead of leaking the query to a web search (H2).
    /// 3. A matched quick toggle (its row advertises "⏎ run").
    /// 4. Otherwise the selected app, then a web search (ND-9 / BUG-5).
    func activateSelection() {
        if userMovedSelection, results.indices.contains(selectedIndex) {
            onLaunch?(results[selectedIndex]); return
        }
        if let calculation { onCopyValue?(calculation.value); return }
        if let conversion { onCopyValue?(conversion.value); return }
        if let currency { onCopyValue?(currency); return }
        if let command { onRunCommand?(command); return }
        if results.indices.contains(selectedIndex) { onLaunch?(results[selectedIndex]); return }
        if let query = webSearchQuery { onWebSearch?(query) }
    }

    /// Directly launches the app at `index` — used by a row *click*, which targets a
    /// specific app and must never be hijacked by a matched command (BUG-5 follow-up).
    func launch(at index: Int) {
        guard results.indices.contains(index) else { return }
        onLaunch?(results[index])
    }

    func reset() {
        query = ""
        selectedIndex = 0
    }
}
