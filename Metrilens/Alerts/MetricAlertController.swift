import Foundation
import UserNotifications

enum MetricAlertKind: String, Hashable {
    case cpu
    case memory
    case thermal
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
        evaluateThreshold(
            kind: .cpu,
            value: snapshot.cpu.freshValue?.percent,
            threshold: preferences.cpuAlertThreshold,
            sustainDuration: preferences.alertSustainDuration,
            nowUptime: nowUptime,
            events: &events
        )
        evaluateThreshold(
            kind: .memory,
            value: snapshot.memory.freshValue?.percent,
            threshold: preferences.memoryAlertThreshold,
            sustainDuration: preferences.alertSustainDuration,
            nowUptime: nowUptime,
            events: &events
        )

        if snapshot.thermalLevel == .serious || snapshot.thermalLevel == .critical {
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
        _ kinds: Set<MetricAlertKind> = [.cpu, .memory, .thermal]
    ) {
        for kind in kinds {
            thresholdStartedAt.removeValue(forKey: kind)
        }
    }

    private mutating func evaluateThreshold(
        kind: MetricAlertKind,
        value: Double?,
        threshold: Double,
        sustainDuration: TimeInterval,
        nowUptime: TimeInterval,
        events: inout [MetricAlertEvent]
    ) {
        guard let value, value >= threshold else {
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

protocol LocalNotificationDelivering {
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
    private var authorizationGranted = false

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
        }
    }

    func setPreferences(_ preferences: PreferencesSnapshot) {
        let oldConfiguration = AlertConfiguration(self.preferences)
        let newConfiguration = AlertConfiguration(preferences)
        self.preferences = preferences
        var resetKinds: Set<MetricAlertKind> = []
        if oldConfiguration.enabled != newConfiguration.enabled {
            resetKinds.formUnion([.cpu, .memory, .thermal])
        }
        if oldConfiguration.cpuThreshold != newConfiguration.cpuThreshold
            || oldConfiguration.sustainDuration != newConfiguration.sustainDuration {
            resetKinds.insert(.cpu)
        }
        if oldConfiguration.memoryThreshold != newConfiguration.memoryThreshold
            || oldConfiguration.sustainDuration != newConfiguration.sustainDuration {
            resetKinds.insert(.memory)
        }
        if !resetKinds.isEmpty {
            evaluator.resetPending(resetKinds)
        }
        if preferences.alertsEnabled && !oldConfiguration.enabled {
            requestAuthorization()
        } else if !preferences.alertsEnabled {
            authorizationGranted = false
        }
    }

    func handle(snapshot: SystemSnapshot) {
        guard preferences.alertsEnabled, authorizationGranted else { return }
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
        }
    }

    private func requestAuthorization() {
        delivery.requestAuthorization { [weak self] granted in
            DispatchQueue.main.async {
                self?.authorizationGranted = granted
            }
        }
    }
}

private struct AlertConfiguration: Equatable {
    let enabled: Bool
    let cpuThreshold: Double
    let memoryThreshold: Double
    let sustainDuration: TimeInterval

    init(_ preferences: PreferencesSnapshot) {
        enabled = preferences.alertsEnabled
        cpuThreshold = preferences.cpuAlertThreshold
        memoryThreshold = preferences.memoryAlertThreshold
        sustainDuration = preferences.alertSustainDuration
    }
}
