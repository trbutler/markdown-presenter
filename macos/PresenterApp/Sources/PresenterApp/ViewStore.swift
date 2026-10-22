import AppKit
import Observation
import PresenterCore

// VERIFY-ON-MAC: validate Observation tracking with macOS 27 SwiftUI. Observed
// value types are Equatable; render callbacks are not part of observed state.
@MainActor
@Observable
final class ViewStore {
    private static let defaultsKey = "presenterViewList.v1"
    let deckURL: URL
    private(set) var list: ViewList
    var displays: [DisplayInfo] = []
    var error: String?
    var outputStatus: [UUID: String] = [:]
    @ObservationIgnored var onChange: (() -> Void)?

    init(deckURL: URL) {
        self.deckURL = deckURL
        list = ViewList.presets(deckURL: deckURL)
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey) {
            do {
                let saved = try JSONDecoder().decode(ViewList.self, from: data)
                try saved.validate(deckURL: deckURL)
                list = saved
            } catch {
                self.error = "Saved views could not be loaded; the saved data is retained. \(error.localizedDescription)"
            }
        }
        displays = NSScreen.displayInfos
    }

    func add(_ kind: ViewKind) -> UUID? {
        do {
            var candidate = list
            let id = try candidate.add(kind, deckURL: deckURL)
            try commit(candidate)
            return id
        } catch { self.error = error.localizedDescription; return nil }
    }

    func apply(_ view: ViewConfig) {
        do {
            var candidate = list
            try candidate.replace(view, deckURL: deckURL)
            try commit(candidate)
        } catch { self.error = error.localizedDescription }
    }

    func remove(_ id: UUID) {
        var candidate = list
        candidate.remove(id)
        do { try commit(candidate) } catch { self.error = error.localizedDescription }
    }

    func move(_ offsets: IndexSet, to destination: Int) {
        do {
            var candidate = list
            try candidate.move(fromOffsets: offsets, toOffset: destination)
            try commit(candidate)
        } catch { self.error = error.localizedDescription }
    }

    private func commit(_ candidate: ViewList) throws {
        try candidate.validate(deckURL: deckURL)
        let data = try JSONEncoder().encode(candidate)
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        list = candidate
        error = nil
        onChange?()
    }
}
