import AppKit
import PresenterCore

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }

    /// Stable identity for persistence: the display's UUID survives reboots,
    /// re-plugging and port changes; CGDirectDisplayID does not.
    var displayUUID: String {
        guard let id = displayID, let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else {
            return "name:" + localizedName
        }
        return CFUUIDCreateString(nil, uuid) as String
    }

    static var displayInfos: [DisplayInfo] {
        let primaryID = NSScreen.screens.first?.displayUUID
        return NSScreen.screens.map { DisplayInfo(id: $0.displayUUID, name: $0.localizedName, isPrimary: $0.displayUUID == primaryID) }
    }

    static func screen(withUUID uuid: String?) -> NSScreen? {
        guard let uuid = uuid else {
            return nil
        }
        return NSScreen.screens.first { $0.displayUUID == uuid }
    }
}
