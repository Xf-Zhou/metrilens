import Foundation

enum AppLanguage: String, CaseIterable {
    case system
    case simplifiedChinese
    case english

    var resolved: AppLanguage {
        guard self == .system else { return self }
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return preferred.hasPrefix("zh") ? .simplifiedChinese : .english
    }

    func text(_ chinese: String, _ english: String) -> String {
        resolved == .simplifiedChinese ? chinese : english
    }

}

enum AppText {
    static func languageName(
        _ option: AppLanguage,
        interfaceLanguage: AppLanguage
    ) -> String {
        switch option {
        case .system:
            return interfaceLanguage.text("跟随系统", "System Default")
        case .simplifiedChinese:
            return "简体中文"
        case .english:
            return "English"
        }
    }

    static func metricName(_ metric: PrimaryMetric, language: AppLanguage) -> String {
        switch metric {
        case .cpu:
            return "CPU"
        case .memory:
            return language.text("内存", "Memory")
        case .battery:
            return language.text("电池", "Battery")
        case .network:
            return language.text("网络速率", "Network Speed")
        case .disk:
            return language.text("磁盘空间", "Disk Space")
        }
    }

    static func displayModeName(
        _ mode: StatusDisplayMode,
        language: AppLanguage
    ) -> String {
        switch mode {
        case .single:
            return language.text("单项", "Single")
        case .compact:
            return language.text("紧凑组合", "Compact")
        }
    }

    static func thermalName(_ level: ThermalLevel, language: AppLanguage) -> String {
        switch level {
        case .nominal: return language.text("正常", "Nominal")
        case .fair: return language.text("偏热", "Fair")
        case .serious: return language.text("严重", "Serious")
        case .critical: return language.text("危急", "Critical")
        }
    }

    static func failureReason(
        _ failure: MetricFailure,
        language: AppLanguage
    ) -> String {
        switch failure {
        case .noHardware:
            return language.text("无电池", "No Battery")
        case .noActiveInterface:
            return language.text("无活动网络", "No Active Network")
        case .fieldMissing:
            return language.text("系统未提供该字段", "Field Not Provided")
        case .unsupportedEncoding:
            return language.text("数据格式不支持", "Unsupported Data Format")
        case .counterOverflow:
            return language.text("计数器溢出", "Counter Overflow")
        case .outOfRange:
            return language.text("读数超出有效范围", "Reading Out of Range")
        case .outlierJump:
            return language.text("等待异常读数确认", "Confirming Unusual Reading")
        case .fileSystemFailure:
            return language.text("系统资源暂不可读", "System Resource Unavailable")
        case .iokitFailure:
            return language.text("电池接口暂不可读", "Battery Interface Unavailable")
        case .machFailure:
            return language.text("系统指标暂不可读", "System Metric Unavailable")
        }
    }
}
