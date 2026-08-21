import Foundation

struct SamplingPolicy {
    static func resolve(
        preferences: PreferencesSnapshot,
        popoverVisible: Bool,
        lowPower: Bool,
        sleeping: Bool
    ) -> [ProviderID: TimeInterval] {
        guard !sleeping else { return [:] }
        let activePeriod = lowPower ? max(5, preferences.sampling.refreshInterval) : preferences.sampling.refreshInterval
        let displayedMetrics = Set(preferences.displayedMetrics)
        let samplesCPU = popoverVisible
            || displayedMetrics.contains(.cpu)
            || (preferences.alerts.enabled && preferences.alerts.enabledKinds.contains(.cpu))
        let samplesMemory = popoverVisible
            || displayedMetrics.contains(.memory)
            || (preferences.alerts.enabled && preferences.alerts.enabledKinds.contains(.memory))
        let samplesBattery = popoverVisible
            || displayedMetrics.contains(.battery)
            || (preferences.alerts.enabled
                && (preferences.alerts.enabledKinds.contains(.batteryLevel)
                    || preferences.alerts.enabledKinds.contains(.batteryTemperature)))
        let networkPeriod: TimeInterval
        if displayedMetrics.contains(.network) {
            networkPeriod = activePeriod
        } else if popoverVisible {
            networkPeriod = lowPower ? activePeriod : min(1, activePeriod)
        } else {
            networkPeriod = 30
        }
        let samplesDisk = popoverVisible
            || displayedMetrics.contains(.disk)
            || (preferences.alerts.enabled && preferences.alerts.enabledKinds.contains(.diskFree))
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
        result[.network] = networkPeriod
        if samplesDisk {
            result[.disk] = lowPower ? 120 : 60
        }
        return result
    }
}
