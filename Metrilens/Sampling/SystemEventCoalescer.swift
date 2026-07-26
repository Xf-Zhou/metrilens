import Foundation

struct SystemEventCoalescer {
    let window: TimeInterval
    private(set) var lastAcceptedUptime: TimeInterval = -.infinity

    init(window: TimeInterval = 2) {
        self.window = window
    }

    mutating func shouldAccept(at uptime: TimeInterval) -> Bool {
        guard uptime - lastAcceptedUptime >= window else {
            return false
        }
        lastAcceptedUptime = uptime
        return true
    }
}
