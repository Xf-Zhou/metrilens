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
            return language.text(
                "未发现异常发热迹象",
                "No abnormal heat indicators detected"
            )
        case .elevated:
            return language.text(
                "发现可能导致发热的状态",
                "Potential heat-producing conditions detected"
            )
        case .urgent:
            return language.text(
                "温度或热压力较高，请尽快处理",
                "Temperature or thermal pressure is high; act soon"
            )
        }
    }

    static func evidenceText(
        _ evidence: HeatEvidence,
        language: AppLanguage
    ) -> String {
        switch evidence {
        case .systemThermalPressure:
            return language.text(
                "macOS 报告严重热压力",
                "macOS reports serious thermal pressure"
            )
        case .sustainedCPU:
            return language.text(
                "CPU 当前或近期持续高占用",
                "CPU usage is currently or recently sustained at a high level"
            )
        case .hotBattery:
            return language.text(
                "电池温度达到较高水平",
                "Battery temperature has reached a high level"
            )
        case .chargingHeat:
            return language.text(
                "充电期间电池温度偏高",
                "Battery temperature is elevated while charging"
            )
        }
    }

    static func recommendationText(
        _ recommendation: HeatRecommendation,
        language: AppLanguage
    ) -> String {
        switch recommendation {
        case .inspectActivityMonitor:
            return language.text(
                "打开“活动监视器”的 CPU 页，检查并退出异常高占用 App",
                "Open Activity Monitor’s CPU tab and quit unusually busy apps"
            )
        case .reduceWorkload:
            return language.text(
                "暂停高负载任务并关闭暂时不用的 App",
                "Pause heavy work and close apps you are not using"
            )
        case .improveVentilation:
            return language.text(
                "将 Mac 放在坚硬、通风的表面并清除散热口遮挡",
                "Place the Mac on a hard, ventilated surface and clear airflow"
            )
        case .pauseCharging:
            return language.text(
                "条件允许时暂停充电并断开高功耗外设",
                "Pause charging and disconnect high-power accessories when practical"
            )
        case .enableLowPowerMode:
            return language.text(
                "可临时开启低电量模式以降低功耗",
                "Temporarily enable Low Power Mode to reduce power use"
            )
        case .coolAndSeekService:
            return language.text(
                "若危急状态或高温持续，停止使用并冷却；仍反复出现时联系 Apple",
                "If critical heat persists, stop and cool the Mac; contact Apple if it recurs"
            )
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
