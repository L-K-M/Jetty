import Foundation

/// The look of the Trash dock tile. `.default` is the exact system trash can
/// (CoreTypes artwork, empty/full — see TRASH.md); other styles ship their own
/// empty/full artwork in the asset catalog. Each style provides a distinct empty
/// and full variant so the can still reflects the live Trash state.
enum TrashIconStyle: String, CaseIterable, Identifiable, Codable {
    case `default`
    case seven
    case eight
    case star
    case white
    case dark
    case cheetah

    var id: String { rawValue }

    /// Human-readable name for the Settings picker.
    var displayName: String {
        switch self {
        case .default: return "Default (System)"
        case .seven: return "Seven"
        case .eight: return "Eight"
        case .star: return "Star"
        case .white: return "White"
        case .dark: return "Dark"
        case .cheetah: return "Cheetah"
        }
    }

    /// Asset-catalog image names for the empty/full variants, or nil for `.default`
    /// (which comes from the system CoreTypes resources, not a bundled asset).
    var assetNames: (empty: String, full: String)? {
        switch self {
        case .default: return nil
        case .seven: return ("TrashSevenEmpty", "TrashSevenFull")
        case .eight: return ("TrashEightEmpty", "TrashEightFull")
        case .star: return ("TrashStarEmpty", "TrashStarFull")
        case .white: return ("TrashWhiteEmpty", "TrashWhiteFull")
        case .dark: return ("TrashDarkEmpty", "TrashDarkFull")
        case .cheetah: return ("TrashCheetahEmpty", "TrashCheetahFull")
        }
    }
}
