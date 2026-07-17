import Foundation

/// Pure tier-selection for Trash-fullness resolution (see TRASH.md). Given the
/// result of the home-Trash filesystem probe and the Finder Automation consent
/// status, decide which exact source to use — or give up honestly. No I/O, so the
/// policy is unit-tested.
enum TrashStateResolver {

    enum Plan: Equatable {
        /// The probe produced a definitive answer — use it (Full Disk Access, or a
        /// system where the Trash isn't locked for this app).
        case useProbe(DockModel.TrashState)
        /// The probe was denied but Finder Automation is consented — ask Finder for
        /// the item count.
        case askFinder
        /// Neither exact source works — render the neutral (empty) can; the
        /// Permissions pane offers the user the one-click fix.
        case indeterminate
    }

    static func plan(probe: DockModel.TrashState, finderAutomationGranted: Bool) -> Plan {
        switch probe {
        case .full, .empty:
            return .useProbe(probe)
        case .unknown:
            return finderAutomationGranted ? .askFinder : .indeterminate
        }
    }
}
