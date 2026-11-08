import AppKit
import Observation
import PresenterCore

// VERIFY-ON-MAC: validate Observation tracking with macOS 27 SwiftUI. Observed
// value types are Equatable; render callbacks are not part of observed state.
@MainActor
@Observable
final class ViewStore {
    private static let defaultsKey = "presenterViewList.v1"
    private static let keyrussoKey = "keyrussoServer.v1"
    let deckURL: URL
    private(set) var list: ViewList
    var displays: [DisplayInfo] = []
    var error: String?
    private(set) var keyrussoBase: URL = KeyrussoPreset.defaultBase
    private(set) var isImportingMap = false
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
        if let text = UserDefaults.standard.string(forKey: Self.keyrussoKey),
           let saved = try? KeyrussoServer.normalizedBase(text) {
            keyrussoBase = saved
        }
        displays = NSScreen.displayInfos
    }

    /// Adds one Keyrusso screen as a custom view pointing at the saved server.
    func addKeyrusso(_ preset: KeyrussoPreset) -> UUID? {
        do {
            let view = try preset.view(base: keyrussoBase)
            var candidate = list
            try candidate.add([view], deckURL: deckURL)
            try commit(candidate)
            return view.id
        } catch { self.error = error.localizedDescription; return nil }
    }

    func setKeyrussoServer(_ text: String) -> Bool {
        do {
            keyrussoBase = try KeyrussoServer.normalizedBase(text)
            UserDefaults.standard.set(keyrussoBase.absoluteString, forKey: Self.keyrussoKey)
            error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    /// Reads the server's display map and adds one view per entry, placed on
    /// Display N (in the order the app lists displays) and/or an NDI source.
    func importKeyrussoMap() async {
        guard !isImportingMap else { return }
        isImportingMap = true
        defer { isImportingMap = false }
        do {
            var request = URLRequest(url: try KeyrussoServer.displayMapURL(base: keyrussoBase))
            request.timeoutInterval = 10
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw ViewConfigError.invalid("The Keyrusso server did not answer with a display map")
            }
            let views = try KeyrussoDisplayMap.decode(data).views(displayIDs: displays.map(\.id))
            var candidate = list
            try candidate.add(views, deckURL: deckURL)
            try commit(candidate)
        } catch { self.error = error.localizedDescription }
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
