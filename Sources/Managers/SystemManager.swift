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
    /// flipped it to `true` and fired a bogus "Charging" banner on every launch. Observers
    /// check this before reacting to a change.
    @Published private(set) var hasBatteryReading: Bool = false

    private let cpuCounter = CPUUsage()

    /// Hardware sampling, only while the System tab is on screen.
    ///
    /// This used to poll CPU, RAM, brightness and battery every 5 s for the life of the
    /// app, although only the System tab displays the first three. Battery state —
    /// the one thing needed while the island is collapsed, for the charging banner —
    /// now arrives as an IOKit push notification instead.
    private var metricsTimer: AnyCancellable?
    private var isTabVisible = false
    private var powerSourceRunLoopSource: CFRunLoopSource?

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
        observePowerSources()
        refreshBattery()
    }

    deinit {
        metricsTimer?.cancel()
        if let source = powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
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

    // MARK: - Visibility

    /// Called by the view when the System tab is shown or hidden.
    func setTabVisible(_ visible: Bool) {
        guard visible != isTabVisible else { return }
        isTabVisible = visible

        guard visible else {
            metricsTimer?.cancel()
            metricsTimer = nil
            return
        }

        sampleMetrics()
        metricsTimer = Timer.publish(every: 2.0, tolerance: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.sampleMetrics()
            }
    }

    // MARK: - Battery

    /// Fires on plug/unplug and on capacity changes, so there's nothing to poll.
    private func observePowerSources() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context = context else { return }
            Unmanaged<SystemManager>.fromOpaque(context).takeUnretainedValue().refreshBattery()
        }

        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else {
            Log.system.error("Could not observe power sources; battery state will not update")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        powerSourceRunLoopSource = source
    }

    private func refreshBattery() {
        sampleQueue.async { [weak self] in
            guard let reading = SystemManager.readBattery() else { return }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.batteryPercentage = reading.percentage
                self.isBatteryCharging = reading.isCharging
                self.hasBatteryReading = true
            }
        }
    }

    private static func readBattery() -> (percentage: Int, isCharging: Bool)? {
        guard let snapshotRef = IOPSCopyPowerSourcesInfo() else { return nil }
        let snapshot = snapshotRef.takeRetainedValue()
        guard let sourcesRef = IOPSCopyPowerSourcesList(snapshot) else { return nil }
        let sources = sourcesRef.takeRetainedValue() as [CFTypeRef]

        for source in sources {
            guard let descriptionRef = IOPSGetPowerSourceDescription(snapshot, source) else { continue }
            let description = descriptionRef.takeUnretainedValue() as? [String: Any] ?? [:]
            let name = description[kIOPSNameKey] as? String ?? ""
            if name.contains("InternalBattery") {
                return (
                    description[kIOPSCurrentCapacityKey] as? Int ?? 100,
                    description[kIOPSIsChargingKey] as? Bool ?? false
                )
            }
        }
        return nil
    }

    // MARK: - CPU, RAM, brightness

    private func sampleMetrics() {
        sampleQueue.async { [weak self] in
            guard let self = self else { return }
            // Skip rather than queue up if a previous sample is somehow still running.
            guard !self.isSampling else { return }
            self.isSampling = true
            defer { self.isSampling = false }

            var brightness: Int?
            if let getBrightness = self.getBrightness {
                var currentBrightness: Float = 0.0
                if getBrightness(CGMainDisplayID(), &currentBrightness) == 0 {
                    brightness = Int(currentBrightness * 100.0)
                }
            }

            let cpu = self.cpuCounter.getCPUUsagePercentage()
            let ram = self.getMemoryUsagePercentage()

            DispatchQueue.main.async {
                if let brightness = brightness { self.systemBrightness = brightness }
                // nil while the counter takes a fresh baseline; keep the last value.
                if let cpu = cpu { self.cpuUsage = cpu }
                self.ramUsage = ram
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
    private var prevSampleDate: Date?

    /// A baseline older than this would average over the whole time the System tab was
    /// closed, which says nothing about load right now.
    private let maxBaselineAge: TimeInterval = 10

    /// Usage since the previous call, or `nil` when there is no recent baseline yet.
    func getCPUUsagePercentage() -> Int? {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var cpuInfo = host_cpu_load_info()

        let result = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        let now = Date()
        defer { prevSampleDate = now }
        guard let last = prevSampleDate, now.timeIntervalSince(last) <= maxBaselineAge else {
            prevCpuInfo = cpuInfo
            return nil
        }

        let userDiff = Double(cpuInfo.cpu_ticks.0 &- prevCpuInfo.cpu_ticks.0)
        let systemDiff = Double(cpuInfo.cpu_ticks.1 &- prevCpuInfo.cpu_ticks.1)
        let idleDiff = Double(cpuInfo.cpu_ticks.2 &- prevCpuInfo.cpu_ticks.2)
        let niceDiff = Double(cpuInfo.cpu_ticks.3 &- prevCpuInfo.cpu_ticks.3)

        let totalTicks = userDiff + systemDiff + idleDiff + niceDiff
        prevCpuInfo = cpuInfo

        if totalTicks > 0 {
            let activeTicks = userDiff + systemDiff + niceDiff
            return Int((activeTicks / totalTicks) * 100.0)
        }
        return 0
    }
}
