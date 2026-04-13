import Foundation

final class SyncScheduler {
    private var timer: Timer?
    private let action: @Sendable () -> Void

    init(action: @escaping @Sendable () -> Void) {
        self.action = action
    }

    func start(frequency: SyncFrequency) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: frequency.interval, repeats: true) { [action] _ in
            action()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        stop()
    }
}
