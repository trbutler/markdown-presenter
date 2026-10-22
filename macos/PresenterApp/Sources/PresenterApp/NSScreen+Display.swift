import AppKit
import PresenterCore

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }

    // VERIFY-ON-MAC: UUID ownership/import and reconnect identity on actual adapters.
    var displayUUID: String? {
        guard let id = displayID, let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    static var displayInfos: [DisplayInfo] {
        let primary = NSScreen.screens.first?.displayUUID
        return NSScreen.screens.compactMap { screen in
            guard let id = screen.displayUUID else { return nil }
            return DisplayInfo(id: id, name: screen.localizedName, isPrimary: id == primary)
        }
    }

    static func screen(withUUID uuid: String) -> NSScreen? {
        NSScreen.screens.first { $0.displayUUID == uuid }
    }
}
