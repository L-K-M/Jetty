import XCTest
@testable import Jetty

/// `DockStore`'s `.bak` rotation (F-R9): recovery from a corrupt primary via
/// the backup, the ISSUE-9 guard that keeps a corrupt primary from rotating
/// over the last good backup, and the healthy save → rotate round-trip.
/// Uses a per-test temp directory and the store's `fileURL` injection.
final class StoreBackupTests: XCTestCase {

    private var dir: URL!
    private var fileURL: URL!
    private var bakURL: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("JettyStoreBackupTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("dock.json")
        bakURL = fileURL.appendingPathExtension("bak")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func write(_ doc: DockDocument, to url: URL) throws {
        try JSONEncoder().encode(doc).write(to: url)
    }

    private func decode(_ url: URL) throws -> DockDocument {
        try JSONDecoder().decode(DockDocument.self, from: Data(contentsOf: url))
    }

    func testLoadRecoversFromCorruptPrimaryViaBackup() throws {
        try Data("{ this is not json".utf8).write(to: fileURL)
        try write(DockDocument(disabledDisplayUUIDs: ["GOOD-BAK"]), to: bakURL)

        let store = DockStore(fileURL: fileURL, debounce: 0)
        XCTAssertTrue(store.loadedFromDisk)
        XCTAssertEqual(store.document.disabledDisplayUUIDs, ["GOOD-BAK"])
    }

    func testSaveDoesNotRotateCorruptPrimaryOverGoodBackup() throws {
        try Data("{ this is not json".utf8).write(to: fileURL)
        let goodBak = DockDocument(disabledDisplayUUIDs: ["GOOD-BAK"])
        try write(goodBak, to: bakURL)

        let store = DockStore(fileURL: fileURL, debounce: 0)  // recovers from .bak
        store.setDisplayDisabled(true, forDisplayUUID: "NEW")
        store.flush()

        // The primary was rewritten with the recovered + edited document…
        XCTAssertEqual(try decode(fileURL).disabledDisplayUUIDs, ["GOOD-BAK", "NEW"])
        // …but the corrupt bytes were NOT rotated over the last good backup (ISSUE-9).
        XCTAssertEqual(try decode(bakURL), goodBak)
    }

    func testHealthySaveRoundTripRotatesPreviousGoodVersionIntoBackup() throws {
        let store = DockStore(fileURL: fileURL, debounce: 0)
        XCTAssertFalse(store.loadedFromDisk)

        // First save: primary decodes; there was nothing to rotate into a backup.
        store.setDisplayDisabled(true, forDisplayUUID: "ONE")
        store.flush()
        XCTAssertEqual(try decode(fileURL).disabledDisplayUUIDs, ["ONE"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: bakURL.path))

        // Second save: the prior good primary rotates into `.bak`.
        store.setDisplayDisabled(true, forDisplayUUID: "TWO")
        store.flush()
        XCTAssertEqual(try decode(fileURL).disabledDisplayUUIDs, ["ONE", "TWO"])
        XCTAssertEqual(try decode(bakURL).disabledDisplayUUIDs, ["ONE"])
    }
}
