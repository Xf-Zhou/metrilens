import Foundation
import UserNotifications

enum MetricAlertKind: String, Hashable {
    case cpu
    case memory
    case thermal
    case batteryLevel
    case batteryTemperature
    case diskFree
}

enum NotificationAuthorizationState: String, Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case unknown

    var canDeliver: Bool {
        self == .authorized || self == .provisional
    }
}

struct MetricAlertEvent: Equatable {
    let kind: MetricAlertKind
    let value: Double?
    let thermalLevel: ThermalLevel?
}

struct MetricAlertEvaluator {
    let cooldown: TimeInterval
    private var thresholdStartedAt: [MetricAlertKind: TimeInterval] = [:]
    private var lastDeliveredAt: [MetricAlertKind: TimeInterval] = [:]

    init(cooldown: TimeInterval = 600) {
        self.cooldown = cooldown
    }

    mutating func evaluate(
        snapshot: SystemSnapshot,
        preferences: PreferencesSnapshot,
        nowUptime: TimeInterval
    ) -> [MetricAlertEvent] {
        guard preferences.alertsEnabled else {
            resetPending()
            return []
        }

        var events: [MetricAlertEvent] = []
        if preferences.cpuAlertEnabled {
            evaluateThreshold(
                kind: .cpu,
                value: snapshot.cpu.freshValue?.percent,
                threshold: preferences.cpuAlertThreshold,
                direction: .above,
                sustainDuration: preferences.alertSustainDuration,
                nowUptime: nowUptime,
                events: &events
            )
        } else {
            thresholdStartedAt.removeValue(forKey: .cpu)
        }
        if preferences.memoryAlertEnabled {
            evaluateThreshold(
                kind: .memory,
                value: snapshot.memory.freshValue?.percent,
                threshold: preferences.memoryAlertThreshold,
                direction: .above,
                sustainDuration: preferences.alertSustainDuration,
                nowUptime: nowUptime,
                events: &events
            )
        } else {
            thresholdStartedAt.removeValue(forKey: .memory)
        }
        if preferences.batteryLevelAlertEnabled {
            let battery = snapshot.battery.freshValue
            let level = battery?.powerState == .discharging
                ? battery?.levelPercent
                : nil
            evaluateThreshold(
                kind: .batteryLevel,
                value: level,
                threshold: preferences.batteryLevelAlertThreshold,
                direction: .below,
                sustainDuration: preferences.alertSustainDuration,
                nowUptime: nowUptime,
                events: &events
            )
        } else {
            thresholdStartedAt.removeValue(forKey: .batteryLevel)
        }
        if preferences.batteryTemperatureAlertEnabled {
            evaluateThreshold(
                kind: .batteryTemperature,
                value: snapshot.batteryTemperature.freshValue,
                threshold: preferences.batteryTemperatureAlertThreshold,
                direction: .above,
                sustainDuration: preferences.alertSustainDuration,
                nowUptime: nowUptime,
                events: &events
            )
        } else {
            thresholdStartedAt.removeValue(forKey: .batteryTemperature)
        }
        if preferences.diskFreeAlertEnabled {
            evaluateThreshold(
                kind: .diskFree,
                value: snapshot.disk.freshValue?.freePercent,
                threshold: preferences.diskFreeAlertThreshold,
                direction: .below,
                sustainDuration: preferences.alertSustainDuration,
                nowUptime: nowUptime,
                events: &events
            )
        } else {
            thresholdStartedAt.removeValue(forKey: .diskFree)
        }

        if preferences.thermalAlertEnabled
            && (snapshot.thermalLevel == .serious
                || snapshot.thermalLevel == .critical) {
            if canDeliver(.thermal, nowUptime: nowUptime) {
                events.append(
                    MetricAlertEvent(
                        kind: .thermal,
                        value: nil,
                        thermalLevel: snapshot.thermalLevel
                    )
                )
                lastDeliveredAt[.thermal] = nowUptime
            }
        } else {
            thresholdStartedAt.removeValue(forKey: .thermal)
        }
        return events
    }

    mutating func resetPending(
        _ kinds: Set<MetricAlertKind> = Set([
            .cpu,
            .memory,
            .thermal,
            .batteryLevel,
            .batteryTemperature,
            .diskFree
        ])
    ) {
        for kind in kinds {
            thresholdStartedAt.removeValue(forKey: kind)
        }
    }

    private mutating func evaluateThreshold(
        kind: MetricAlertKind,
        value: Double?,
        threshold: Double,
        direction: ThresholdDirection,
        sustainDuration: TimeInterval,
        nowUptime: TimeInterval,
        events: inout [MetricAlertEvent]
    ) {
        guard let value,
              (direction == .above
                ? value >= threshold
                : value <= threshold) else {
            thresholdStartedAt.removeValue(forKey: kind)
            return
        }
        let startedAt = thresholdStartedAt[kind] ?? nowUptime
        thresholdStartedAt[kind] = startedAt
        guard nowUptime - startedAt >= sustainDuration,
              canDeliver(kind, nowUptime: nowUptime) else {
            return
        }
        events.append(
            MetricAlertEvent(kind: kind, value: value, thermalLevel: nil)
        )
        lastDeliveredAt[kind] = nowUptime
    }

    private func canDeliver(
        _ kind: MetricAlertKind,
        nowUptime: TimeInterval
    ) -> Bool {
        guard let lastDelivered = lastDeliveredAt[kind] else { return true }
        return nowUptime - lastDelivered >= cooldown
    }
}

private enum ThresholdDirection {
    case above
    case below
}

protocol LocalNotificationDelivering {
    func getAuthorizationStatus(
        completion: @escaping (NotificationAuthorizationState) -> Void
    )
    func requestAuthorization(completion: @escaping (Bool) -> Void)
    func deliver(identifier: String, title: String, body: String)
}

final class UserNotificationDelivery: NSObject,
    LocalNotificationDelivering,
    UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter
    static let foregroundPresentationOptions: UNNotificationPresentationOptions = [
        .banner,
        .sound
    ]

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        center.delegate = self
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            completion(granted)
        }
    }

    func getAuthorizationStatus(
        completion: @escaping (NotificationAuthorizationState) -> Void
    ) {
        center.getNotificationSettings { settings in
            let state: NotificationAuthorizationState
            switch settings.authorizationStatus {
            case .notDetermined: state = .notDetermined
            case .denied: state = .denied
            case .authorized: state = .authorized
            case .provisional: state = .provisional
            case .ephemeral: state = .authorized
            @unknown default: state = .unknown
            }
            completion(state)
        }
    }

    func deliver(identifier: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        center.add(
            UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: nil
            )
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(Self.foregroundPresentationOptions)
    }
}

final class MetricAlertController {
    private let delivery: LocalNotificationDelivering
    private let uptimeProvider: () -> TimeInterval
    private var evaluator = MetricAlertEvaluator()
    private var preferences: PreferencesSnapshot
    private(set) var authorizationState: NotificationAuthorizationState = .unknown
    var onAuthorizationChange: ((NotificationAuthorizationState) -> Void)?

    init(
        preferences: PreferencesSnapshot,
        delivery: LocalNotificationDelivering = UserNotificationDelivery(),
        uptimeProvider: @escaping () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        self.preferences = preferences
        self.delivery = delivery
        self.uptimeProvider = uptimeProvider
        if preferences.alertsEnabled {
            requestAuthorization()
        } else {
            refreshAuthorizationStatus()
        }
    }

    func setPreferences(_ preferences: PreferencesSnapshot) {
        let oldConfiguration = AlertConfiguration(self.preferences)
        let newConfiguration = AlertConfiguration(preferences)
        self.preferences = preferences
        var resetKinds: Set<MetricAlertKind> = []
        if oldConfiguration.enabled != newConfiguration.enabled {
            resetKinds.formUnion(Set(MetricAlertKind.all))
        }
        resetKinds.formUnion(oldConfiguration.changedKinds(comparedTo: newConfiguration))
        if !resetKinds.isEmpty {
            evaluator.resetPending(resetKinds)
        }
        if preferences.alertsEnabled && !oldConfiguration.enabled {
            requestAuthorization()
        }
    }

    func handle(snapshot: SystemSnapshot) {
        guard preferences.alertsEnabled, authorizationState.canDeliver else {
            return
        }
        let events = evaluator.evaluate(
            snapshot: snapshot,
            preferences: preferences,
            nowUptime: uptimeProvider()
        )
        for event in events {
            let content = Self.content(for: event, language: preferences.language)
            delivery.deliver(
                identifier: "metrilens.alert.\(event.kind.rawValue).\(UUID().uuidString)",
                title: content.title,
                body: content.body
            )
        }
    }

    func refreshAuthorizationStatus() {
        delivery.getAuthorizationStatus { [weak self] state in
            DispatchQueue.main.async {
                self?.setAuthorizationState(state)
            }
        }
    }

    func sendTestNotification() {
        let send: () -> Void = { [weak self] in
            guard let self else { return }
            self.delivery.deliver(
                identifier: "metrilens.alert.test.\(UUID().uuidString)",
                title: self.preferences.language.text(
                    "Metrilens 测试提醒",
                    "Metrilens Test Alert"
                ),
                body: self.preferences.language.text(
                    "本地通知工作正常。",
                    "Local notifications are working."
                )
            )
        }
        if authorizationState.canDeliver {
            send()
        } else {
            delivery.requestAuthorization { [weak self] granted in
                DispatchQueue.main.async {
                    self?.setAuthorizationState(
                        granted ? .authorized : .denied
                    )
                    if granted { send() }
                }
            }
        }
    }

    static func content(
        for event: MetricAlertEvent,
        language: AppLanguage
    ) -> (title: String, body: String) {
        switch event.kind {
        case .cpu:
            return (
                language.text("CPU 持续高占用", "Sustained High CPU"),
                String(
                    format: language.text("当前 CPU 使用率 %.0f%%", "Current CPU usage is %.0f%%"),
                    event.value ?? 0
                )
            )
        case .memory:
            return (
                language.text("内存持续高占用", "Sustained High Memory"),
                String(
                    format: language.text("当前内存占用 %.0f%%", "Current memory usage is %.0f%%"),
                    event.value ?? 0
                )
            )
        case .thermal:
            return (
                language.text("系统热状态警告", "System Thermal Warning"),
                language.text(
                    "当前状态：\(AppText.thermalName(event.thermalLevel ?? .serious, language: language))",
                    "Current state: \(AppText.thermalName(event.thermalLevel ?? .serious, language: language))"
                )
            )
        case .batteryLevel:
            return (
                language.text("电池电量较低", "Low Battery"),
                String(
                    format: language.text(
                        "当前剩余电量 %.0f%%",
                        "Battery level is %.0f%%"
                    ),
                    event.value ?? 0
                )
            )
        case .batteryTemperature:
            return (
                language.text("电池温度较高", "High Battery Temperature"),
                String(
                    format: language.text(
                        "当前电池温度 %.1f°C",
                        "Battery temperature is %.1f°C"
                    ),
                    event.value ?? 0
                )
            )
        case .diskFree:
            return (
                language.text("磁盘空间不足", "Low Disk Space"),
                String(
                    format: language.text(
                        "启动磁盘可用空间仅剩 %.0f%%",
                        "Only %.0f%% of the startup disk is available"
                    ),
                    event.value ?? 0
                )
            )
        }
    }

    private func requestAuthorization() {
        delivery.requestAuthorization { [weak self] granted in
            DispatchQueue.main.async {
                self?.setAuthorizationState(
                    granted ? .authorized : .denied
                )
            }
        }
    }

    private func setAuthorizationState(
        _ state: NotificationAuthorizationState
    ) {
        authorizationState = state
        onAuthorizationChange?(state)
    }
}

private struct AlertConfiguration: Equatable {
    let enabled: Bool
    let cpuThreshold: Double
    let memoryThreshold: Double
    let batteryLevelThreshold: Double
    let batteryTemperatureThreshold: Double
    let diskFreeThreshold: Double
    let sustainDuration: TimeInterval
    let enabledKinds: Set<MetricAlertKind>

    init(_ preferences: PreferencesSnapshot) {
        enabled = preferences.alertsEnabled
        cpuThreshold = preferences.cpuAlertThreshold
        memoryThreshold = preferences.memoryAlertThreshold
        batteryLevelThreshold = preferences.batteryLevelAlertThreshold
        batteryTemperatureThreshold = preferences.batteryTemperatureAlertThreshold
        diskFreeThreshold = preferences.diskFreeAlertThreshold
        sustainDuration = preferences.alertSustainDuration
        enabledKinds = Set(MetricAlertKind.all.filter {
            preferences.isAlertEnabled($0)
        })
    }

    func changedKinds(comparedTo other: AlertConfiguration)
        -> Set<MetricAlertKind> {
        var result = enabledKinds.symmetricDifference(other.enabledKinds)
        if sustainDuration != other.sustainDuration {
            result.formUnion(Set(MetricAlertKind.all.filter { $0 != .thermal }))
        }
        if cpuThreshold != other.cpuThreshold { result.insert(.cpu) }
        if memoryThreshold != other.memoryThreshold { result.insert(.memory) }
        if batteryLevelThreshold != other.batteryLevelThreshold {
            result.insert(.batteryLevel)
        }
        if batteryTemperatureThreshold != other.batteryTemperatureThreshold {
            result.insert(.batteryTemperature)
        }
        if diskFreeThreshold != other.diskFreeThreshold {
            result.insert(.diskFree)
        }
        return result
    }
}

private extension MetricAlertKind {
    static let all: [MetricAlertKind] = [
        .cpu,
        .memory,
        .thermal,
        .batteryLevel,
        .batteryTemperature,
        .diskFree
    ]
}

private extension PreferencesSnapshot {
    func isAlertEnabled(_ kind: MetricAlertKind) -> Bool {
        switch kind {
        case .cpu: return cpuAlertEnabled
        case .memory: return memoryAlertEnabled
        case .thermal: return thermalAlertEnabled
        case .batteryLevel: return batteryLevelAlertEnabled
        case .batteryTemperature: return batteryTemperatureAlertEnabled
        case .diskFree: return diskFreeAlertEnabled
        }
    }
}
