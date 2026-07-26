import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = AppPreferences()
    private let loginItemController = LoginItemController()
    private lazy var sampler = MetricSampler(preferences: preferences.snapshot)
    private lazy var statusController = StatusItemController(primaryMetric: preferences.snapshot.primaryMetric)
    private lazy var popoverController = PopoverController(showsSparkline: preferences.snapshot.showsSparkline)
    private lazy var preferencesController = PreferencesController(
        preferences: preferences,
        loginItemController: loginItemController
    )
    private let lifecycleBridge = LifecycleEventBridge()
    private var taskPowerProbe: TaskPowerProbe?

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

    private func wireComponents() {
        statusController.onToggle = { [weak self] button in
            self?.popoverController.toggle(relativeTo: button)
        }
        popoverController.onVisibilityChange = { [weak self] visible in
            self?.sampler.setPopoverVisible(visible)
        }
        popoverController.onOpenPreferences = { [weak self] in
            self?.preferencesController.show()
        }
        popoverController.onQuit = {
            NSApp.terminate(nil)
        }

        sampler.onSnapshot = { [weak self] snapshot in
            self?.statusController.update(snapshot: snapshot)
            self?.popoverController.update(snapshot: snapshot)
        }

        preferences.onChange = { [weak self] value in
            self?.statusController.setPrimaryMetric(value.primaryMetric)
            self?.popoverController.setShowsSparkline(value.showsSparkline)
            self?.sampler.updatePreferences(value)
        }

        lifecycleBridge.onWillSleep = { [weak self] in self?.sampler.systemWillSleep() }
        lifecycleBridge.onDidWake = { [weak self] in self?.sampler.systemDidWake() }
        lifecycleBridge.onPowerSourceChange = { [weak self] in self?.sampler.powerSourceChanged() }
        lifecycleBridge.onPowerStateChange = { [weak self] in self?.sampler.powerStateChanged() }
        lifecycleBridge.onThermalStateChange = { [weak self] in self?.sampler.thermalStateChanged() }
    }
}
