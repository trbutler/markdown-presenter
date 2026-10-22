import Foundation

public enum ViewKind: String, CaseIterable, Codable, Sendable {
    case mainSlides
    case overlaySlides
    case presenter
    case custom

    public var title: String {
        switch self {
        case .mainSlides: return "Main Slides"
        case .overlaySlides: return "Overlay Slides"
        case .presenter: return "Presenter View"
        case .custom: return "Custom"
        }
    }

    public var queryView: String? {
        switch self {
        case .mainSlides: return "audience"
        case .overlaySlides: return "overlay"
        case .presenter: return "notes"
        case .custom: return nil
        }
    }
}

public struct ViewOutputs: Codable, Equatable, Sendable {
    public var displayIDs: Set<String>
    public var ndiEnabled: Bool
    public var ndiSourceName: String

    public init(displayIDs: Set<String> = [], ndiEnabled: Bool = false, ndiSourceName: String = "Presenter") {
        self.displayIDs = displayIDs
        self.ndiEnabled = ndiEnabled
        self.ndiSourceName = ndiSourceName
    }
}

public struct ViewConfig: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var kind: ViewKind
    public var customURL: String?
    public var query: [String: String]
    public var outputs: ViewOutputs

    public init(id: UUID = UUID(), name: String, kind: ViewKind, customURL: String? = nil,
                query: [String: String] = [:], outputs: ViewOutputs = ViewOutputs()) {
        self.id = id
        self.name = name
        self.kind = kind
        self.customURL = customURL
        self.query = query
        self.outputs = outputs
    }

    public static func preset(_ kind: ViewKind, deckURL: URL) -> ViewConfig {
        let id = UUID()
        return ViewConfig(id: id, name: kind.title, kind: kind,
                          customURL: kind == .custom ? deckURL.absoluteString : nil,
                          outputs: ViewOutputs(ndiSourceName: kind.title + " " + String(id.uuidString.prefix(8))))
    }

    public func resolvedURL(deckURL: URL) throws -> URL {
        if kind == .custom {
            guard let text = customURL, let url = URL(string: text) else {
                throw ViewConfigError.invalid("Custom requires an absolute URL")
            }
            try ViewURLPolicy.validate(url, deckURL: deckURL)
            return url.isFileURL ? ViewURLPolicy.canonicalFile(url) : url
        }
        guard deckURL.isFileURL, var components = URLComponents(url: deckURL, resolvingAgainstBaseURL: false) else {
            throw ViewConfigError.invalid("The deck must be a local file URL")
        }
        let reserved: Set<String> = ["view", "mute", "seed"]
        guard query.keys.allSatisfy({ !$0.isEmpty && !reserved.contains($0.lowercased()) }) else {
            throw ViewConfigError.invalid("view, mute and seed are reserved query keys")
        }
        var items = (components.queryItems ?? []).filter { !reserved.contains($0.name.lowercased()) && query[$0.name] == nil }
        items.append(contentsOf: query.keys.sorted().map { URLQueryItem(name: $0, value: query[$0]) })
        items.append(URLQueryItem(name: "view", value: kind.queryView))
        components.queryItems = items
        guard let url = components.url else { throw ViewConfigError.invalid("Invalid view query") }
        try ViewURLPolicy.validate(url, deckURL: deckURL)
        return ViewURLPolicy.canonicalFile(url)
    }
}

public enum ViewConfigError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let text): return text }
    }
}

public enum ViewURLPolicy {
    public static func canonicalFile(_ url: URL) -> URL {
        let file = URL(fileURLWithPath: url.path).resolvingSymlinksInPath().standardizedFileURL
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return file }
        parts.scheme = "file"
        parts.host = ""
        parts.path = file.path
        return parts.url ?? file
    }

    public static func validate(_ url: URL, deckURL: URL) throws {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = parts.scheme?.lowercased(), ["file", "http", "https"].contains(scheme),
              parts.user == nil, parts.password == nil else {
            throw ViewConfigError.invalid("Use file, http or https without embedded credentials")
        }
        if scheme != "file" {
            guard let host = parts.host, !host.isEmpty else { throw ViewConfigError.invalid("A remote URL needs a host") }
            return
        }
        guard deckURL.isFileURL, parts.host == nil || parts.host == "" || parts.host == "localhost" else {
            throw ViewConfigError.invalid("Only local files in the deck folder are allowed")
        }
        // Reject ambiguous symlink/.. traversal before normalizing or loading.
        let decodedPath = parts.percentEncodedPath.removingPercentEncoding ?? parts.path
        guard !decodedPath.split(separator: "/").contains("..") else {
            throw ViewConfigError.invalid("File view URLs cannot contain parent traversal")
        }
        let folder = canonicalFile(deckURL).deletingLastPathComponent().pathComponents
        guard canonicalFile(url).pathComponents.starts(with: folder) else {
            throw ViewConfigError.invalid("A file view must stay in the deck folder, including symlink targets")
        }
    }

    public static func allowsBridge(_ url: URL, deckURL: URL) -> Bool {
        guard url.isFileURL, (try? validate(url, deckURL: deckURL)) != nil else { return false }
        return canonicalFile(url).path == canonicalFile(deckURL).path
    }
}
