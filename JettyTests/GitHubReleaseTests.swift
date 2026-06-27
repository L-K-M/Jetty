import XCTest
@testable import Jetty

final class GitHubReleaseTests: XCTestCase {

    private let json = Data("""
    {
      "tag_name": "v1.4.0",
      "name": "Jetty 1.4.0",
      "body": "Notes here",
      "html_url": "https://github.com/L-K-M/Jetty/releases/tag/v1.4.0",
      "prerelease": false,
      "draft": false,
      "published_at": "2026-06-01T12:00:00Z",
      "assets": [
        { "name": "Jetty-1.4.0.zip", "content_type": "application/zip", "size": 1, "browser_download_url": "https://example.com/Jetty.zip" },
        { "name": "Jetty-1.4.0.dmg", "content_type": "application/x-apple-diskimage", "size": 2, "browser_download_url": "https://example.com/Jetty.dmg" }
      ]
    }
    """.utf8)

    func testDecodes() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let release = try decoder.decode(GitHubRelease.self, from: json)
        XCTAssertEqual(release.tagName, "v1.4.0")
        XCTAssertEqual(release.assets.count, 2)
        XCTAssertFalse(release.draft)
    }

    func testPrefersDMGAsset() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let release = try decoder.decode(GitHubRelease.self, from: json)
        XCTAssertEqual(release.preferredAsset?.name, "Jetty-1.4.0.dmg")
    }

    func testReleaseNotesTruncates() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let release = try decoder.decode(GitHubRelease.self, from: json)
        XCTAssertEqual(release.releaseNotes(maxLength: 4), "Note…")
    }
}
