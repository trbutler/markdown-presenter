import AppKit
import PresenterCore

/// Routes clicker/keyboard keys from whichever app window is key to the
/// controller, so all windows behave identically and the deck's own JS key
/// handler never double-advances (the template skips it when in-app).
@MainActor
final class KeyRouter {
    /// Kept for the app's lifetime; the router is never torn down.
    private var monitor: Any?

    init(controller: DeckController) {
        // VERIFY-ON-MAC: local event monitor isolation/main-thread callback contract.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak controller] event in
            // Preferences and untrusted Custom pages retain their normal keys.
            guard MainActor.assumeIsolated({ controller?.ownsFocusedWindow == true }) else { return event }
            let chord = !event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            guard let command = KeyMap.command(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers, hasCommandModifiers: chord) else {
                return event
            }
            Task { @MainActor in
                controller?.perform(command)
            }
            return nil
        }
    }
}
