import Foundation

/// Where a display's dock lives: a *stable display identity* plus an edge, an
/// alignment along that edge, a fine `offset`, and an `inset` from the very edge
/// (for a floating-island look). Keying on a durable display **UUID** — never raw
/// pixels — is what lets a dock return to the same spot after a reboot, resolution
/// change, or monitor reconnection. See PLAN.md §5–6.
struct DockAnchor: Codable, Equatable {

    /// `CGDisplayCreateUUIDFromDisplayID` string — stable across reboots and
    /// reconnections for the same physical display. Empty means "the default /
    /// any display".
    var displayUUID: String

    var edge: DockEdge
    var alignment: DockAlignment

    /// Fine nudge along the edge, in points (positive = toward trailing/bottom).
    var offset: Double

    /// Gap from the very screen edge, in points. `0` hugs the edge; a positive
    /// value lifts the dock off it for a floating bar.
    var inset: Double

    init(displayUUID: String = "",
         edge: DockEdge = .bottom,
         alignment: DockAlignment = .center,
         offset: Double = 0,
         inset: Double = 0) {
        self.displayUUID = displayUUID
        self.edge = edge
        self.alignment = alignment
        self.offset = offset
        self.inset = DockAnchor.clampInset(inset)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayUUID = try c.decodeIfPresent(String.self, forKey: .displayUUID) ?? ""
        edge = try c.decodeIfPresent(DockEdge.self, forKey: .edge) ?? .bottom
        alignment = try c.decodeIfPresent(DockAlignment.self, forKey: .alignment) ?? .center
        offset = try c.decodeIfPresent(Double.self, forKey: .offset) ?? 0
        inset = DockAnchor.clampInset(try c.decodeIfPresent(Double.self, forKey: .inset) ?? 0)
    }

    private enum CodingKeys: String, CodingKey { case displayUUID, edge, alignment, offset, inset }

    /// Keeps the inset finite and non-negative (corrupted storage maps to 0).
    static func clampInset(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return Swift.max(0, Swift.min(value, 400))
    }
}
