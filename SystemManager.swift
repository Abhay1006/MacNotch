import Foundation
import Combine
import IOKit.ps
import ApplicationServices

class SystemManager: ObservableObject {
    @Published var batteryPercentage: Int = 100
    @Published var isBatteryCharging: Bool = false
    @Published var systemVolume: Int = 50 // 0 to 100
    @Published var systemBrightness: Int = 50 // 0 to 100
    
    @Published var cpuUsage: Int = 0
    @Published var ramUsage: Int = 0
    
    let calendarManager = CalendarManager()
    private let cpuCounter = CPUUsage()
    
    private var timer: AnyCancellable?
    
    private var getBrightness: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32)?
    private var setBrightness: (@convention(c) (CGDirectDisplayID, Float) -> Int32)?
    
    init() {
        setupBrightnessControl()
        startMonitoring()
        updateSystemStatusAsync()
    }
    
    private func setupBrightnessControl() {
        if let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW) {
            typealias GetBrightnessProto = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
            typealias SetBrightnessProto = @convention(c) (CGDirectDisplayID, Float) -> Int32
            
            if let getBrightnessSym = dlsym(handle, "DisplayServicesGetBrightness"),
               let setBrightnessSym = dlsym(handle, "DisplayServicesSetBrightness") {
                self.getBrightness = unsafeBitCast(getBrightnessSym, to: GetBrightnessProto.self)
                self.setBrightness = unsafeBitCast(setBrightnessSym, to: SetBrightnessProto.self)
            }
        }
    }
    
    func startMonitoring() {
        // Poll system status every 2.0 seconds
        timer = Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateSystemStatusAsync()
            }
    }
    
    private func updateSystemStatusAsync() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // 1. Battery status
            var tempBatteryPercentage = 100
            var tempIsBatteryCharging = false
            if let snapshotRef = IOPSCopyPowerSourcesInfo() {
                let snapshot = snapshotRef.takeRetainedValue()
                if let sourcesRef = IOPSCopyPowerSourcesList(snapshot) {
                    let sources = sourcesRef.takeRetainedValue() as [CFTypeRef]
                    for source in sources {
                        if let descriptionRef = IOPSGetPowerSourceDescription(snapshot, source) {
                            let description = descriptionRef.takeUnretainedValue() as? [String: Any] ?? [:]
                            let name = description[kIOPSNameKey] as? String ?? ""
                            if name.contains("InternalBattery") {
                                tempBatteryPercentage = description[kIOPSCurrentCapacityKey] as? Int ?? 100
                                tempIsBatteryCharging = description[kIOPSIsChargingKey] as? Bool ?? false
                                break
                            }
                        }
                    }
                }
            }
            
            // 2. Volume status
            var tempVolume = 50
            let volScript = "output volume of (get volume settings)"
            if let volResult = self.runAppleScript(volScript),
               let vol = Int(volResult.trimmingCharacters(in: .whitespacesAndNewlines)) {
                tempVolume = vol
            }
            
            // 3. Brightness status
            var tempBrightness = 50
            if let getBrightness = self.getBrightness {
                let mainDisplay = CGMainDisplayID()
                var currentBrightness: Float = 0.0
                let result = getBrightness(mainDisplay, &currentBrightness)
                if result == 0 {
                    tempBrightness = Int(currentBrightness * 100.0)
                }
            }
            
            // 4. CPU and RAM Metrics
            let tempCpu = self.cpuCounter.getCPUUsagePercentage()
            let tempRam = self.getMemoryUsagePercentage()
            
            // 5. Calendar (updates internally in background)
            self.calendarManager.fetchNextEvent()
            
            // Dispatch UI updates to main thread
            DispatchQueue.main.async {
                self.batteryPercentage = tempBatteryPercentage
                self.isBatteryCharging = tempIsBatteryCharging
                self.systemVolume = tempVolume
                self.systemBrightness = tempBrightness
                self.cpuUsage = tempCpu
                self.ramUsage = tempRam
            }
        }
    }
    
    private func getMemoryUsagePercentage() -> Int {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        
        let kerr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let pageSize = Double(vm_kernel_page_size)
            let active = Double(stats.active_count) * pageSize
            let wire = Double(stats.wire_count) * pageSize
            let compressed = Double(stats.compressor_page_count) * pageSize
            
            let total = Double(ProcessInfo.processInfo.physicalMemory)
            let used = active + wire + compressed
            return Int((used / total) * 100.0)
        }
        return 0
    }
    
    private func runAppleScript(_ source: String) -> String? {
        return autoreleasepool {
            guard let script = NSAppleScript(source: source) else { return nil }
            var error: NSDictionary?
            let descriptor = script.executeAndReturnError(&error)
            if error != nil {
                return nil
            }
            return descriptor.stringValue
        }
    }
    
    func setVolume(_ volume: Int) {
        let clamped = max(0, min(100, volume))
        self.systemVolume = clamped
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let script = "set volume output volume \(clamped)"
            _ = self?.runAppleScript(script)
        }
    }
    
    private func updateBrightnessStatus() {
        guard let getBrightness = self.getBrightness else { return }
        let mainDisplay = CGMainDisplayID()
        var currentBrightness: Float = 0.0
        let result = getBrightness(mainDisplay, &currentBrightness)
        if result == 0 {
            self.systemBrightness = Int(currentBrightness * 100.0)
        }
    }
    
    func setBrightness(_ brightness: Int) {
        let clamped = max(0, min(100, brightness))
        self.systemBrightness = clamped
        guard let setBrightness = self.setBrightness else { return }
        let mainDisplay = CGMainDisplayID()
        let level = Float(clamped) / 100.0
        _ = setBrightness(mainDisplay, level)
    }
}

class CPUUsage {
    private var prevCpuInfo = host_cpu_load_info()
    private var hasPrevInfo = false
    
    func getCPUUsagePercentage() -> Int {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var cpuInfo = host_cpu_load_info()
        
        let result = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        
        guard result == KERN_SUCCESS else { return 0 }
        
        if !hasPrevInfo {
            prevCpuInfo = cpuInfo
            hasPrevInfo = true
            return 0
        }
        
        let userDiff = Double(cpuInfo.cpu_ticks.0 - prevCpuInfo.cpu_ticks.0)
        let systemDiff = Double(cpuInfo.cpu_ticks.1 - prevCpuInfo.cpu_ticks.1)
        let idleDiff = Double(cpuInfo.cpu_ticks.2 - prevCpuInfo.cpu_ticks.2)
        let niceDiff = Double(cpuInfo.cpu_ticks.3 - prevCpuInfo.cpu_ticks.3)
        
        let totalTicks = userDiff + systemDiff + idleDiff + niceDiff
        prevCpuInfo = cpuInfo
        
        if totalTicks > 0 {
            let activeTicks = userDiff + systemDiff + niceDiff
            return Int((activeTicks / totalTicks) * 100.0)
        }
        return 0
    }
}
