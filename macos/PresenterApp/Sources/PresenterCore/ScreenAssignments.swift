/// One connected display, described without AppKit so the assignment rules
/// are testable. `id` is the display's CoreGraphics UUID string, which is
/// stable across reboots and re-plugging (unlike CGDirectDisplayID).
public struct DisplayInfo: Equatable, Sendable {
    public let id: String
    public let name: String
    /// The menu-bar display (`NSScreen.screens.first`).
    public let isPrimary: Bool

    public init(id: String, name: String, isPrimary: Bool) {
        self.id = id
        self.name = name
        self.isPrimary = isPrimary
    }
}

/// Which display each view goes on. Persisted as JSON in UserDefaults.
///
/// A saved choice whose display is unplugged is kept, not overwritten: the
/// view falls back to the automatic rule until that display returns, then
/// moves back by itself (hot-plug).
public struct ScreenAssignments: Codable, Equatable, Sendable {
    /// role raw value -> display id. A missing entry means "Automatic".
    public var byRole: [String: String]

    public init(byRole: [String: String] = [:]) {
        self.byRole = byRole
    }

    public mutating func assign(_ role: ViewRole, to displayID: String?) {
        byRole[role.rawValue] = displayID
    }

    public func savedDisplayID(for role: ViewRole) -> String? {
        byRole[role.rawValue]
    }

    public func resolve(_ role: ViewRole, among displays: [DisplayInfo]) -> DisplayInfo? {
        if let id = byRole[role.rawValue], let saved = displays.first(where: { $0.id == id }) {
            return saved
        }
        return ScreenAssignments.automatic(role, among: displays)
    }

    /// Automatic placement: controls on the laptop, audience on the first
    /// external display (projector), confidence on the second external display
    /// if there is one, else on the laptop beside the controls.
    public static func automatic(_ role: ViewRole, among displays: [DisplayInfo]) -> DisplayInfo? {
        let primary = displays.first(where: { $0.isPrimary }) ?? displays.first
        let externals = displays.filter { !$0.isPrimary }
        switch role {
        case .control:
            return primary
        case .audience:
            return externals.first ?? primary
        case .confidence:
            return externals.count >= 2 ? externals[1] : primary
        case .overlay:
            return nil
        }
    }
}
