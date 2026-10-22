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
