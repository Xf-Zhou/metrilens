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
        let displayedMetrics = Set(preferences.displayedMetrics)
        let samplesCPU = popoverVisible
            || displayedMetrics.contains(.cpu)
            || preferences.alertsEnabled
        let samplesMemory = popoverVisible
            || displayedMetrics.contains(.memory)
            || preferences.alertsEnabled
        let samplesBattery = displayedMetrics.contains(.battery)
        var result: [ProviderID: TimeInterval] = [:]
        if popoverVisible || samplesBattery {
            if lowPower {
                result[.battery] = 120
            } else if popoverVisible {
                result[.battery] = 10
            } else {
                result[.battery] = 30
            }
        }
        if samplesCPU {
            result[.cpu] = activePeriod
        }
        if samplesMemory {
            result[.memory] = activePeriod
        }
        return result
    }
}
