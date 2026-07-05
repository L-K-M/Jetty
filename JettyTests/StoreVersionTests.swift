import XCTest
@testable import Jetty

/// FAB-B16: the store must stamp `DockDocument.currentVersion` on everything it
/// writes, and must never overwrite a file written by a *newer* build (whose
/// content it can only decode lossily).
final class StoreVersionTests: XCTestCase {

    private var dir: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("JettyStoreVersionTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("dock.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func versionField(of url: URL) throws -> Int? {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return object?["version"] as? Int
    }

    // MARK: A newer file is never destructively downgraded

    func testHigherVersionFileIsReadOnlyAndNeverOverwritten() throws {
        // A file claiming a future version, as a newer build would have written it.
        let future = DockDocument(version: DockDocument.currentVersion + 1,
                                  items: [DockItem(kind: .application,
                                                   displayName: "Future App",
                                                   bundleIdentifier: "com.example.future")])
        let originalBytes = try JSONEncoder().encode(future)
        try originalBytes.write(to: fileURL)

        let store = DockStore(fileURL: fileURL, debounce: 0.01)
        XCTAssertTrue(store.loadedFromDisk)
        XCTAssertTrue(store.isReadOnly)
        XCTAssertEqual(store.document.version, DockDocument.currentVersion + 1)

        // Mutate + force a flush: the guard must skip the write entirely.
        store.addItem(DockItem(kind: .application, displayName: "Old Build App"))
        store.setItems(store.items + [DockItem(kind: .file, displayName: "Doc")])
        store.flush()

        let bytesAfter = try Data(contentsOf: fileURL)
        XCTAssertEqual(bytesAfter, originalBytes,
                       "a higher-version file must not be rewritten by an older build")
        // The `.bak` rotation must not run either — it would evict the real newer backup.
        let bak = fileURL.appendingPathExtension("bak")
        XCTAssertFalse(FileManager.default.fileExists(atPath: bak.path))
        // In-memory edits still work for the session.
        XCTAssertEqual(store.items.count, 3)
    }

    // MARK: Normal saves stamp the version truthfully

    func testNormalSaveWritesCurrentVersion() throws {
        let store = DockStore(fileURL: fileURL, debounce: 0.01)
        XCTAssertFalse(store.loadedFromDisk)
        XCTAssertFalse(store.isReadOnly)

        store.addItem(DockItem(kind: .application, displayName: "Safari",
                               bundleIdentifier: "com.apple.Safari"))
        store.flush()

        XCTAssertEqual(try versionField(of: fileURL), DockDocument.currentVersion)
        let decoded = try XCTUnwrap(DockStore.load(from: fileURL))
        XCTAssertEqual(decoded.version, DockDocument.currentVersion)
        XCTAssertEqual(decoded.items.count, 1)
    }

    func testSaveUpgradesAnOlderVersionStamp() throws {
        // A file from a (hypothetical) older schema keeps loading normally…
        let old = DockDocument(version: 0,
                               items: [DockItem(kind: .file, displayName: "Notes")])
        try JSONEncoder().encode(old).write(to: fileURL)

        let store = DockStore(fileURL: fileURL, debounce: 0.01)
        XCTAssertTrue(store.loadedFromDisk)
        XCTAssertFalse(store.isReadOnly, "older versions stay writable — behavior unchanged")

        // …and the first save stamps what this build actually wrote.
        store.addItem(DockItem(kind: .file, displayName: "More Notes"))
        store.flush()

        XCTAssertEqual(try versionField(of: fileURL), DockDocument.currentVersion)
        let decoded = try XCTUnwrap(DockStore.load(from: fileURL))
        XCTAssertEqual(decoded.version, DockDocument.currentVersion)
        XCTAssertEqual(decoded.items.count, 2)
    }
}
