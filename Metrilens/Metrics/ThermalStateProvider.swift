import Foundation

protocol ThermalStateProviding {
    func current() -> ThermalLevel
}

struct ThermalStateProvider: ThermalStateProviding {
    func current() -> ThermalLevel {
        ThermalLevel(ProcessInfo.processInfo.thermalState)
    }
}
