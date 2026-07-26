import Foundation

struct SamplingPolicy {
    static func resolve(
        preferences: PreferencesSnapshot,
        popoverVisible: Bool,
        lowPower: Bool,
        sleeping: Bool
    ) -> [ProviderID: TimeInterval] {
        guard !sleeping else { return [:] }
        let activePeriod = lowPower ? max(5, preferences.refreshInterval) : preferences.refreshInterval
        let batteryPeriod: TimeInterval
        if lowPower {
            batteryPeriod = 120
        } else if popoverVisible {
            batteryPeriod = 10
        } else if preferences.primaryMetric == .battery {
            batteryPeriod = 30
        } else {
            batteryPeriod = 60
        }

        var result: [ProviderID: TimeInterval] = [.battery: batteryPeriod]
        if popoverVisible || preferences.primaryMetric == .cpu {
            result[.cpu] = activePeriod
        }
        if popoverVisible || preferences.primaryMetric == .memory {
            result[.memory] = activePeriod
        }
        return result
    }
}
