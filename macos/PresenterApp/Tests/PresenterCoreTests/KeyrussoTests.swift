import XCTest
@testable import PresenterCore

final class KeyrussoTests: XCTestCase {
    private let deck = URL(fileURLWithPath: "/presenter/decks/show.html")
    private let base = URL(string: "http://booth.local:8765")!

    func testPresetPaths() throws {
        let paths = try KeyrussoPreset.allCases.compactMap { try $0.view(base: base).customURL }
        XCTAssertEqual(paths, ["present", "confidence", "stage", "lobby", "ndi", "obs"].map { "http://booth.local:8765/\($0)" })
    }

    func testPresetViewIsACustomViewThatValidates() throws {
        var list = ViewList.presets(deckURL: deck)
        let view = try KeyrussoPreset.confidence.view(base: base)
        XCTAssertEqual(view.kind, .custom)
        XCTAssertFalse(view.outputs.ndiEnabled)
        try list.add([view], deckURL: deck)
        XCTAssertEqual(list.views.count, 4)
        XCTAssertEqual(try view.resolvedURL(deckURL: deck).absoluteString, "http://booth.local:8765/confidence")
        // Only the deck's own file page gets presentation controls.
        XCTAssertFalse(ViewURLPolicy.allowsBridge(try view.resolvedURL(deckURL: deck), deckURL: deck))
    }

    func testNDIPresetsStartWithNDIAndStayDistinct() throws {
        var list = ViewList()
        let a = try KeyrussoPreset.ndi.view(base: base)
        let b = try KeyrussoPreset.ndi.view(base: base)
        XCTAssertTrue(a.outputs.ndiEnabled)
        XCTAssertNotEqual(a.outputs.ndiSourceName, b.outputs.ndiSourceName)
        try list.add([a, b], deckURL: deck)
    }

    func testBaseNormalizing() throws {
        XCTAssertEqual(try KeyrussoServer.normalizedBase(" https://booth.example:8765/ ").absoluteString, "https://booth.example:8765")
        for bad in ["", "booth", "ftp://x", "http://", "http://u:p@x", "http://x/path", "http://x?q=1", "javascript:alert(1)", "file:///tmp"] {
            XCTAssertThrowsError(try KeyrussoServer.normalizedBase(bad), bad)
        }
    }

    func testPathMustBeOneSlash() {
        XCTAssertThrowsError(try KeyrussoPreset.main.view(base: base, path: "//evil.example/x"))
        XCTAssertThrowsError(try KeyrussoPreset.main.view(base: base, path: "present"))
        XCTAssertThrowsError(try KeyrussoPreset.main.view(base: base, path: "/a?b=1"))
    }

    private let json = """
    {"displayMap":{"base":"http://b:1","entries":[
     {"input":"main","label":"House","url":"http://b:1/present","template":"lyricsL3","screen":1,"ndi":null},
     {"input":"confidence","label":"Confidence","url":"http://b:1/confidence","template":"confidence","screen":2,"ndi":null},
     {"input":"stage","label":"Stage","url":"http://b:1/stage","template":"stage","screen":5,"ndi":null},
     {"input":"ndi","label":"NDI","url":"http://b:1/ndi","template":"fullscreen","screen":null,
      "ndi":{"name":"Sanctuary","width":1920,"height":1080,"fps":30}}]}}
    """

    func testDisplayMapBecomesViews() throws {
        let map = try KeyrussoDisplayMap.decode(Data(json.utf8))
        let views = try map.views(displayIDs: ["D-A", "D-B"])
        XCTAssertEqual(views.map(\.name), ["Keyrusso House", "Keyrusso Confidence", "Keyrusso Stage", "Keyrusso NDI"])
        XCTAssertEqual(views[0].outputs.displayIDs, ["D-A"])
        XCTAssertEqual(views[1].outputs.displayIDs, ["D-B"])
        XCTAssertTrue(views[2].outputs.displayIDs.isEmpty, "screen 5 with two displays stays unassigned")
        XCTAssertTrue(views[3].outputs.ndiEnabled)
        XCTAssertEqual(views[3].outputs.ndiSourceName, "Sanctuary")
        var list = ViewList()
        try list.add(views, deckURL: deck)
        XCTAssertEqual(list.displayOwner("D-A"), views[0].id)
    }

    func testDisplayMapRejectsNonHTTPAndNonMaps() throws {
        XCTAssertThrowsError(try KeyrussoDisplayMap.decode(Data("{}".utf8)))
        let evil = KeyrussoDisplayMap(entries: [.init(input: "main", label: "x", url: "javascript:alert(1)", screen: 1, ndi: nil)])
        XCTAssertThrowsError(try evil.views(displayIDs: ["D"]))
    }

    func testGroupAddIsAllOrNothing() throws {
        var list = ViewList.presets(deckURL: deck)
        let good = try KeyrussoPreset.stage.view(base: base)
        var bad = try KeyrussoPreset.lobby.view(base: base)
        bad.customURL = "ftp://nope"
        let before = list
        XCTAssertThrowsError(try list.add([good, bad], deckURL: deck))
        XCTAssertEqual(list, before)
    }
}
