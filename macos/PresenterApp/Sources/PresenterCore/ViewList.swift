import Foundation

public struct ViewList: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 1
    public private(set) var views: [ViewConfig]

    public init(views: [ViewConfig] = []) {
        self.views = views
    }

    public static func presets(deckURL: URL) -> ViewList {
        ViewList(views: [ViewKind.mainSlides, .overlaySlides, .presenter].map { ViewConfig.preset($0, deckURL: deckURL) })
    }

    public var primaryMainID: UUID? {
        views.first { $0.kind == .mainSlides }?.id
    }

    public func validate(deckURL: URL) throws {
        guard schemaVersion == 1 else { throw ViewConfigError.invalid("Unsupported view-list schema") }
        guard Set(views.map(\.id)).count == views.count else { throw ViewConfigError.invalid("View IDs must be unique") }
        var sources: Set<String> = []
        for view in views {
            guard !view.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ViewConfigError.invalid("Every view needs a name")
            }
            guard view.outputs.displayIDs.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                throw ViewConfigError.invalid("Display IDs cannot be empty")
            }
            if view.outputs.ndiEnabled {
                let name = view.outputs.ndiSourceName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !name.isEmpty, sources.insert(name).inserted else {
                    throw ViewConfigError.invalid("Enabled NDI sources need distinct nonempty names")
                }
            }
            if view.kind == .custom && !view.query.isEmpty {
                throw ViewConfigError.invalid("Put Custom query parameters in its URL")
            }
            _ = try view.resolvedURL(deckURL: deckURL)
        }
    }

    @discardableResult
    public mutating func add(_ kind: ViewKind, deckURL: URL) throws -> UUID {
        let view = ViewConfig.preset(kind, deckURL: deckURL)
        var candidate = self
        candidate.views.append(view)
        try candidate.validate(deckURL: deckURL)
        self = candidate
        return view.id
    }

    public mutating func replace(_ view: ViewConfig, deckURL: URL) throws {
        guard let index = views.firstIndex(where: { $0.id == view.id }) else { throw ViewConfigError.invalid("View no longer exists") }
        var candidate = self
        candidate.views[index] = view
        try candidate.validate(deckURL: deckURL)
        self = candidate
    }

    public mutating func remove(_ id: UUID) {
        views.removeAll { $0.id == id }
    }

    /// SwiftUI List move semantics: destination is expressed before removal.
    public mutating func move(fromOffsets offsets: IndexSet, toOffset destination: Int) throws {
        guard destination >= 0, destination <= views.count, offsets.allSatisfy({ views.indices.contains($0) }) else {
            throw ViewConfigError.invalid("Invalid view reorder")
        }
        let moving = offsets.map { views[$0] }
        let remaining = views.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        let insertion = destination - offsets.filter { $0 < destination }.count
        views = Array(remaining.prefix(insertion)) + moving + Array(remaining.dropFirst(insertion))
    }

    /// The first claim in list order wins. Saved losing/disconnected claims stay.
    public func displayOwner(_ displayID: String) -> UUID? {
        views.first { $0.outputs.displayIDs.contains(displayID) }?.id
    }

    public func displayOwners(connected: Set<String>) -> [String: UUID] {
        var result: [String: UUID] = [:]
        for id in connected {
            if let owner = displayOwner(id) { result[id] = owner }
        }
        return result
    }

    public func permitsAudienceEffects(viewID: UUID, isCanonical: Bool) -> Bool {
        isCanonical && primaryMainID == viewID
    }
}
