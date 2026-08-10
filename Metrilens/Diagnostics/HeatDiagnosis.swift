import Foundation

enum HeatDiagnosisSeverity: String, Equatable {
    case normal
    case elevated
    case urgent
}

enum HeatEvidence: String, Equatable {
    case systemThermalPressure
    case sustainedCPU
    case hotBattery
    case chargingHeat
}

enum HeatRecommendation: String, Equatable {
    case inspectActivityMonitor
    case reduceWorkload
    case improveVentilation
    case pauseCharging
    case enableLowPowerMode
    case coolAndSeekService
}

struct HeatDiagnosis: Equatable {
    let severity: HeatDiagnosisSeverity
    let evidence: [HeatEvidence]
    let recommendations: [HeatRecommendation]

    var isAbnormal: Bool { severity != .normal }
}

enum HeatDiagnosisAnalyzer {
    static func evaluate(_ snapshot: SystemSnapshot) -> HeatDiagnosis {
        var severity: HeatDiagnosisSeverity = .normal
        var evidence: [HeatEvidence] = []
        var recommendations: [HeatRecommendation] = []

        if snapshot.thermalLevel == .serious
            || snapshot.thermalLevel == .critical {
            evidence.append(.systemThermalPressure)
            severity = snapshot.thermalLevel == .critical ? .urgent : .elevated
            recommendations.append(contentsOf: [
                .reduceWorkload,
                .improveVentilation,
                .enableLowPowerMode
            ])
        }

        let cpuAverage = snapshot.cpuHistorySummary?.average
        let cpuCurrent = snapshot.cpu.freshValue?.percent
        if (cpuAverage ?? 0) >= 70 || (cpuCurrent ?? 0) >= 85 {
            evidence.append(.sustainedCPU)
            severity = HeatDiagnosisSeverity.max(severity, .elevated)
            recommendations.append(contentsOf: [
                .inspectActivityMonitor,
                .reduceWorkload
            ])
        }

        if let temperature = snapshot.batteryTemperature.freshValue,
           temperature >= 45 {
            evidence.append(.hotBattery)
            severity = .urgent
            recommendations.append(contentsOf: [
                .pauseCharging,
                .improveVentilation,
                .coolAndSeekService
            ])
        } else if let temperature = snapshot.batteryTemperature.freshValue,
                  temperature >= 38,
                  snapshot.battery.freshValue?.powerState == .charging {
            evidence.append(.chargingHeat)
            severity = HeatDiagnosisSeverity.max(severity, .elevated)
            recommendations.append(contentsOf: [
                .pauseCharging,
                .improveVentilation
            ])
        }

        if severity == .urgent {
            recommendations.insert(.coolAndSeekService, at: 0)
        }

        return HeatDiagnosis(
            severity: severity,
            evidence: orderedUnique(evidence),
            recommendations: orderedUnique(recommendations)
        )
    }

    static func summary(
        _ diagnosis: HeatDiagnosis,
        language: AppLanguage
    ) -> String {
        switch diagnosis.severity {
        case .normal:
            return language.localized("No abnormal heat indicators detected")
        case .elevated:
            return language.localized("Potential heat-producing conditions detected")
        case .urgent:
            return language.localized("Temperature or thermal pressure is high; act soon")
        }
    }

    static func evidenceText(
        _ evidence: HeatEvidence,
        language: AppLanguage
    ) -> String {
        switch evidence {
        case .systemThermalPressure:
            return language.localized("macOS reports serious thermal pressure")
        case .sustainedCPU:
            return language.localized("CPU usage is currently or recently sustained at a high level")
        case .hotBattery:
            return language.localized("Battery temperature has reached a high level")
        case .chargingHeat:
            return language.localized("Battery temperature is elevated while charging")
        }
    }

    static func recommendationText(
        _ recommendation: HeatRecommendation,
        language: AppLanguage
    ) -> String {
        switch recommendation {
        case .inspectActivityMonitor:
            return language.localized("Open Activity Monitor’s CPU tab and quit unusually busy apps")
        case .reduceWorkload:
            return language.localized("Pause heavy work and close apps you are not using")
        case .improveVentilation:
            return language.localized("Place the Mac on a hard, ventilated surface and clear airflow")
        case .pauseCharging:
            return language.localized("Pause charging and disconnect high-power accessories when practical")
        case .enableLowPowerMode:
            return language.localized("Temporarily enable Low Power Mode to reduce power use")
        case .coolAndSeekService:
            return language.localized("If critical heat persists, stop and cool the Mac; contact Apple if it recurs")
        }
    }

    private static func orderedUnique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        return values.filter { seen.insert($0).inserted }
    }
}

private extension HeatDiagnosisSeverity {
    static func max(
        _ lhs: HeatDiagnosisSeverity,
        _ rhs: HeatDiagnosisSeverity
    ) -> HeatDiagnosisSeverity {
        let order: [HeatDiagnosisSeverity] = [.normal, .elevated, .urgent]
        return (order.firstIndex(of: lhs) ?? 0) >= (order.firstIndex(of: rhs) ?? 0)
            ? lhs
            : rhs
    }
}
