import XCTest
@testable import PresenterCore

final class ViewListTests: XCTestCase {
    private let deck = URL(fileURLWithPath: "/presenter/decks/show.html")

    func testPresetsAndRoundTrip() throws {
        let list = ViewList.presets(deckURL: deck)
        try list.validate(deckURL: deck)
        XCTAssertEqual(list.views.map(\.kind), [.mainSlides, .overlaySlides, .presenter])
        XCTAssertEqual(list.views.map(\.name), ["Main Slides", "Overlay Slides", "Presenter View"])
        XCTAssertEqual(Set(list.views.map(\.id)).count, 3)
        XCTAssertTrue(list.views.allSatisfy { $0.outputs.displayIDs.isEmpty && !$0.outputs.ndiEnabled })
        XCTAssertEqual(try JSONDecoder().decode(ViewList.self, from: JSONEncoder().encode(list)), list)
        for (config, expected) in zip(list.views, ["audience", "overlay", "notes"]) {
            let url = try config.resolvedURL(deckURL: deck)
            XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "view" }?.value, expected)
        }
    }

    func testAddReplaceRemoveAndReorderPreserveIdentity() throws {
        var list = ViewList.presets(deckURL: deck)
        let id = try list.add(.custom, deckURL: deck)
        var custom = try XCTUnwrap(list.views.last)
        custom.name = "Camera words"
        custom.customURL = deck.absoluteString + "?view=lyrics"
        try list.replace(custom, deckURL: deck)
        XCTAssertEqual(list.views.last?.id, id)
        let original = list.views.map(\.id)
        try list.move(fromOffsets: IndexSet([0, 2]), toOffset: 4)
        XCTAssertEqual(list.views.map(\.id), [original[1], original[3], original[0], original[2]])
        list.remove(id)
        XCTAssertFalse(list.views.contains { $0.id == id })
        XCTAssertEqual(list.views.count, 3)
        let snapshot = list
        XCTAssertThrowsError(try list.move(fromOffsets: IndexSet(integer: 99), toOffset: 0))
        XCTAssertEqual(list, snapshot)
        XCTAssertThrowsError(try list.move(fromOffsets: IndexSet(integer: 0), toOffset: -1))
        XCTAssertEqual(list, snapshot)
        for view in snapshot.views { list.remove(view.id) }
        XCTAssertTrue(list.views.isEmpty)
        try list.validate(deckURL: deck)
    }

    func testDisplayConflictsAndDisconnectKeepSavedClaims() throws {
        var first = ViewConfig.preset(.mainSlides, deckURL: deck)
        var second = ViewConfig.preset(.overlaySlides, deckURL: deck)
        first.outputs.displayIDs = ["projector", "stage"]
        first.outputs.ndiEnabled = true
        second.outputs.displayIDs = ["projector"]
        var list = ViewList(views: [first, second])
        try list.validate(deckURL: deck)
        XCTAssertEqual(list.displayOwners(connected: ["projector", "stage"]), ["projector": first.id, "stage": first.id])
        XCTAssertEqual(list.displayOwners(connected: ["stage"]), ["stage": first.id])
        XCTAssertEqual(list.views[0].outputs.displayIDs, ["projector", "stage"])
        XCTAssertTrue(list.views[0].outputs.ndiEnabled)
        try list.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        XCTAssertEqual(list.displayOwners(connected: ["projector"]), ["projector": second.id])
        list.remove(second.id)
        XCTAssertEqual(list.displayOwner("projector"), first.id)
    }

    func testPrimaryAudienceIsFirstMainCanonicalOnly() throws {
        let presenter = ViewConfig.preset(.presenter, deckURL: deck)
        let first = ViewConfig.preset(.mainSlides, deckURL: deck)
        let second = ViewConfig.preset(.mainSlides, deckURL: deck)
        let custom = ViewConfig.preset(.custom, deckURL: deck)
        var list = ViewList(views: [presenter, first, second, custom])
        XCTAssertEqual(list.primaryMainID, first.id)
        XCTAssertTrue(list.permitsAudienceEffects(viewID: first.id, isCanonical: true))
        XCTAssertFalse(list.permitsAudienceEffects(viewID: first.id, isCanonical: false))
        XCTAssertFalse(list.permitsAudienceEffects(viewID: second.id, isCanonical: true))
        XCTAssertFalse(list.permitsAudienceEffects(viewID: custom.id, isCanonical: true))
        try list.move(fromOffsets: IndexSet(integer: 2), toOffset: 1)
        XCTAssertEqual(list.primaryMainID, second.id)
        list.remove(first.id); list.remove(second.id)
        XCTAssertNil(list.primaryMainID)
        XCTAssertFalse(list.permitsAudienceEffects(viewID: presenter.id, isCanonical: true))
    }

    func testValidationAndAtomicEditFailure() throws {
        var list = ViewList.presets(deckURL: deck)
        let original = list
        var invalid = list.views[0]
        invalid.name = "  "
        XCTAssertThrowsError(try list.replace(invalid, deckURL: deck))
        XCTAssertEqual(list, original)
        XCTAssertThrowsError(try ViewList(views: [original.views[0], original.views[0]]).validate(deckURL: deck))
        list.schemaVersion = 99
        XCTAssertThrowsError(try list.validate(deckURL: deck))
        var a = original.views[0]
        var b = original.views[1]
        a.outputs.ndiEnabled = true; b.outputs.ndiEnabled = true
        a.outputs.ndiSourceName = "Same"; b.outputs.ndiSourceName = "same"
        XCTAssertThrowsError(try ViewList(views: [a, b]).validate(deckURL: deck))
        a.outputs.ndiSourceName = " "
        XCTAssertThrowsError(try ViewList(views: [a]).validate(deckURL: deck))
        a = original.views[0]; a.outputs.displayIDs = [""]
        XCTAssertThrowsError(try ViewList(views: [a]).validate(deckURL: deck))
    }

    func testPresetURLPreservesUnrelatedQueryAndRejectsReservedKeys() throws {
        let url = try XCTUnwrap(URL(string: deck.absoluteString + "?view=service&chrome=1&seed=9&mute=1#3"))
        var config = ViewConfig.preset(.overlaySlides, deckURL: deck)
        config.query = ["chrome": "0", "label": "two words & more"]
        let resolved = try config.resolvedURL(deckURL: url)
        let parts = try XCTUnwrap(URLComponents(url: resolved, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query, ["view": "overlay", "chrome": "0", "label": "two words & more"])
        XCTAssertEqual(parts.fragment, "3")
        XCTAssertEqual(resolved.path, deck.path)
        for key in ["view", "VIEW", "seed", "mute", ""] {
            config.query = [key: "x"]
            XCTAssertThrowsError(try config.resolvedURL(deckURL: deck))
        }
    }
}
