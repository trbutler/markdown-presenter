import SwiftUI
import PresenterCore

// VERIFY-ON-MAC: build List selection/move, bindings, Form and NSHostingController
// integration with the macOS 27 SwiftUI SDK; no earlier-system UI fallback.
@MainActor
struct ViewPreferences: View {
    let store: ViewStore
    @State private var selection: UUID? = nil

    init(store: ViewStore) { self.store = store }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewListToolbar(store: store, selection: $selection)
            HStack(alignment: .top) {
                List(selection: $selection) {
                    ForEach(store.list.views) { config in
                        ViewListRow(name: config.name, kind: config.kind.title).tag(config.id)
                    }.onMove { store.move($0, to: $1) }
                }.frame(minWidth: 200, maxWidth: 260)
                if let config = store.list.views.first(where: { $0.id == selection }) {
                    ViewEditor(store: store, config: config).id(config.id)
                } else {
                    Text("Select a view to choose its displays and NDI output.").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if let error = store.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
        }
        .padding()
        .frame(minWidth: 780, minHeight: 540)
    }
}

@MainActor
private struct ViewEditor: View {
    let store: ViewStore
    @State private var draft: ViewConfig
    @State private var queryText: String
    @State private var queryError: String? = nil

    init(store: ViewStore, config: ViewConfig) {
        self.store = store
        // VERIFY-ON-MAC: SDK 27 @State macro uses init accessors; no declaration
        // default or legacy backing-wrapper assignment for these draft values.
        self.draft = config
        var query = URLComponents()
        query.queryItems = config.query.keys.sorted().map { URLQueryItem(name: $0, value: config.query[$0]) }
        self.queryText = query.percentEncodedQuery ?? ""
    }

    var body: some View {
        Form {
            TextField("Name", text: $draft.name)
            Text(draft.kind.title)
            if draft.kind == .custom {
                TextField("URL", text: Binding(get: { draft.customURL ?? "" }, set: { draft.customURL = $0 }))
                Text("Only the deck's own file URL receives presentation controls.").font(.caption)
            } else {
                Text("Deck query: ?view=\(draft.kind.queryView ?? "")")
                TextField("Extra query (e.g. chrome=0)", text: $queryText)
            }
            ViewDisplayChoices(store: store, viewID: draft.id, displayIDs: $draft.outputs.displayIDs)
            NDIOutputControls(outputs: $draft.outputs, status: store.outputStatus[draft.id] ?? "NDI off")
            if let queryError = queryError { Text(queryError).foregroundStyle(.red) }
            Button("Apply") { apply() }
        }.formStyle(.grouped)
    }

    private func apply() {
        if draft.kind != .custom {
            guard let components = URLComponents(string: "https://query.invalid/?" + queryText), components.fragment == nil else {
                queryError = "Invalid query"; return
            }
            let items = components.queryItems ?? []
            guard Set(items.map(\.name)).count == items.count else { queryError = "Duplicate query keys"; return }
            draft.query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        }
        queryError = nil
        store.apply(draft)
    }
}

@MainActor
private struct ViewListToolbar: View {
    let store: ViewStore
    @Binding var selection: UUID?
    private var selectedIndex: Int? { store.list.views.firstIndex { $0.id == selection } }
    var body: some View {
        HStack {
            Text("Views").font(.title2)
            Spacer()
            Menu {
                ForEach(ViewKind.allCases, id: \.self) { kind in
                    Button(kind.title) { selection = store.add(kind) }
                }
            } label: { Image(systemName: "plus") }
            .help("Add a view")
            Button { if let selection = selection { store.remove(selection); self.selection = nil } } label: { Image(systemName: "minus") }
                .disabled(selection == nil)
            Button("Up") { if let index = selectedIndex { store.move(IndexSet(integer: index), to: index - 1) } }
                .disabled((selectedIndex ?? 0) == 0)
            Button("Down") { if let index = selectedIndex { store.move(IndexSet(integer: index), to: index + 2) } }
                .disabled(selectedIndex == nil || selectedIndex == store.list.views.count - 1)
        }
    }
}

private struct ViewListRow: View {
    let name: String
    let kind: String
    var body: some View {
        VStack(alignment: .leading) {
            Text(name)
            Text(kind).font(.caption).foregroundStyle(.secondary)
        }
    }
}

@MainActor
private struct ViewDisplayChoices: View {
    let store: ViewStore
    let viewID: UUID
    @Binding var displayIDs: Set<String>

    private func displayBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { displayIDs.contains(id) }, set: { enabled in
            if enabled { displayIDs.insert(id) } else { displayIDs.remove(id) }
        })
    }

    var body: some View {
        Section("Displays") {
            ForEach(store.displays, id: \.id) { display in
                Toggle(isOn: displayBinding(display.id)) {
                    VStack(alignment: .leading) {
                        Text(display.name)
                        if let owner = store.list.displayOwner(display.id), owner != viewID {
                            Text("Claimed by \(store.list.views.first { $0.id == owner }?.name ?? "another view"); earlier view wins")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            ForEach(displayIDs.subtracting(Set(store.displays.map(\.id))).sorted(), id: \.self) { id in
                Toggle("Disconnected display: \(id)", isOn: displayBinding(id))
            }
            Text("Assignments resume on reconnect. Earlier views win conflicting claims.").font(.caption)
        }
    }
}

private struct NDIOutputControls: View {
    @Binding var outputs: ViewOutputs
    let status: String
    var body: some View {
        Section("NDI®") {
            Toggle("Send this view to NDI", isOn: $outputs.ndiEnabled)
            TextField("Source name", text: $outputs.ndiSourceName)
            Text(status).font(.caption)
            if let url = URL(string: "https://ndi.video") { Link("NDI® is a registered trademark of Vizrt NDI AB — ndi.video", destination: url) }
        }
    }
}
