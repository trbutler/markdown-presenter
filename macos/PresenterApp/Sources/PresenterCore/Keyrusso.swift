import Foundation

/// The booth screens keyrusso serves. Each is a plain web page, so a view that
/// shows one is a `.custom` view: nothing in the saved view-list schema changes.
/// Foundation only, so the same code can serve a future iOS/iPadOS target.
public enum KeyrussoPreset: String, CaseIterable, Codable, Sendable {
    case main, confidence, stage, lobby, ndi, obs

    public static let defaultBase = URL(string: "http://127.0.0.1:8765")!

    public var title: String {
        switch self {
        case .main: return "Keyrusso Main"
        case .confidence: return "Keyrusso Confidence"
        case .stage: return "Keyrusso Stage"
        case .lobby: return "Keyrusso Lobby"
        case .ndi: return "Keyrusso NDI®"
        case .obs: return "Keyrusso OBS"
        }
    }

    /// The booth's default path for this screen (`displays.<role>.path`).
    public var defaultPath: String {
        switch self {
        case .main: return "/present"
        default: return "/" + rawValue
        }
    }

    /// NDI and OBS are program feeds, so they start with NDI output on.
    public var sendsToNDI: Bool { self == .ndi || self == .obs }

    public func view(base: URL, path: String? = nil, ndiName: String? = nil, displayIDs: Set<String> = [],
                     ndiEnabled: Bool? = nil) throws -> ViewConfig {
        let url = try KeyrussoServer.url(base: base, path: path ?? defaultPath)
        let id = UUID()
        let name = ndiName ?? title + " " + String(id.uuidString.prefix(8))
        return ViewConfig(id: id, name: title, kind: .custom, customURL: url.absoluteString,
                          outputs: ViewOutputs(displayIDs: displayIDs, ndiEnabled: ndiEnabled ?? sendsToNDI,
                                               ndiSourceName: name))
    }
}

public enum KeyrussoServer {
    /// A booth origin is http(s), has a host, and carries no credentials, path or query.
    public static func normalizedBase(_ text: String) throws -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: trimmed), let scheme = parts.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/",
              let url = URL(string: "\(scheme)://\(host)\(parts.port.map { ":\($0)" } ?? "")") else {
            throw ViewConfigError.invalid("Enter the Keyrusso server as http://host:port")
        }
        return url
    }

    static func url(base: URL, path: String) throws -> URL {
        guard path.hasPrefix("/"), !path.hasPrefix("//"), !path.contains("?"), !path.contains("#"),
              let url = URL(string: path, relativeTo: base)?.absoluteURL else {
            throw ViewConfigError.invalid("A Keyrusso path must start with one /")
        }
        return url
    }

    public static func displayMapURL(base: URL) throws -> URL {
        try url(base: base, path: "/api/display-map")
    }
}

/// Keyrusso's `GET /api/display-map` answer: each input URL with the screen
/// number and/or NDI sender it should go to.
public struct KeyrussoDisplayMap: Decodable, Equatable, Sendable {
    public struct Sender: Decodable, Equatable, Sendable {
        public let name: String
        public let width: Int
        public let height: Int
        public let fps: Int
    }

    public struct Entry: Decodable, Equatable, Sendable {
        public let input: String
        public let label: String
        public let url: String
        public let screen: Int?
        public let ndi: Sender?
    }

    private struct Envelope: Decodable { let displayMap: Body }
    private struct Body: Decodable { let entries: [Entry] }

    public let entries: [Entry]

    public init(entries: [Entry]) { self.entries = entries }

    public init(from decoder: Decoder) throws {
        entries = try Envelope(from: decoder).displayMap.entries
    }

    public static func decode(_ data: Data) throws -> KeyrussoDisplayMap {
        do { return try JSONDecoder().decode(KeyrussoDisplayMap.self, from: data) }
        catch { throw ViewConfigError.invalid("That server did not return a Keyrusso display map") }
    }

    /// One custom view per entry. "Display N" is the Nth connected display in
    /// the order given; a screen number with no display attached is left
    /// unassigned and the view stays in the list.
    public func views(displayIDs: [String]) throws -> [ViewConfig] {
        try entries.map { entry in
            guard let url = URL(string: entry.url), let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  parts.host?.isEmpty == false, parts.user == nil, parts.password == nil else {
                throw ViewConfigError.invalid("The display map has a URL that is not http(s): \(entry.url)")
            }
            var outputs = ViewOutputs()
            if let screen = entry.screen, screen >= 1, screen <= displayIDs.count {
                outputs.displayIDs = [displayIDs[screen - 1]]
            }
            if let ndi = entry.ndi {
                outputs.ndiEnabled = true
                outputs.ndiSourceName = ndi.name
            }
            let name = entry.label.trimmingCharacters(in: .whitespacesAndNewlines)
            return ViewConfig(name: name.isEmpty ? entry.input : "Keyrusso " + name, kind: .custom,
                              customURL: url.absoluteString, outputs: outputs)
        }
    }
}
