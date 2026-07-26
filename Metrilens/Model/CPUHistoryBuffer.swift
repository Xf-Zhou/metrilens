import Foundation

struct MetricHistorySummary: Equatable {
    let average: Double
    let peak: Double
}

struct MetricHistoryBuffer {
    private(set) var points: [MetricHistoryPoint] = []
    private var collectionStartedAt: TimeInterval?
    let window: TimeInterval
    let capacity: Int

    init(window: TimeInterval = 60, capacity: Int = 64) {
        self.window = window
        self.capacity = capacity
        points.reserveCapacity(capacity)
    }

    mutating func append(percent: Double, at uptime: TimeInterval) {
        if collectionStartedAt == nil {
            collectionStartedAt = uptime
        }
        prune(now: uptime)
        if points.count == capacity {
            points.removeFirst()
        }
        points.append(MetricHistoryPoint(uptime: uptime, percent: percent))
    }

    mutating func values(now: TimeInterval) -> [MetricHistoryPoint] {
        prune(now: now)
        return points
    }

    mutating func summary(now: TimeInterval) -> MetricHistorySummary? {
        prune(now: now)
        guard !points.isEmpty else { return nil }
        let percentages = points.map(\.percent)
        return MetricHistorySummary(
            average: percentages.reduce(0, +) / Double(percentages.count),
            peak: percentages.max() ?? 0
        )
    }

    mutating func clear() {
        points.removeAll(keepingCapacity: true)
        collectionStartedAt = nil
    }

    func isCollecting(now: TimeInterval) -> Bool {
        guard let collectionStartedAt else { return true }
        return now - collectionStartedAt < window
    }

    private mutating func prune(now: TimeInterval) {
        let cutoff = now - window
        guard let firstValid = points.firstIndex(where: { $0.uptime >= cutoff }) else {
            points.removeAll(keepingCapacity: true)
            return
        }
        if firstValid > 0 {
            points.removeFirst(firstValid)
        }
    }
}

typealias CPUHistoryBuffer = MetricHistoryBuffer
