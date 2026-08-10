import Foundation
import UserNotifications

enum MetricAlertKind: String, Hashable, CaseIterable {
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
        guard preferences.alerts.enabled else {
            resetPending()
            return []
        }

        var events: [MetricAlertEvent] = []
        if preferences.alerts.enabledKinds.contains(.cpu) {
            evaluateThreshold(
                kind: .cpu,
                value: snapshot.cpu.freshValue?.percent,
                threshold: preferences.alerts.thresholds.cpu,
                direction: .above,
                sustainDuration: preferences.alerts.sustainDuration,
                nowUptime: nowUptime,
                events: &events
            )
        } else {
            thresholdStartedAt.removeValue(forKey: .cpu)
        }
        if preferences.alerts.enabledKinds.contains(.memory) {
            evaluateThreshold(
                kind: .memory,
                value: snapshot.memory.freshValue?.percent,
                threshold: preferences.alerts.thresholds.memory,
                direction: .above,
                sustainDuration: preferences.alerts.sustainDuration,
                nowUptime: nowUptime,
                events: &events
            )
        } else {
            thresholdStartedAt.removeValue(forKey: .memory)
        }
        if preferences.alerts.enabledKinds.contains(.batteryLevel) {
            let battery = snapshot.battery.freshValue
            let level = battery?.powerState == .discharging
                ? battery?.levelPercent
                : nil
            evaluateThreshold(
                kind: .batteryLevel,
                value: level,
                threshold: preferences.alerts.thresholds.batteryLevel,
                direction: .below,
                sustainDuration: preferences.alerts.sustainDuration,
                nowUptime: nowUptime,
                events: &events
            )
        } else {
            thresholdStartedAt.removeValue(forKey: .batteryLevel)
        }
        if preferences.alerts.enabledKinds.contains(.batteryTemperature) {
            evaluateThreshold(
                kind: .batteryTemperature,
                value: snapshot.batteryTemperature.freshValue,
                threshold: preferences.alerts.thresholds.batteryTemperature,
                direction: .above,
                sustainDuration: preferences.alerts.sustainDuration,
                nowUptime: nowUptime,
                events: &events
            )
        } else {
            thresholdStartedAt.removeValue(forKey: .batteryTemperature)
        }
        if preferences.alerts.enabledKinds.contains(.diskFree) {
            evaluateThreshold(
                kind: .diskFree,
                value: snapshot.disk.freshValue?.freePercent,
                threshold: preferences.alerts.thresholds.diskFree,
                direction: .below,
                sustainDuration: preferences.alerts.sustainDuration,
                nowUptime: nowUptime,
                events: &events
            )
        } else {
            thresholdStartedAt.removeValue(forKey: .diskFree)
        }

        if preferences.alerts.enabledKinds.contains(.thermal)
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
        if preferences.alerts.enabled {
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
            resetKinds.formUnion(Set(MetricAlertKind.allCases))
        }
        resetKinds.formUnion(oldConfiguration.changedKinds(comparedTo: newConfiguration))
        if !resetKinds.isEmpty {
            evaluator.resetPending(resetKinds)
        }
        if preferences.alerts.enabled && !oldConfiguration.enabled {
            requestAuthorization()
        }
    }

    func handle(snapshot: SystemSnapshot) {
        guard preferences.alerts.enabled, authorizationState.canDeliver else {
            return
        }
        let events = evaluator.evaluate(
            snapshot: snapshot,
            preferences: preferences,
            nowUptime: uptimeProvider()
        )
        for event in events {
            let content = Self.content(for: event, language: preferences.display.language)
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
                title: self.preferences.display.language.localized("Metrilens Test Alert"),
                body: self.preferences.display.language.localized("Local notifications are working.")
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
                language.localized("Sustained High CPU"),
                String(
                    format: language.localized("Current CPU usage is %.0f%%"),
                    event.value ?? 0
                )
            )
        case .memory:
            return (
                language.localized("Sustained High Memory"),
                String(
                    format: language.localized("Current memory usage is %.0f%%"),
                    event.value ?? 0
                )
            )
        case .thermal:
            return (
                language.localized("System Thermal Warning"),
                language.localized(
                    "alert.currentThermalState",
                    arguments: AppText.thermalName(
                        event.thermalLevel ?? .serious,
                        language: language
                    )
                )
            )
        case .batteryLevel:
            return (
                language.localized("Low Battery"),
                String(
                    format: language.localized("Battery level is %.0f%%"),
                    event.value ?? 0
                )
            )
        case .batteryTemperature:
            return (
                language.localized("alert.highBatteryTemperature"),
                String(
                    format: language.localized("Battery temperature is %.1f°C"),
                    event.value ?? 0
                )
            )
        case .diskFree:
            return (
                language.localized("Low Disk Space"),
                String(
                    format: language.localized("Only %.0f%% of the startup disk is available"),
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
        enabled = preferences.alerts.enabled
        cpuThreshold = preferences.alerts.thresholds.cpu
        memoryThreshold = preferences.alerts.thresholds.memory
        batteryLevelThreshold = preferences.alerts.thresholds.batteryLevel
        batteryTemperatureThreshold = preferences.alerts.thresholds.batteryTemperature
        diskFreeThreshold = preferences.alerts.thresholds.diskFree
        sustainDuration = preferences.alerts.sustainDuration
        enabledKinds = preferences.alerts.enabledKinds
    }

    func changedKinds(comparedTo other: AlertConfiguration)
        -> Set<MetricAlertKind> {
        var result = enabledKinds.symmetricDifference(other.enabledKinds)
        if sustainDuration != other.sustainDuration {
            result.formUnion(Set(MetricAlertKind.allCases.filter { $0 != .thermal }))
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
