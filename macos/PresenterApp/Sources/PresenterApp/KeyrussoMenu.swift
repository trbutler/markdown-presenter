import SwiftUI
import PresenterCore

// SwiftUI only: nothing here touches AppKit, so an iOS/iPadOS target can
// reuse it with the same ViewStore API.

/// The "+" at the bottom of the display list. Custom URL first, then the
/// Keyrusso booth screens, then the stock deck views.
struct AddViewMenu: View {
    let store: ViewStore
    @Binding var selection: UUID?
    @Binding var showsServerSheet: Bool

    var body: some View {
        Menu {
            Button("Custom URL") { selection = store.add(.custom) }
            Section("Keyrusso") {
                ForEach(KeyrussoPreset.allCases, id: \.self) { preset in
                    Button(preset.title) { selection = store.addKeyrusso(preset) }
                }
                Button("All Screens from Server Map") { Task { await store.importKeyrussoMap() } }
                    .disabled(store.isImportingMap)
                Button("Keyrusso Server…") { showsServerSheet = true }
            }
            Section("Deck") {
                ForEach(ViewKind.allCases.filter { $0 != .custom }, id: \.self) { kind in
                    Button(kind.title) { selection = store.add(kind) }
                }
            }
        } label: {
            Label("Add View", systemImage: "plus")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .help("Add a view")
    }
}

struct KeyrussoServerSheet: View {
    let store: ViewStore
    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(store: ViewStore) {
        self.store = store
        _text = State(initialValue: store.keyrussoBase.absoluteString)
    }

    var body: some View {
        Form {
            TextField("Server", text: $text, prompt: Text("http://booth.local:8765"))
                .autocorrectionDisabled()
            Text("The Keyrusso booth that the Keyrusso presets and the server map read from.")
                .font(.caption).foregroundStyle(.secondary)
            if let error = store.error { Text(error).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
        .frame(minWidth: 380)
        .toolbar {
            ToolbarItem(cancellationAction: .automatic) { Button("Cancel", role: .cancel) { dismiss() } }
            ToolbarItem(confirmationAction: .automatic) {
                Button("Save") { if store.setKeyrussoServer(text) { dismiss() } }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }
}
