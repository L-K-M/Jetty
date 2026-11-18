// swift-tools-version: 5.9
import PackageDescription

// Jetty is a macOS app built through Jetty.xcodeproj. This manifest exists so the
// portable subset of that same source tree — "JettyCore" in docs/linux-port-plan.md —
// compiles and tests on Linux. The two build systems read the same files: Xcode picks
// them up through its file-system-synchronized groups, SwiftPM through the curated
// `sources:` lists below.
//
// The target is named `Jetty`, not `JettyCore`, so the existing tests' `@testable
// import Jetty` compiles unmodified under both.
//
// IMPORTANT: SwiftPM target membership is platform-unconditional, so nothing on macOS
// may build or test this package. It would not even get as far as skipping things: on
// macOS `canImport(SwiftUI)` is true, so `Preferences.tintColor` and
// `DecorationStyle.colors` call `Color(hexString:)` — which lives in LiveryKit, a
// product this target deliberately does not link (it depends on LiveryCore only) —
// and the build fails on an unresolved initialiser. The `sources:` lists below are
// the *Linux* build; macOS goes through the .xcodeproj, always. They deliberately
// carry no hand-written file/suite count: two port steps running have left one
// stale, and the audit step prints the real total on every CI run, so trust
// `scripts/audit-manifest-coverage.swift` over prose.
//
// `sources:` and `exclude:` are both load-bearing: SwiftPM reports anything under the
// target directory that is in neither as "unhandled" and names it, and Linux CI fails
// on that. A new macOS file therefore has to be ported or excluded deliberately.
let package = Package(
    name: "Jetty",
    platforms: [.macOS(.v13)],
    products: [.library(name: "Jetty", targets: ["Jetty"])],
    dependencies: [
        .package(url: "https://github.com/L-K-M/Livery", .upToNextMinor(from: "0.1.0")),
        .package(url: "https://github.com/L-K-M/Keycap", .upToNextMinor(from: "0.1.0")),
        .package(url: "https://github.com/L-K-M/Updraft", .upToNextMinor(from: "0.1.0")),
    ],
    targets: [
        .target(
            name: "Jetty",
            dependencies: [
                .product(name: "LiveryCore", package: "Livery"),
                .product(name: "KeycapCore", package: "Keycap"),
                .product(name: "UpdraftCore", package: "Updraft"),
            ],
            path: "Jetty",
            exclude: [
                "Resources",
                "MediaRemote",
                "Jetty.entitlements",
                "AppDelegate.swift",
                "JettyApp.swift",
                // `Apps` is no longer excluded wholesale — `RunningAppInfo` and
                // `TrashLocations` are portable and sit in `sources:`. That means a
                // NEW file under Apps/ is covered by neither list until someone adds
                // it here or there.
                "Apps/AppLauncher.swift",
                "Apps/AppResponsivenessMonitor.swift",
                "Apps/FinderAutomation.swift",
                "Apps/RunningAppsModel.swift",
                "Apps/TrashIconProvider.swift",
                "Apps/TrashMonitor.swift",
                "Apps/TrashStateResolver.swift",
                "Common/ActivationPolicy.swift",
                "Common/IconCache.swift",
                "Common/LRUImageCache.swift",
                "Common/Poof.swift",
                "Common/TileAccent.swift",
                "Dock/DockContextAction.swift",
                "Dock/DockContextMenuPlacement.swift",
                "Dock/DockContextMenuSource.swift",
                "Dock/DockController.swift",
                "Dock/DockModel.swift",
                "Dock/DockPanelController.swift",
                "Dock/DockTileView.swift",
                "Dock/DockView.swift",
                "Dock/EdgeHoverMonitor.swift",
                // A directory excluded wholesale also covers files added to it later.
                "Icons",
                "Menu/AppIndex.swift",
                "Menu/AppleScriptRunner.swift",
                "Menu/JettyMenuController.swift",
                "Menu/JettyMenuModel.swift",
                "Menu/JettyMenuView.swift",
                "Menu/MenuCommand.swift",
                "Menu/PowerCommands.swift",
                "Menu/RecentAppsStore.swift",
                "Screens/DisplayRegistry.swift",
                "Settings",
                "Stacks",
                "SystemDock",
                "Widgets/AnalogClockFace.swift",
                "Widgets/BatteryWidgetView.swift",
                "Widgets/ClockWidgetView.swift",
                "Widgets/LCDClockFace.swift",
                "Widgets/LiveSystemStats.swift",
                "Widgets/NowPlayingService.swift",
                "Widgets/NowPlayingWidgetView.swift",
                "Widgets/PomodoroTimer.swift",
                "Widgets/PomodoroWidgetView.swift",
                "Widgets/SystemMonitorGaugeView.swift",
                "Widgets/SystemMonitorLEDView.swift",
                "Widgets/SystemMonitorScopeView.swift",
                "Widgets/SystemMonitorWidgetView.swift",
                "Widgets/SystemStats.swift",
                "Widgets/WeatherWidgetView.swift",
                "Widgets/WorldClockWidgetView.swift",
                "Windows",
            ],
            sources: [
                "Screens/DockLayout.swift",
                "Screens/LayerShellPlacement.swift",
                "Dock/MagnificationCurve.swift",
                "Dock/DockTileGeometry.swift",
                "Dock/DockSlot.swift",
                "Dock/DockTile.swift",
                "Dock/DockTileMerge.swift",
                "Apps/RunningAppInfo.swift",
                "Apps/TrashLocations.swift",
                "Common/ObservationCompat.swift",
                "Common/XDGPaths.swift",
                "Model/DockEdge.swift",
                "Model/DockAnchor.swift",
                "Model/HotkeyBinding.swift",
                "Model/JettyMenuGlyph.swift",
                "Model/Preferences.swift",
                "Model/AppearancePreset.swift",
                "Store/DockStore.swift",
                "Store/BookmarkResolver.swift",
                "Model/DockDocument.swift",
                "Model/DockItem.swift",
                "Model/DockItemKind.swift",
                "Model/ClockFaceStyle.swift",
                "Model/SystemMonitorStyle.swift",
                "Model/TrashIconStyle.swift",
                "Model/PreferenceEnums.swift",
                "Widgets/ClockFormatter.swift",
                "Widgets/ClockGeometry.swift",
                "Widgets/SevenSegment.swift",
                "Widgets/WeatherService.swift",
                "Menu/AppSearch.swift",
                "Menu/ExpressionEvaluator.swift",
                "Menu/UnitConverter.swift",
                "Menu/CurrencyService.swift",
            ]
        ),
        .testTarget(
            name: "JettyTests",
            dependencies: ["Jetty"],
            path: "JettyTests",
            exclude: [
                "AppResponsivenessTests.swift",
                "ClockFaceTests.swift",
                "CommandBarTests.swift",
                "DockContextMenuPlacementTests.swift",
                "DockLayoutGapTests.swift",
                "DockModelTests.swift",
                "FolderStackTests.swift",
                "InfoWidgetTests.swift",
                "LinkNormalizationTests.swift",
                "PomodoroTests.swift",
                "PowerCommandTests.swift",
                "RecentsTests.swift",
                "SystemMonitorPathTests.swift",
                "TrashIconTests.swift",
            ],
            sources: [
                "DockLayoutTests.swift",
                "DockTileMergeTests.swift",
                "DockTileGeometryTests.swift",
                "TrashLocationsTests.swift",
                "CodableModelTests.swift",
                "PreferencesTests.swift",
                "HotkeyBindingTests.swift",
                "MenuGlyphAndStoreTests.swift",
                "BookmarkResolverTests.swift",
                "XDGDataHomeTests.swift",
                "StoreBackupTests.swift",
                "StoreVersionTests.swift",
                "LayerShellPlacementTests.swift",
                "KeepRevealedFrameTests.swift",
                "PointerOverDockContentTests.swift",
                "MagnificationCurveTests.swift",
                "ClockFormatterTests.swift",
                "ClockGeometrySecondsTests.swift",
                "AppSearchTests.swift",
                "ExpressionEvaluatorTests.swift",
                "WeatherRetryTests.swift",
            ]
        ),
    ]
)
