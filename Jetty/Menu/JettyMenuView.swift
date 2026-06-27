import SwiftUI
import AppKit

/// The Windows-Start-style launcher panel: a search field over installed apps, a
/// results list, and a power-command row. Liquid Glass background to match the dock.
/// See PLAN.md §8.2.
struct JettyMenuView: View {
    @ObservedObject var model: JettyMenuModel
    @ObservedObject var preferences: Preferences
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider().opacity(0.5)
            results
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

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, item in
                        resultRow(item, selected: index == model.selectedIndex)
                            .id(index)
                            .onTapGesture { model.selectedIndex = index; model.activateSelection() }
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
            }
            .onChange(of: model.selectedIndex) { newValue in
                withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(newValue, anchor: .center) }
            }
        }
    }

    private func resultRow(_ item: AppSearchItem, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().frame(width: 28, height: 28)
            Text(item.name).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(selected ? preferences.tintColor.opacity(0.85) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .foregroundStyle(selected ? Color.white : Color.primary)
        .contentShape(Rectangle())
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
