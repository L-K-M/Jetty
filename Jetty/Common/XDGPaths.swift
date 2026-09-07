import Foundation

/// The XDG Base Directory rules, in one place.
///
/// Extracted in JP-06a after a second hand-rolled copy appeared in
/// `TrashLocations`: the persisted-data location and the trash location have to
/// agree about what `$XDG_DATA_HOME` means, and "mirrors the other one" in a comment
/// is the arrangement this port keeps having to undo. `DockStore.xdgDataHome`
/// forwards here, so its existing tests still pin this behaviour unchanged.
enum XDGPaths {

    /// `$XDG_DATA_HOME`, or the spec's default. Two rules beyond "read the variable",
    /// and both are here: an unset **or empty** value falls back to
    /// `$HOME/.local/share`, and a **relative** value is invalid and must be ignored
    /// rather than resolved against the working directory. Pure and unconditional, so
    /// both platforms test it.
    static func dataHome(_ value: String?, home: String) -> URL {
        if let value, value.hasPrefix("/") { return URL(fileURLWithPath: value) }
        return URL(fileURLWithPath: home).appendingPathComponent(".local/share")
    }

    /// `dataHome` for the current process.
    static func dataHome() -> URL {
        dataHome(ProcessInfo.processInfo.environment["XDG_DATA_HOME"], home: NSHomeDirectory())
    }
}
