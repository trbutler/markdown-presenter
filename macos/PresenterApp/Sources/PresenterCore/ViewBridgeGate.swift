import Foundation

/// Native instance identity is authoritative; JavaScript view names are never used.
/// Only the first registered canonical page for a saved view may control it.
public struct ViewBridgeGate: Sendable {
    private struct Instance: Sendable {
        let viewID: UUID
        let audienceRendering: Bool
    }
    private var list = ViewList()
    private var instances: [UUID: Instance] = [:]
    private var canonical: [UUID: UUID] = [:]

    public init() {}
    public mutating func configure(_ list: ViewList) { self.list = list }

    public mutating func register(instanceID: UUID, viewID: UUID, isCanonical: Bool, audienceRendering: Bool) {
        unregister(instanceID)
        instances[instanceID] = Instance(viewID: viewID, audienceRendering: audienceRendering)
        if isCanonical && canonical[viewID] == nil { canonical[viewID] = instanceID }
    }

    public mutating func unregister(_ instanceID: UUID) {
        if let old = instances.removeValue(forKey: instanceID), canonical[old.viewID] == instanceID {
            canonical[old.viewID] = nil
        }
    }

    public func permitsMIDI(from instanceID: UUID, isMainFrame: Bool = true) -> Bool {
        guard isMainFrame, let instance = instances[instanceID],
              canonical[instance.viewID] == instanceID else { return false }
        // primaryMainID derives from kind, so even a Custom URL pointing at the
        // deck with view=audience cannot acquire MIDI authority.
        return list.primaryMainID == instance.viewID
    }

    public func permitsRequest(from instanceID: UUID, isMainFrame: Bool = true) -> Bool {
        guard isMainFrame, let instance = instances[instanceID],
              canonical[instance.viewID] == instanceID,
              let view = list.views.first(where: { $0.id == instance.viewID }),
              view.kind != .custom else { return false }
        return !instance.audienceRendering || permitsMIDI(from: instanceID)
    }
}
