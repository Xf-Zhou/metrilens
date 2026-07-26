import Foundation

enum MetricVisualSeverity: Int, Comparable {
    case normal
    case caution
    case warning
    case critical

    static func < (lhs: MetricVisualSeverity, rhs: MetricVisualSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum MetricPresentationPolicy {
    static func temperatureSeverity(_ celsius: Double) -> MetricVisualSeverity {
        switch celsius {
        case ..<38: return .normal
        case ..<42: return .caution
        case ..<45: return .warning
        default: return .critical
        }
    }

    static func thermalSeverity(_ level: ThermalLevel) -> MetricVisualSeverity {
        switch level {
        case .nominal: return .normal
        case .fair: return .caution
        case .serious: return .warning
        case .critical: return .critical
        }
    }
}
