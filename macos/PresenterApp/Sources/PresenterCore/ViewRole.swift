/// Bridge vocabulary retained for ready messages; view identity is ViewConfig.id. Raw values match the template's
/// `?view=` parameter and `window.__presenterView`. In the template,
/// `confidence` is an alias of its `notes` view and `control` of its
/// `service` view; `overlay` shows lower thirds and the countdown only
/// (the template's `lyrics` view is the words-only alternative).
public enum ViewRole: String, CaseIterable, Codable, Sendable {
    case audience
    case confidence
    case control
    case overlay

    public var title: String {
        switch self {
        case .audience: return "Audience"
        case .confidence: return "Confidence Monitor"
        case .control: return "Presenter Controls"
        case .overlay: return "Overlay (NDI)"
        }
    }
}
