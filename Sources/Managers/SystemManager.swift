import Foundation
import Combine
import IOKit.ps
import ApplicationServices

class SystemManager: ObservableObject {
    @Published var batteryPercentage: Int = 100
    @Published var isBatteryCharging: Bool = false
    @Published var systemBrightness: Int = 50

    @Published var cpuUsage: Int = 0
    @Published var ramUsage: Int = 0

    /// False until the first real power-source read completes.
    ///
    /// `isBatteryCharging` starts at `false`, so the first poll on a plugged-in Mac
    /// flipped it to `true` and fired a bogus "Charging" banner on every launch. Views
    /// check this before reacting to a change.
    @Published private(set) var hasBatteryReading: Bool = false

    private let cpuCounter = CPUUsage()

    private var timer: AnyCancellable?

    /// All sampling happens here, serially.
    ///
    /// The old code dispatched to a *concurrent* global queue every 5s while reading a
    /// main-thread `@Published` and mutating `prevCpuInfo`. A slow poll could overlap the
    /// next one and race.
    private let sampleQueue = DispatchQueue(label: "com.abhay.MacNotch.system", qos: .utility)
    private var isSampling = false

    private var getBrightness: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32)?
    private var setBrightness: (@convention(c) (CGDirectDisplayID, Float) -> Int32)?

    init() {
        setupBrightnessControl()
        startMonitoring()
        updateSystemStatusAsync()
    }

    deinit {
        timer?.cancel()
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
        } else {
            Log.system.notice("DisplayServices unavailable; brightness control disabled")
        }
    }

    func startMonitoring() {
        // Poll system status every 5.0 seconds
        timer = Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateSystemStatusAsync()
            }
    }

    private func updateSystemStatusAsync() {
        sampleQueue.async { [weak self] in
            guard let self = self else { return }
            // Skip rather than queue up if a previous sample is somehow still running.
            guard !self.isSampling else { return }
            self.isSampling = true
            defer { self.isSampling = false }

            // 1. Battery status
            var tempBatteryPercentage = 100
            var tempIsBatteryCharging = false
            var gotBatteryReading = false
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
                                gotBatteryReading = true
                                break
                            }
                        }
                    }
                }
            }

            // 2. Brightness status
            var tempBrightness = 50
            if let getBrightness = self.getBrightness {
                let mainDisplay = CGMainDisplayID()
                var currentBrightness: Float = 0.0
                if getBrightness(mainDisplay, &currentBrightness) == 0 {
                    tempBrightness = Int(currentBrightness * 100.0)
                }
            }

            // 3. CPU and RAM Metrics
            let tempCpu = self.cpuCounter.getCPUUsagePercentage()
            let tempRam = self.getMemoryUsagePercentage()

            // Dispatch UI updates to main thread
            DispatchQueue.main.async {
                self.batteryPercentage = tempBatteryPercentage
                self.isBatteryCharging = tempIsBatteryCharging
                self.systemBrightness = tempBrightness
                self.cpuUsage = tempCpu
                self.ramUsage = tempRam
                if gotBatteryReading { self.hasBatteryReading = true }
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

    private func updateBrightnessStatus() {
        guard let getBrightness = self.getBrightness else { return }
        let mainDisplay = CGMainDisplayID()
        var currentBrightness: Float = 0.0
        if getBrightness(mainDisplay, &currentBrightness) == 0 {
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
