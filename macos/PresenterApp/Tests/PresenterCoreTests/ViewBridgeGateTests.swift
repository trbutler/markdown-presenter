import XCTest
@testable import PresenterCore

final class ViewBridgeGateTests: XCTestCase {
    private let deckURL = URL(fileURLWithPath: "/deck/deck.html")

    func testOnlyAuthoritativeMainInstanceMaySendMIDI() {
        let main = ViewConfig.preset(.mainSlides, deckURL: deckURL)
        let second = ViewConfig.preset(.mainSlides, deckURL: deckURL)
        let overlay = ViewConfig.preset(.overlaySlides, deckURL: deckURL)
        let presenter = ViewConfig.preset(.presenter, deckURL: deckURL)
        let custom = ViewConfig.preset(.custom, deckURL: deckURL)
        var gate = ViewBridgeGate()
        gate.configure(ViewList(views: [main, second, overlay, presenter, custom]))
        let authority = UUID(), duplicate = UUID(), cast = UUID()
        gate.register(instanceID: authority, viewID: main.id, isCanonical: true, audienceRendering: true)
        gate.register(instanceID: duplicate, viewID: main.id, isCanonical: true, audienceRendering: true)
        gate.register(instanceID: cast, viewID: main.id, isCanonical: false, audienceRendering: true)
        XCTAssertTrue(gate.permitsMIDI(from: authority))
        XCTAssertFalse(gate.permitsMIDI(from: authority, isMainFrame: false))
        XCTAssertFalse(gate.permitsMIDI(from: duplicate))
        XCTAssertFalse(gate.permitsMIDI(from: cast))
        XCTAssertFalse(gate.permitsMIDI(from: UUID()))
        for view in [second, overlay, presenter, custom] {
            let id = UUID()
            gate.register(instanceID: id, viewID: view.id, isCanonical: true, audienceRendering: true)
            XCTAssertFalse(gate.permitsMIDI(from: id))
        }
    }

    func testAuthorityTracksReorderRemovalAndReplacementInstances() {
        let first = ViewConfig.preset(.mainSlides, deckURL: deckURL)
        let second = ViewConfig.preset(.mainSlides, deckURL: deckURL)
        let a = UUID(), b = UUID(), replacement = UUID()
        var gate = ViewBridgeGate()
        gate.configure(ViewList(views: [first, second]))
        gate.register(instanceID: a, viewID: first.id, isCanonical: true, audienceRendering: true)
        gate.register(instanceID: b, viewID: second.id, isCanonical: true, audienceRendering: true)
        XCTAssertTrue(gate.permitsMIDI(from: a))
        gate.configure(ViewList(views: [second, first]))
        XCTAssertFalse(gate.permitsMIDI(from: a))
        XCTAssertTrue(gate.permitsMIDI(from: b))
        gate.unregister(b)
        XCTAssertFalse(gate.permitsMIDI(from: b))
        gate.register(instanceID: replacement, viewID: second.id, isCanonical: true, audienceRendering: true)
        XCTAssertTrue(gate.permitsMIDI(from: replacement))
        gate.configure(ViewList(views: []))
        XCTAssertFalse(gate.permitsMIDI(from: replacement))
    }

    func testLowerThirdRequestsUseCanonicalOperatorGate() throws {
        let views = [ViewKind.mainSlides, .mainSlides, .overlaySlides, .presenter, .custom]
            .map { ViewConfig.preset($0, deckURL: deckURL) }
        var gate = ViewBridgeGate()
        gate.configure(ViewList(views: views))
        let message = try XCTUnwrap(BridgeMessage(body: ["type": "request", "lowerThird": true] as [String: Any]))
        for (offset, view) in views.enumerated() {
            let canonical = UUID(), cast = UUID()
            let audience = view.kind == .mainSlides || view.kind == .custom
            gate.register(instanceID: canonical, viewID: view.id, isCanonical: true, audienceRendering: audience)
            gate.register(instanceID: cast, viewID: view.id, isCanonical: false, audienceRendering: audience)
            let allowed = offset != 1 && view.kind != .custom
            XCTAssertEqual(gate.permitsRequest(from: canonical), allowed)
            XCTAssertFalse(gate.permitsRequest(from: cast))
            XCTAssertFalse(gate.permitsRequest(from: canonical, isMainFrame: false))
            if allowed { XCTAssertEqual(message.commands, [.setLowerThird(true)]) }
        }
    }
}
