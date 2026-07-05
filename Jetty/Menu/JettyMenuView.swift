import SwiftUI
import AppKit

/// The Windows-Start-style launcher panel: a search field over installed apps, a
/// results list, and a power-command row. Liquid Glass background to match the dock.
/// See PLAN.md §8.2.
struct JettyMenuView: View {
    @ObservedObject var model: JettyMenuModel
    @ObservedObject var preferences: Preferences
    @FocusState private var searchFocused: Bool
    /// Set when a hover changes the selection so the results list doesn't auto-scroll
    /// under the cursor — only keyboard navigation scrolls (M11).
    @State private var suppressScroll = false

    var body: some View {
        VStack(spacing: 0) {
            searchField
            if let calculation = model.calculation {
                Divider().opacity(0.5)
                calculationRow(calculation)
            }
            if let conversion = model.conversion {
                Divider().opacity(0.5)
                copyRow(symbol: "ruler", value: conversion.value)
            }
            if let currency = model.currency {
                Divider().opacity(0.5)
                copyRow(symbol: "banknote", value: currency)
            }
            if model.currencyUnavailable {
                Divider().opacity(0.5)
                currencyUnavailableRow
            }
            if let command = model.command {
                Divider().opacity(0.5)
                commandRow(command)
            }
            Divider().opacity(0.5)
            resultsOrEmptyState
            // Always offer a web search for a non-empty query — not only when nothing
            // matched — so "world cup 2026" is reachable even when two apps match (M11).
            if let query = model.webSearchQuery {
                Divider().opacity(0.5)
                webSearchRow(query)
            }
            Divider().opacity(0.5)
            powerRow
        }
        .frame(width: 420, height: 460)
        .background(
            GlassBackground(material: preferences.material,
                            tint: preferences.tintColor,
                            gradientColor: preferences.gradientColor,
                            gradientAngle: preferences.gradientAngle,
                            opacity: max(preferences.backgroundOpacity, 0.7),
                            cornerRadius: 20)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search apps…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($searchFocused)
                .onAppear { searchFocused = true }
        }
        .padding(14)
    }

    /// The inline calculator banner shown when the query is an arithmetic
    /// expression. Click (or tap) to copy the result and close the menu.
    private func calculationRow(_ calculation: ExpressionEvaluator.Result) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "equal.circle.fill")
                .font(.title3)
                .foregroundStyle(preferences.tintColor)
            Text(calculation.value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer()
            Label("Copy", systemImage: "doc.on.doc")
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(calculation.value, forType: .string)
            model.onClose?()
        }
        .help("Copy \(calculation.value) to the clipboard")
        // Expose the banner as a single actionable button to VoiceOver (FAB-A1).
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Copy result: \(calculation.value)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(calculation.value, forType: .string)
            model.onClose?()
        }
    }

    /// A unit/currency result row: shows the value, click to copy and close (ND-9).
    private func copyRow(symbol: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.title3).foregroundStyle(preferences.tintColor)
            Text(value)
                .font(.title3.weight(.semibold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            Spacer()
            Label("Copy", systemImage: "doc.on.doc")
                .labelStyle(.titleAndIcon).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            model.onClose?()
        }
        .help("Copy \(value) to the clipboard")
        // Expose the copy row as a single actionable button to VoiceOver (FAB-A1).
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Copy result: \(value)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            model.onClose?()
        }
    }

    /// Shown when the query parses as a currency conversion but rates never loaded
    /// (offline / failed fetch). Owns the space where the result would be so the
    /// query isn't silently shipped to a web search on Return (FAB-B12). Click to
    /// retry the fetch.
    private var currencyUnavailableRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash").font(.title3).foregroundStyle(.secondary)
            Text("Currency rates unavailable — check your connection")
                .font(.callout).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { CurrencyService.shared.ensureFresh() }
        .help("Currency rates unavailable — click to retry")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { CurrencyService.shared.ensureFresh() }
    }

    /// A quick-toggle command row (e.g. Toggle Dark Mode) — click to run (ND-9).
    private func commandRow(_ command: MenuCommand) -> some View {
        HStack(spacing: 10) {
            Image(systemName: command.symbol).font(.title3).foregroundStyle(preferences.tintColor)
            Text(command.title).font(.title3.weight(.semibold)).lineLimit(1)
            Spacer()
            Text("⏎ run").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { model.onRunCommand?(command) }
        .help(command.title)
        // Expose the command row as a single actionable button to VoiceOver (FAB-A1).
        .accessibilityElement(children: .combine)
        .accessibilityLabel(command.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.onRunCommand?(command) }
    }

    /// A web-search fallback shown when nothing matches — click (or ⏎) to search (ND-9).
    private func webSearchRow(_ query: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.title3).foregroundStyle(preferences.tintColor)
            Text("Search the web for “\(query)”").lineLimit(1).truncationMode(.middle)
            Spacer()
            Text("⏎").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { model.onWebSearch?(query) }
        .help("Search the web for \(query)")
        // Expose the web-search row as a single actionable button to VoiceOver (FAB-A1).
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Search the web for \(query)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.onWebSearch?(query) }
    }

    /// The results list, or a centered empty state when nothing matches (M17).
    @ViewBuilder
    private var resultsOrEmptyState: some View {
        if model.results.isEmpty {
            emptyState
        } else {
            results
        }
    }

    private var emptyState: some View {
        let hasQuery = !model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(spacing: 6) {
            Image(systemName: hasQuery ? "magnifyingglass" : "square.grid.2x2")
                .font(.title2).foregroundStyle(.secondary)
            Text(hasQuery ? "No matching apps" : "Jetty hasn't found any apps yet")
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, item in
                        // Identify each row by the item, NOT its position. The old `.id(index)`
                        // pinned a row's identity to its slot, so when the query filtered the
                        // list SwiftUI reused the view already sitting at each position and never
                        // refreshed its content — row 0 kept showing the panel's initial first
                        // app, row 1 the initial second, etc. An item-based id makes SwiftUI
                        // rebuild the rows to match the current results.
                        resultRow(item, selected: index == model.selectedIndex)
                            .id(item.id)
                            .onTapGesture { model.selectedIndex = index; model.launch(at: index) }
                            // Hover moves the highlight to the row under the pointer so a mouse
                            // user isn't stuck on a keyboard-selected row (M11). Suppress the
                            // auto-scroll for hover changes so the list doesn't jump under the
                            // cursor — only keyboard navigation should scroll. Route through the
                            // model so the hover also counts as an explicit selection and Return
                            // launches the visibly highlighted row (FAB-B7).
                            .onHover { inside in
                                if inside, model.selectedIndex != index {
                                    suppressScroll = true
                                    model.selectByPointer(index)
                                }
                            }
                            // Expose the row as a single actionable button to VoiceOver (FAB-A1).
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(item.name)
                            .accessibilityAddTraits(index == model.selectedIndex
                                                    ? [.isButton, .isSelected] : .isButton)
                            .accessibilityAction { model.selectedIndex = index; model.launch(at: index) }
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
            }
            .onChange(of: model.selectedIndex) { newValue in
                if suppressScroll { suppressScroll = false; return }
                guard model.results.indices.contains(newValue) else { return }
                withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(model.results[newValue].id, anchor: .center) }
            }
        }
    }

    private func resultRow(_ item: AppSearchItem, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: model.icon(for: item))
                .resizable().frame(width: 28, height: 28)
            Text(item.name).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(selected ? preferences.tintColor.opacity(0.85) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        // Derive the selected-row text color from the tint's luminance — hard-coded white
        // was unreadable on a light tint (white/yellow/pink are all supported) (M10).
        .foregroundStyle(selected ? selectedForeground : Color.primary)
        .contentShape(Rectangle())
    }

    /// Black or white for the selected row, chosen by the tint's perceived luminance so
    /// the label always contrasts against the highlight (M10).
    private var selectedForeground: Color {
        guard let rgb = NSColor(preferences.tintColor).usingColorSpace(.deviceRGB) else { return .white }
        let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return luminance > 0.6 ? .black : .white
    }

    private var powerRow: some View {
        HStack(spacing: 18) {
            ForEach(PowerCommand.allCases) { command in
                Button {
                    model.onRunPower?(command)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: command.systemSymbol).font(.system(size: 16))
                        Text(command.title).font(.system(size: 9))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .help(command.title)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }
}
