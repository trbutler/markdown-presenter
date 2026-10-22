/// Presentation-clicker / PowerPoint / Proclaim key bindings, expressed with
/// macOS virtual key codes (Carbon `kVK_*` values) so this file needs no AppKit.
///
/// Next:  Right, Down, Page Down, Space
/// Back:  Left, Up, Page Up
/// Black: B or "." (the blank button on most clickers sends one of these)
/// Jump:  Home, End
public enum KeyMap {
    public enum KeyCode {
        public static let space: UInt16 = 0x31
        public static let leftArrow: UInt16 = 0x7B
        public static let rightArrow: UInt16 = 0x7C
        public static let downArrow: UInt16 = 0x7D
        public static let upArrow: UInt16 = 0x7E
        public static let pageUp: UInt16 = 0x74
        public static let pageDown: UInt16 = 0x79
        public static let home: UInt16 = 0x73
        public static let end: UInt16 = 0x77
    }

    /// - Parameters:
    ///   - keyCode: `NSEvent.keyCode`
    ///   - characters: `NSEvent.charactersIgnoringModifiers`, used for letter
    ///     keys so B works on any keyboard layout.
    ///   - hasCommandModifiers: true when Command, Control or Option is held;
    ///     those chords are left alone so menu shortcuts keep working.
    public static func command(keyCode: UInt16, characters: String?, hasCommandModifiers: Bool = false) -> DeckCommand? {
        if hasCommandModifiers {
            return nil
        }
        switch keyCode {
        case KeyCode.rightArrow, KeyCode.downArrow, KeyCode.pageDown, KeyCode.space:
            return .next
        case KeyCode.leftArrow, KeyCode.upArrow, KeyCode.pageUp:
            return .previous
        case KeyCode.home:
            return .first
        case KeyCode.end:
            return .last
        default:
            break
        }
        switch characters?.lowercased() {
        case "b", ".":
            return .toggleBlack
        default:
            return nil
        }
    }
}
