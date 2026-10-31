import Foundation
import Network

final class TranscriptionQueue {
    var onNetworkRestored: (() -> Void)?

    private let monitor = NWPathMonitor()
    private let queueDispatch = DispatchQueue(label: "com.loudflow.network-monitor")
    private var pending = Set<UUID>()
    private var wasSatisfied = true

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let satisfied = path.status == .satisfied
            let restored = satisfied && !self.wasSatisfied
            self.wasSatisfied = satisfied
            if restored && !self.pending.isEmpty {
                DispatchQueue.main.async { self.onNetworkRestored?() }
            }
        }
        monitor.start(queue: queueDispatch)
    }

    deinit { monitor.cancel() }

    func enqueue(_ id: UUID) { pending.insert(id) }
    func dequeue(_ id: UUID) { pending.remove(id) }
    var isEmpty: Bool { pending.isEmpty }
}
