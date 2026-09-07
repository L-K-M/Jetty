import Foundation

/// A lightweight, value-type snapshot of a running application — enough to build a
/// dock tile and dedup against pinned items, with no AppKit references so the tile
/// merge stays pure and testable.
///
/// Lifted out of `RunningAppsModel.swift` in JP-06: the struct was already free of
/// AppKit by design, but sharing a file with the `NSWorkspace`-backed model meant it
/// could not reach the portable target. `RunningAppsModel` itself stays Darwin-only.
struct RunningAppInfo: Equatable, Identifiable {
    var bundleIdentifier: String?
    var name: String
    var isActive: Bool
    var pid: pid_t
    var launchDate: Date? = nil

    var id: String { bundleIdentifier ?? "pid:\(pid)" }
}
