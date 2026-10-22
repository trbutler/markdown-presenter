import XCTest
@testable import PresenterCore

final class ViewURLPolicyTests: XCTestCase {
    private let deck = URL(fileURLWithPath: "/presenter/decks/show.html")

    func testOwnDeckOnlyGetsBridgeRegardlessOfQueryOrFragment() throws {
        let own = try XCTUnwrap(URL(string: deck.absoluteString + "?view=lyrics#4"))
        XCTAssertTrue(ViewURLPolicy.allowsBridge(own, deckURL: deck))
        let other = URL(fileURLWithPath: "/presenter/decks/other.html")
        try ViewURLPolicy.validate(other, deckURL: deck)
        XCTAssertFalse(ViewURLPolicy.allowsBridge(other, deckURL: deck))
        let lookalike = try XCTUnwrap(URL(string: "https://example.invalid/presenter/decks/show.html"))
        try ViewURLPolicy.validate(lookalike, deckURL: deck)
        XCTAssertFalse(ViewURLPolicy.allowsBridge(lookalike, deckURL: deck))
    }

    func testSchemeAllowListAndRemoteHostValidation() throws {
        for text in ["https://example.invalid/view", "http://localhost:8080/deck"] {
            let url = try XCTUnwrap(URL(string: text))
            try ViewURLPolicy.validate(url, deckURL: deck)
            XCTAssertFalse(ViewURLPolicy.allowsBridge(url, deckURL: deck))
        }
        for text in ["javascript:alert(1)", "data:text/html,hi", "ftp://example.invalid/file", "about:blank", "relative.html",
                     "https:/missing-host", "https://user:password@example.invalid/view", "file://remote-host/presenter/decks/show.html"] {
            let url = try XCTUnwrap(URL(string: text))
            XCTAssertThrowsError(try ViewURLPolicy.validate(url, deckURL: deck))
            XCTAssertFalse(ViewURLPolicy.allowsBridge(url, deckURL: deck))
        }
    }

    func testFileFolderBoundaryAndEncodedTraversal() throws {
        for text in ["file:///presenter/decks-old/file.html", "file:///presenter/decks/../outside.html",
                     "file:///presenter/decks/%2e%2e/outside.html"] {
            let url = try XCTUnwrap(URL(string: text))
            XCTAssertThrowsError(try ViewURLPolicy.validate(url, deckURL: deck))
        }
        try ViewURLPolicy.validate(URL(fileURLWithPath: "/presenter/decks/nested/file.html"), deckURL: deck)
    }

    func testSymlinkEscapeRejectedAndOwnDeckAliasTrusted() throws {
        // Committed fixtures; no temporary files, deletions or external access.
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/security/deck")
        let ownDeck = folder.appendingPathComponent("deck.html")
        let alias = folder.appendingPathComponent("alias.html")
        let escape = folder.appendingPathComponent("escape.html")
        XCTAssertTrue(ViewURLPolicy.allowsBridge(alias, deckURL: ownDeck))
        var custom = ViewConfig.preset(.custom, deckURL: ownDeck)
        custom.customURL = alias.absoluteString + "?view=lyrics#2"
        let canonical = try custom.resolvedURL(deckURL: ownDeck)
        XCTAssertEqual(canonical.path, ownDeck.path)
        XCTAssertEqual(URLComponents(url: canonical, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "lyrics")
        XCTAssertEqual(canonical.fragment, "2")
        XCTAssertThrowsError(try ViewURLPolicy.validate(escape, deckURL: ownDeck))
        XCTAssertFalse(ViewURLPolicy.allowsBridge(escape, deckURL: ownDeck))
    }

    func testCustomURLValidationIsUsedByModel() throws {
        var custom = ViewConfig.preset(.custom, deckURL: deck)
        custom.customURL = "https://example.invalid/camera?x=1"
        XCTAssertEqual(try custom.resolvedURL(deckURL: deck).absoluteString, custom.customURL)
        try ViewList(views: [custom]).validate(deckURL: deck)
        custom.customURL = "javascript:alert(1)"
        XCTAssertThrowsError(try ViewList(views: [custom]).validate(deckURL: deck))
        custom.customURL = nil
        XCTAssertThrowsError(try custom.resolvedURL(deckURL: deck))
        custom.customURL = deck.absoluteString
        custom.query = ["view": "audience"]
        XCTAssertThrowsError(try ViewList(views: [custom]).validate(deckURL: deck))
    }
}
