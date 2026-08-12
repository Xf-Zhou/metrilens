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

    func localized(_ key: String) -> String {
        AppTextCatalog.localized(key, language: resolved)
    }

    func localized(_ key: String, arguments: CVarArg...) -> String {
        String(
            format: localized(key),
            locale: Locale(identifier: resolved == .simplifiedChinese ? "zh_CN" : "en_US"),
            arguments: arguments
        )
    }
}

enum AppTextCatalog {
    static let keys: Set<String> = Set(chineseTranslations.keys)

    static var validationFailures: [String] {
        var failures: [String] = []
        for (key, chinese) in chineseTranslations {
            let english = englishOverrides[key] ?? key
            if key.isEmpty || chinese.isEmpty || english.isEmpty {
                failures.append("empty:\(key)")
            }
            if formatSpecifiers(in: chinese) != formatSpecifiers(in: english) {
                failures.append("format:\(key)")
            }
        }
        for key in englishOverrides.keys where chineseTranslations[key] == nil {
            failures.append("orphan:\(key)")
        }
        return failures.sorted()
    }

    static func localized(_ key: String, language: AppLanguage) -> String {
        guard let chinese = chineseTranslations[key] else {
            assertionFailure("Missing localization key: \(key)")
            return englishOverrides[key] ?? key
        }
        return language == .simplifiedChinese
            ? chinese
            : englishOverrides[key] ?? key
    }

    private static func formatSpecifiers(in value: String) -> [String] {
        let pattern = #"%(?:\d+\$)?(?:[-+0 #]*)?(?:\d+|\*)?(?:\.\d+|\.\*)?[hlLzjtq]*[@a-zA-Z%]"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(value.startIndex..., in: value)
        return expression.matches(in: value, range: range).compactMap {
            Range($0.range, in: value).map { String(value[$0]) }
        }.filter { $0 != "%%" }
    }

    private static let englishOverrides: [String: String] = [
        "about.version": "Version %@ (%@)",
        "alert.highBatteryTemperature": "High Battery Temperature",
        "alert.currentThermalState": "Current state: %@",
        "batteryHealth.fair": "Fair",
        "diagnostics.privacyDisclosure": "Diagnostics include only the app version and build, macOS version, architecture, Low Power Mode, app settings, sampling state, metric state, and recent metric read errors. They do not include usernames, hostnames, serial numbers, file paths, process IDs, or network addresses.",
        "language.simplifiedChinese": "简体中文",
        "popover.updated": "Updated %@",
        "preferences.decimalPlaces": "%d decimal places",
        "preferences.seconds": "%d sec",
        "preferences.sourceInformation": "Temperature: Metrilens reads AppleSmartBattery battery temperature only. It separates the resettable session maximum from the device lifetime maximum. Precise CPU/GPU temperature is outside the current scope.\n\nMemory: “Metrilens Memory” is internal + wired + compressor memory. This stable product definition may differ from Activity Monitor.",
        "settings.highBatteryTemperature": "High Battery Temperature",
        "sparkline.accessibilityLabel": "%@ usage over the last 60 seconds",
        "status.staleTooltip": "Metrilens System Status\nData is stale; sampled at %@",
        "thermal.fair": "Fair"
    ]

    private static let chineseTranslations: [String: String] = [
        " · Stale": " · 已过期",
        "%d samples, current %.1f%%%@%@": "%d 个样本，当前 %.1f%%%@%@",
        ", average %.1f%%, peak %.1f%%": "，平均 %.1f%%，峰值 %.1f%%",
        ", data is stale": "，数据已过期",
        ", still collecting": "，仍在收集",
        ", display range %.0f to %.0f%%": "，显示范围 %.0f 至 %.0f%%",
        ", system thermal warning": "，系统热状态警告",
        "A lightweight, privacy-first Apple Silicon menu bar system monitor.": "轻量、隐私优先的 Apple Silicon 菜单栏系统状态查看器。",
        "Abnormal Heat Diagnosis": "异常发热诊断",
        "About Metrilens": "关于 Metrilens",
        "Allow Metrilens in System Settings → General → Login Items.": "请在“系统设置 → 通用 → 登录项”中允许 Metrilens。",
        "Allowed": "已允许",
        "Alerts": "提醒",
        "Average %.1f%% · Peak %.1f%%": "平均 %.1f%% · 峰值 %.1f%%",
        "Average — · Peak —": "平均 — · 峰值 —",
        "Bar (|)": "竖线（|）",
        "Batt": "电池",
        "Battery": "电池",
        "Battery Health": "电池健康",
        "Battery Interface Unavailable": "电池接口暂不可读",
        "Battery Level": "电池电量",
        "Battery Temperature": "电池温度",
        "Battery Temperature Threshold": "电池温度阈值",
        "Battery level is %.0f%%": "当前剩余电量 %.0f%%",
        "Battery temperature has reached a high level": "电池温度达到较高水平",
        "Battery temperature is %.1f°C": "当前电池温度 %.1f°C",
        "Battery temperature is elevated while charging": "充电期间电池温度偏高",
        "CPU Threshold": "CPU 阈值",
        "CPU usage is currently or recently sustained at a high level": "CPU 当前或近期持续高占用",
        "Metric Refresh": "指标刷新",
        "Cancel": "取消",
        "Charged": "已充满",
        "Charging": "充电中",
        "Checking": "读取中",
        "Collecting": "正在收集",
        "Compact": "紧凑组合",
        "Compact Metrics": "紧凑显示项",
        "Confirming Unusual Reading": "等待异常读数确认",
        "Copied": "已复制",
        "Copy Diagnostics": "复制诊断信息",
        "Copy a diagnostic summary without personal identifiers": "复制不含个人标识的诊断摘要",
        "Could Not Disable Login Item": "无法关闭登录项",
        "Could Not Save Diagnostic Report": "无法保存诊断报告",
        "Could Not Update Login Item": "无法更新登录项",
        "Counter Overflow": "计数器溢出",
        "Critical": "危急",
        "Current CPU usage is %.0f%%": "当前 CPU 使用率 %.0f%%",
        "Current memory usage is %.0f%%": "当前内存占用 %.0f%%",
        "Cycle Count": "循环次数",
        "Denied": "已拒绝",
        "Device Maximum": "设备历史最高",
        "Disable Metrilens in System Settings → General → Login Items first.": "请先在“系统设置 → 通用 → 登录项”中关闭 Metrilens。",
        "Disk": "磁盘",
        "Disk Available Threshold": "磁盘可用阈值",
        "Disk Space": "磁盘空间",
        "Display Mode": "显示模式",
        "Display": "显示",
        "Done": "完成",
        "Dot (·)": "圆点（·）",
        "Down": "下移",
        "Enable local status alerts (off by default)": "启用本地状态提醒（默认关闭）",
        "Field Not Provided": "系统未提供该字段",
        "Free": "磁盘余",
        "Good": "正常",
        "General": "通用",
        "If critical heat persists, stop and cool the Mac; contact Apple if it recurs": "若危急状态或高温持续，停止使用并冷却；仍反复出现时联系 Apple",
        "Language": "界面语言",
        "Launch at Login": "登录时启动",
        "language.simplifiedChinese": "简体中文",
        "Local Alerts": "本地提醒",
        "Local notifications are working.": "本地通知工作正常。",
        "Low Battery": "电池电量较低",
        "Low Battery Level": "电池电量过低",
        "Low Battery Threshold": "低电量阈值",
        "Low Disk Space": "磁盘空间不足",
        "Low Startup Disk Space": "启动磁盘空间不足",
        "Master switch; each alert type is configurable and notifications are off by default": "总开关；各提醒类型可单独启用，默认不发送本地通知",
        "Memory": "内存",
        "Memory Threshold": "内存阈值",
        "Menu Bar": "菜单栏显示",
        "Menu bar, refresh, alert, login, and chart settings will be restored.": "菜单栏、刷新频率、提醒、登录项和图表设置将恢复默认值。",
        "Metric Order": "指标顺序",
        "Metrilens App Icon": "Metrilens App 图标",
        "Metrilens Diagnostics": "Metrilens 诊断信息",
        "Metrilens Memory": "Metrilens 占用",
        "Metrilens Settings": "Metrilens 设置",
        "Metrilens System Status": "Metrilens 系统状态",
        "Metrilens Test Alert": "Metrilens 测试提醒",
        "Metrilens does not scan processes; confirm the source in Activity Monitor.": "Metrilens 不扫描进程；具体来源请在“活动监视器”确认。",
        "Net": "网络",
        "Network": "网络",
        "Network Download": "网络下载",
        "Network Speed": "网络速率",
        "Network Upload": "网络上传",
        "No Active Network": "无活动网络",
        "No Battery": "无电池",
        "No abnormal heat indicators detected": "未发现异常发热迹象",
        "No samples": "暂无样本",
        "Nominal": "正常",
        "Not Provided": "系统未提供",
        "Not Requested": "尚未请求",
        "Notification Permission": "通知权限",
        "Notification Settings…": "系统通知设置…",
        "Number Precision": "数值精度",
        "On Battery": "使用电池",
        "Only %.0f%% of the startup disk is available": "启动磁盘可用空间仅剩 %.0f%%",
        "Open Activity Monitor’s CPU tab and quit unusually busy apps": "打开“活动监视器”的 CPU 页，检查并退出异常高占用 App",
        "Open CPU, memory, battery, network, disk, and heat diagnostics": "打开 CPU、内存、电池、网络、磁盘和发热诊断",
        "Open display, sampling, and alert settings": "打开显示、采样与提醒设置",
        "Open version and privacy-safe diagnostics": "打开版本与隐私安全诊断信息",
        "Pause charging and disconnect high-power accessories when practical": "条件允许时暂停充电并断开高功耗外设",
        "Pause heavy work and close apps you are not using": "暂停高负载任务并关闭暂时不用的 App",
        "Place the Mac on a hard, ventilated surface and clear airflow": "将 Mac 放在坚硬、通风的表面并清除散热口遮挡",
        "Poor": "较差",
        "Potential heat-producing conditions detected": "发现可能导致发热的状态",
        "Power Adapter": "外接电源",
        "Power State": "供电状态",
        "Provisional": "临时允许",
        "Quit": "退出",
        "RAM": "内存",
        "Reading Out of Range": "读数超出有效范围",
        "Reset": "重置",
        "Restart the session maximum from the current temperature": "以当前温度重新开始统计本次最高温度",
        "Restore Default Settings?": "恢复默认设置？",
        "Restore Defaults": "恢复默认设置",
        "Restore Defaults…": "恢复默认设置…",
        "Restore default display, sampling, alert, and launch settings": "恢复默认显示、采样、提醒和启动设置",
        "Sampling & Charts": "采样与图表",
        "Save Diagnostic Report…": "保存诊断报告…",
        "Save the privacy-safe diagnostic summary as a text file": "将隐私安全的诊断摘要保存为文本文件",
        "Send Test Alert": "发送测试提醒",
        "Separator": "分隔符",
        "Serious": "严重",
        "Serious Thermal State": "严重系统热状态",
        "Service Recommended": "建议维修",
        "Session Maximum": "本次最高",
        "Settings": "设置",
        "Show CPU and memory sparklines": "显示 CPU 和内存微型折线",
        "Single": "单项",
        "Single Metric": "单项主指标",
        "Space": "空格",
        "Startup Disk Available": "启动磁盘可用",
        "Startup Disk Used": "启动磁盘已用",
        "Sustain Duration": "持续时间",
        "Sustained High CPU": "CPU 持续高占用",
        "Sustained High Memory": "内存持续高占用",
        "System & Notes": "系统与说明",
        "System Default": "跟随系统",
        "System Metric Unavailable": "系统指标暂不可读",
        "System Resource Unavailable": "系统资源暂不可读",
        "System Thermal Warning": "系统热状态警告",
        "Temperature or thermal pressure is high; act soon": "温度或热压力较高，请尽快处理",
        "Temporarily enable Low Power Mode to reduce power use": "可临时开启低电量模式以降低功耗",
        "Thermal State": "系统热状态",
        "Unknown": "未知",
        "Unsupported Data Format": "数据格式不支持",
        "Up": "上移",
        "User Approval Required": "需要用户批准",
        "about.version": "版本 %@（%@）",
        "alert.highBatteryTemperature": "电池温度较高",
        "alert.currentThermalState": "当前状态：%@",
        "batteryHealth.fair": "一般",
        "diagnostics.privacyDisclosure": "诊断信息仅包含 App 版本与构建号、macOS 版本、系统架构、低电量模式状态、应用设置、采样状态、指标状态和最近的指标读取错误；不包含用户名、主机名、序列号、文件路径、进程 ID 或网络地址。",
        "macOS reports serious thermal pressure": "macOS 报告严重热压力",
        "popover.updated": "更新于 %@",
        "preferences.decimalPlaces": "%d 位小数",
        "preferences.seconds": "%d 秒",
        "preferences.sourceInformation": "温度说明：只读取 AppleSmartBattery 电池温度，并区分可重置的本次最高与设备历史最高。CPU/GPU 精确温度不在当前范围内。\n\n内存说明：“Metrilens 占用”由 internal、wired 与 compressor 内存组成；这是稳定的产品口径，不承诺与活动监视器完全一致。",
        "settings.highBatteryTemperature": "电池温度过高",
        "sparkline.accessibilityLabel": "最近 60 秒%@使用率",
        "status.staleTooltip": "Metrilens 系统状态\n数据已过期，采样于 %@",
        "thermal.fair": "偏热"
    ]
}

enum AppText {
    static func languageName(
        _ option: AppLanguage,
        interfaceLanguage: AppLanguage
    ) -> String {
        switch option {
        case .system:
            return interfaceLanguage.localized("System Default")
        case .simplifiedChinese:
            return interfaceLanguage.localized("language.simplifiedChinese")
        case .english:
            return "English"
        }
    }

    static func metricName(_ metric: PrimaryMetric, language: AppLanguage) -> String {
        switch metric {
        case .cpu:
            return "CPU"
        case .memory:
            return language.localized("Memory")
        case .battery:
            return language.localized("Battery")
        case .network:
            return language.localized("Network Speed")
        case .disk:
            return language.localized("Disk Space")
        }
    }

    static func displayModeName(
        _ mode: StatusDisplayMode,
        language: AppLanguage
    ) -> String {
        switch mode {
        case .single:
            return language.localized("Single")
        case .compact:
            return language.localized("Compact")
        }
    }

    static func thermalName(_ level: ThermalLevel, language: AppLanguage) -> String {
        switch level {
        case .nominal: return language.localized("Nominal")
        case .fair: return language.localized("thermal.fair")
        case .serious: return language.localized("Serious")
        case .critical: return language.localized("Critical")
        }
    }

    static func failureReason(
        _ failure: MetricFailure,
        language: AppLanguage
    ) -> String {
        switch failure {
        case .noHardware:
            return language.localized("No Battery")
        case .noActiveInterface:
            return language.localized("No Active Network")
        case .fieldMissing:
            return language.localized("Field Not Provided")
        case .unsupportedEncoding:
            return language.localized("Unsupported Data Format")
        case .counterOverflow:
            return language.localized("Counter Overflow")
        case .outOfRange:
            return language.localized("Reading Out of Range")
        case .outlierJump:
            return language.localized("Confirming Unusual Reading")
        case .fileSystemFailure:
            return language.localized("System Resource Unavailable")
        case .iokitFailure:
            return language.localized("Battery Interface Unavailable")
        case .machFailure:
            return language.localized("System Metric Unavailable")
        }
    }
}
