import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = AppPreferences()
    private let loginItemController = LoginItemController()
    private lazy var sampler = MetricSampler(preferences: preferences.snapshot)
    private lazy var statusController = StatusItemController(
        preferences: preferences.snapshot
    )
    private lazy var popoverController = PopoverController(
        preferences: preferences.snapshot
    )
    private lazy var preferencesController = PreferencesController(
        preferences: preferences,
        loginItemController: loginItemController
    )
    private lazy var aboutController = AboutController(
        language: preferences.snapshot.language
    ) { [weak self] in
        guard let self else { return "Metrilens 诊断信息\nstatus=unavailable" }
        return DiagnosticReport.make(
            build: .current(),
            context: .current(),
            preferences: self.preferences.snapshot,
            snapshot: self.latestSnapshot
        )
    }
    private lazy var alertController = MetricAlertController(
        preferences: preferences.snapshot
    )
    private let lifecycleBridge = LifecycleEventBridge()
    private var taskPowerProbe: TaskPowerProbe?
    private var latestSnapshot = SystemSnapshot.initial()

    func applicationDidFinishLaunching(_ notification: Notification) {
        wireComponents()
        lifecycleBridge.start()
        sampler.start()
        taskPowerProbe = TaskPowerProbe.startIfRequested(
            preferences: preferences.snapshot,
            effectiveCPUPeriodProvider: { [weak self] in
                self?.sampler.effectiveCPUPeriodForDiagnostics()
            }
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        lifecycleBridge.stop()
        sampler.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        alertController.refreshAuthorizationStatus()
    }

    private func wireComponents() {
        statusController.onToggle = { [weak self] button in
            self?.popoverController.toggle(relativeTo: button)
        }
        popoverController.onVisibilityChange = { [weak self] visible in
            self?.statusController.setPopoverVisible(visible)
            self?.sampler.setPopoverVisible(visible)
        }
        popoverController.onOpenPreferences = { [weak self] in
            self?.preferencesController.show()
        }
        popoverController.onOpenAbout = { [weak self] in
            self?.aboutController.show()
        }
        popoverController.onResetBatterySessionMaximum = { [weak self] in
            self?.sampler.resetBatterySessionMaximum()
        }
        popoverController.onQuit = {
            NSApp.terminate(nil)
        }
        preferencesController.onTestNotification = { [weak self] in
            self?.alertController.sendTestNotification()
        }
        preferencesController.onRefreshNotificationStatus = { [weak self] in
            self?.alertController.refreshAuthorizationStatus()
        }
        preferencesController.onOpenNotificationSettings = {
            guard let url = URL(
                string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
            ) else { return }
            NSWorkspace.shared.open(url)
        }
        alertController.onAuthorizationChange = { [weak self] state in
            self?.preferencesController.setNotificationAuthorizationState(state)
        }
        preferencesController.setNotificationAuthorizationState(
            alertController.authorizationState
        )

        sampler.onSnapshot = { [weak self] snapshot in
            self?.latestSnapshot = snapshot
            self?.statusController.update(snapshot: snapshot)
            self?.popoverController.update(snapshot: snapshot)
            self?.alertController.handle(snapshot: snapshot)
        }

        preferences.onChange = { [weak self] value in
            guard let self else { return }
            self.statusController.setPreferences(value)
            self.statusController.update(snapshot: self.latestSnapshot)
            self.popoverController.setPreferences(value)
            self.popoverController.update(snapshot: self.latestSnapshot)
            self.preferencesController.setPreferences(value)
            self.aboutController.setLanguage(value.language)
            self.alertController.setPreferences(value)
            self.sampler.updatePreferences(value)
        }

        lifecycleBridge.onWillSleep = { [weak self] in self?.sampler.systemWillSleep() }
        lifecycleBridge.onDidWake = { [weak self] in self?.sampler.systemDidWake() }
        lifecycleBridge.onPowerSourceChange = { [weak self] in self?.sampler.powerSourceChanged() }
        lifecycleBridge.onPowerStateChange = { [weak self] in self?.sampler.powerStateChanged() }
        lifecycleBridge.onThermalStateChange = { [weak self] in self?.sampler.thermalStateChanged() }
    }
}
