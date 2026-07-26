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
            || (preferences.alertsEnabled && preferences.cpuAlertEnabled)
        let samplesMemory = popoverVisible
            || displayedMetrics.contains(.memory)
            || (preferences.alertsEnabled && preferences.memoryAlertEnabled)
        let samplesBattery = popoverVisible
            || displayedMetrics.contains(.battery)
            || (preferences.alertsEnabled
                && (preferences.batteryLevelAlertEnabled
                    || preferences.batteryTemperatureAlertEnabled))
        let samplesNetwork = popoverVisible || displayedMetrics.contains(.network)
        let samplesDisk = popoverVisible
            || displayedMetrics.contains(.disk)
            || (preferences.alertsEnabled && preferences.diskFreeAlertEnabled)
        var result: [ProviderID: TimeInterval] = [:]
        if samplesBattery {
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
        if samplesNetwork {
            result[.network] = activePeriod
        }
        if samplesDisk {
            result[.disk] = lowPower ? 120 : 60
        }
        return result
    }
}
