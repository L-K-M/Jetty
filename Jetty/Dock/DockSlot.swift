import Foundation

/// One reorderable unit on the dock. Most slots wrap a single tile (a pinned app,
/// file, the clock, …); the **running-apps** slot wraps the whole cluster of
/// running-but-not-pinned apps so it moves as one element. A slot is reorderable iff
/// it has a backing `itemID` (the pinned `DockItem`, or the running-apps sentinel).
/// See PLAN.md §7.
struct DockSlot: Identifiable {
    let id: String
    let itemID: UUID?
    let tiles: [DockTile]
    let isRunningGroup: Bool

    var isReorderable: Bool { itemID != nil }
}
