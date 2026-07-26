import AppKit
import Foundation
import IOKit.ps

final class LifecycleEventBridge {
    var onWillSleep: (() -> Void)?
    var onDidWake: (() -> Void)?
    var onPowerSourceChange: (() -> Void)?
    var onPowerStateChange: (() -> Void)?
    var onThermalStateChange: (() -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var lastPowerSourceType: String?

    func start() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.onWillSleep?() })
        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.onDidWake?() })

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.onPowerStateChange?() })
        observers.append(center.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.onThermalStateChange?() })

        lastPowerSourceType = currentPowerSourceType()
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let bridge = Unmanaged<LifecycleEventBridge>.fromOpaque(context).takeUnretainedValue()
            bridge.handlePowerSourceNotification()
        }, context)?.takeRetainedValue() {
            powerSourceRunLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    func stop() {
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        if let source = powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            powerSourceRunLoopSource = nil
        }
    }

    deinit {
        stop()
    }

    private func handlePowerSourceNotification() {
        let current = currentPowerSourceType()
        defer { lastPowerSourceType = current }
        guard current != lastPowerSourceType else { return }
        onPowerSourceChange?()
    }

    private func currentPowerSourceType() -> String? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let value = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else {
            return nil
        }
        return value as String
    }
}
