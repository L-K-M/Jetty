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
    /// True while a valid currency query is waiting for its first rate table.
    @Published private(set) var currencyLoading = false
    /// A valid ISO code for which the current provider returned no rate.
    @Published private(set) var currencyUnsupported: String?
    /// Set when the query parses as a currency conversion but no rates are loaded
    /// (offline / failed fetch). Shown as an inline banner that owns Return, so the
    /// query is never silently leaked to a web search (FAB-B12).
    @Published private(set) var currencyUnavailable = false
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

    /// Recents captured once per menu show (`snapshotRecents`). Re-reading and
    /// JSON-decoding UserDefaults on every keystroke is per-key waste, and recents
    /// can't change while the menu is open except through the menu's own launches.
    private var recentsSnapshot: [AppSearchItem]?

    /// Captures the recents for this showing of the menu — call on every show.
    func snapshotRecents() {
        recentsSnapshot = recentsProvider?()
        recompute()
    }

    private var currencyCancellable: AnyCancellable?

    init(appIndex: AppIndex) {
        self.appIndex = appIndex
        cancellable = appIndex.$apps
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.recompute() }
        // Recompute when currency rates arrive so a pending conversion fills in (ND-9).
        currencyCancellable = Publishers.CombineLatest(CurrencyService.shared.$rates,
                                                        CurrencyService.shared.$fetchState)
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
                                           recents: recentsSnapshot ?? recentsProvider?() ?? []).prefix(maxResults))
        if let previouslySelectedID, let idx = results.firstIndex(where: { $0.id == previouslySelectedID }) {
            selectedIndex = idx
        } else if selectedIndex >= results.count {
            selectedIndex = 0
        }
    }

    /// A currency conversion result string, when the query parses as one and the
    /// rates for both currencies are loaded (ND-9). Also maintains
    /// `currencyUnavailable`: when the query *parses* as currency but no rates are
    /// loaded at all, the menu must show a "rates unavailable" banner instead of
    /// silently falling through to a web search of the query (FAB-B12).
    private func computeCurrency() -> String? {
        currencyLoading = false
        currencyUnsupported = nil
        currencyUnavailable = false
        guard calculation == nil, conversion == nil,
              let parsed = CurrencyService.parseQuery(query) else { return nil }
        guard CurrencyService.supports(parsed.from), CurrencyService.supports(parsed.to) else {
            return nil
        }
        if parsed.from == "USD", parsed.to == "USD" {
            return Self.formatCurrency(parsed.amount, code: parsed.to)
        }
        let service = CurrencyService.shared
        // Refresh stale rates only after explicit currency intent. Existing rates can
        // still produce an immediate result while the coalesced refresh runs.
        service.ensureFresh()
        if service.rates.isEmpty {
            currencyLoading = service.fetchState != .failed
            currencyUnavailable = service.fetchState == .failed
            return nil
        }
        guard service.known(parsed.from), service.known(parsed.to),
              let value = service.convert(amount: parsed.amount, from: parsed.from, to: parsed.to)
        else {
            currencyUnsupported = !service.known(parsed.from) ? parsed.from : parsed.to
            return nil
        }
        return Self.formatCurrency(value, code: parsed.to)
    }

    /// Formats a converted amount as money — currency symbol and the currency's own
    /// decimal convention (2 for EUR, 0 for JPY) — instead of the unit converter's
    /// 4-decimals-plus-ISO-code (M12). Formatters are cached per currency code:
    /// building a NumberFormatter is one of the pricier Foundation operations and
    /// this runs per keystroke (main-thread only).
    static func formatCurrency(_ value: Double, code: String) -> String {
        let formatter = currencyFormatters[code] ?? {
            let f = NumberFormatter()
            f.numberStyle = .currency
            f.currencyCode = code
            currencyFormatters[code] = f
            return f
        }()
        return formatter.string(from: NSNumber(value: value)) ?? "\(UnitConverter.format(value)) \(code)"
    }

    private static var currencyFormatters: [String: NumberFormatter] = [:]

    /// The trimmed query to offer as a web search (nil when empty).
    var webSearchQuery: String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Pure ranking: an empty query lists recents first (then the rest, de-duplicated);
    /// a non-empty query is fuzzy-ranked over all apps. `apps` must be in `AppIndex`
    /// order — already name-sorted — so the empty path preserves it instead of paying
    /// for a second full ICU sort on every keystroke (FAB-P4 follow-up). Unit-tested.
    static func rankedResults(query: String, apps: [AppSearchItem],
                              recents: [AppSearchItem]) -> [AppSearchItem] {
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AppSearch.rank(query, in: apps)
        }
        let recentIDs = Set(recents.map(\.id))
        return recents + apps.filter { !recentIDs.contains($0.id) }
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

    /// Pointer (hover) selection. A hover that visibly moves the highlight is as
    /// explicit a gesture as an arrow key, so it must also set `userMovedSelection`
    /// — otherwise Return runs a matched command instead of the highlighted row
    /// (FAB-B7).
    func selectByPointer(_ index: Int) {
        guard results.indices.contains(index) else { return }
        userMovedSelection = true
        selectedIndex = index
    }

    /// The Return key. Priority:
    /// 1. An app the user explicitly arrow-selected — never hijacked (F-H4).
    /// 2. A calc/conversion/currency banner — copy it, the universal "use this answer"
    ///    gesture, instead of leaking the query to a web search (H2).
    /// 3. A currency query whose rates are unavailable — retry the fetch and stay
    ///    put; never leak the query to a web search (FAB-B12).
    /// 4. A matched quick toggle (its row advertises "⏎ run").
    /// 5. Otherwise the selected app, then a web search (ND-9 / BUG-5).
    func activateSelection() {
        if userMovedSelection, results.indices.contains(selectedIndex) {
            onLaunch?(results[selectedIndex]); return
        }
        if let calculation { onCopyValue?(calculation.value); return }
        if let conversion { onCopyValue?(conversion.value); return }
        if let currency { onCopyValue?(currency); return }
        if currencyLoading { return }
        if currencyUnavailable { CurrencyService.shared.ensureFresh(force: true); return }
        if currencyUnsupported != nil { return }
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
