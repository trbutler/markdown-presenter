import SwiftUI
import PresenterCore

// VERIFY-ON-MAC: build List selection/move, bindings, Form and NSHostingController
// integration with the macOS 27 SwiftUI SDK; no earlier-system UI fallback.
@MainActor
struct ViewPreferences: View {
    let store: ViewStore
    @State private var selection: UUID? = nil
    @State private var showsServerSheet = false

    init(store: ViewStore) { self.store = store }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(store.list.views) { config in
                        ViewListRow(config: config).tag(config.id)
                            .contextMenu { rowMenu(config) }
                    }.onMove { store.move($0, to: $1) }
                }
                .listStyle(.sidebar)
                .onDeleteCommand(perform: removeSelection)
                Divider()
                ViewListBar(store: store, selection: $selection, showsServerSheet: $showsServerSheet,
                            remove: removeSelection)
            }
            .frame(minWidth: 200, idealWidth: 230, maxWidth: 300)
            VStack(alignment: .leading, spacing: 8) {
                if let config = store.list.views.first(where: { $0.id == selection }) {
                    ViewEditor(store: store, config: config).id(config.id)
                } else {
                    ContentUnavailableView("No View Selected", systemImage: "display",
                        description: Text("Select a view to choose its displays and NDI output."))
                }
                if let error = store.error { Text(error).foregroundStyle(.red).textSelection(.enabled).padding(.horizontal) }
            }
            .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 780, minHeight: 540)
        .sheet(isPresented: $showsServerSheet) { KeyrussoServerSheet(store: store) }
    }

    private func removeSelection() {
        guard let id = selection else { return }
        store.remove(id)
        selection = nil
    }

    @ViewBuilder private func rowMenu(_ config: ViewConfig) -> some View {
        let index = store.list.views.firstIndex { $0.id == config.id }
        Button("Move Up") { if let index { store.move(IndexSet(integer: index), to: index - 1) } }
            .disabled(index == nil || index == 0)
        Button("Move Down") { if let index { store.move(IndexSet(integer: index), to: index + 2) } }
            .disabled(index == nil || index == store.list.views.count - 1)
        Divider()
        Button("Remove", role: .destructive) { store.remove(config.id); if selection == config.id { selection = nil } }
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

/// The source-list footer: "+" and "-" at the bottom, as in Finder or System Settings.
@MainActor
private struct ViewListBar: View {
    let store: ViewStore
    @Binding var selection: UUID?
    @Binding var showsServerSheet: Bool
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            AddViewMenu(store: store, selection: $selection, showsServerSheet: $showsServerSheet)
            Button(action: remove) { Label("Remove View", systemImage: "minus") }
                .disabled(selection == nil)
                .help("Remove the selected view")
            Spacer()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }
}

private struct ViewListRow: View {
    let config: ViewConfig

    private var detail: String {
        guard config.kind == .custom, let text = config.customURL, let url = URL(string: text), !url.isFileURL,
              let host = url.host else { return config.kind.title }
        return host + url.path
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text(config.name)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
