import Foundation
import UIKit
import Darwin
import os
import Observation

/// 一次采样的设备快照（值类型，供 UI 渲染）
struct DeviceSnapshot: Hashable {
    let modelName: String          // "iPhone 15 Pro"
    let machineId: String          // "iPhone16,2"
    let osVersion: String
    let coreCount: Int
    let totalRAM: UInt64
    let usedRAM: UInt64            // 系统级已用（active+wired+compressed）
    let freeRAM: UInt64            // 系统级空闲（free+inactive）
    let appAvailRAM: UInt64        // 本 App 可申请的内存预算（os_proc_available_memory）
    let totalStorage: Int64
    let freeStorage: Int64
    let batteryLevel: Float        // 0..1，-1 未知
    let batteryState: UIDevice.BatteryState
    let cpuUsage: Double           // 0..1，尽力值（Mach 两次采样）
    let measured: Bool             // CPU 是否已完成首次两次采样
    let timestamp: Date
}

/// 机型代号 → 市场名（覆盖带 Action Button 的机型 + 常见型号，其余回退原始代号）
private let machineNames: [String: String] = [
    "iPhone16,1": "iPhone 15 Pro",
    "iPhone16,2": "iPhone 15 Pro Max",
    "iPhone17,1": "iPhone 16 Pro",
    "iPhone17,2": "iPhone 16 Pro Max",
    "iPhone17,3": "iPhone 16",
    "iPhone17,4": "iPhone 16 Plus"
]

/// 系统信息采集器。@Observable 供 SwiftUI 直接订阅；start/refresh 跑在主线程。
@Observable
final class SystemMonitor {
    private(set) var snapshot: DeviceSnapshot?

    private var timer: Timer?
    private var prevCPU: (inUse: UInt64, total: UInt64)?

    @MainActor
    func start() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    @MainActor
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @MainActor
    func refresh() {
        snapshot = DeviceSnapshot(
            modelName: machineName(),
            machineId: machineId(),
            osVersion: osVersion(),
            coreCount: ProcessInfo.processInfo.activeProcessorCount,
            totalRAM: ProcessInfo.processInfo.physicalMemory,
            usedRAM: vmInfo()?.used ?? 0,
            freeRAM: vmInfo()?.free ?? 0,
            appAvailRAM: UInt64(os_proc_available_memory()),
            totalStorage: storage().total,
            freeStorage: storage().free,
            batteryLevel: UIDevice.current.batteryLevel,
            batteryState: UIDevice.current.batteryState,
            cpuUsage: cpuUsage(),
            measured: prevCPU != nil,
            timestamp: Date()
        )
    }

    // MARK: - 基本信息

    private func machineId() -> String {
        var uts = utsname()
        uname(&uts)
        return withUnsafePointer(to: &uts.machine) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: uts.machine)) {
                String(cString: $0)
            }
        }
    }

    private func machineName() -> String { machineNames[machineId()] ?? machineId() }

    private func osVersion() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    // MARK: - 存储（公开 API，准确）

    private func storage() -> (total: Int64, free: Int64) {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]
        guard let v = try? url.resourceValues(forKeys: keys) else { return (0, 0) }
        let total = Int64(v.volumeTotalCapacity ?? 0)
        let free = Int64(v.volumeAvailableCapacityForImportantUsage ?? 0)
        return (total, free)
    }

    // MARK: - 内存（系统级，Mach host_statistics64）

    private func vmInfo() -> (free: UInt64, used: UInt64)? {
        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS, pageSize > 0 else { return nil }

        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        var info = vm_statistics64_data_t()
        let kr = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &size)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let ps = UInt64(pageSize)
        let free = (UInt64(info.free_count) + UInt64(info.inactive_count)) * ps
        let used = (UInt64(info.active_count) + UInt64(info.wire_count) + UInt64(info.compressor_page_count)) * ps
        return (free, used)
    }

    // MARK: - CPU（Mach host_processor_info，两次采样算 delta）

    private func cpuUsage() -> Double {
        guard let now = sampleCPUTicks() else { return 0 }
        defer { prevCPU = now }
        guard let prev = prevCPU else { return 0 }
        let totalDelta = now.total > prev.total ? (now.total - prev.total) : 0
        guard totalDelta > 0 else { return 0 }
        let inUseDelta = now.inUse > prev.inUse ? (now.inUse - prev.inUse) : 0
        return Double(inUseDelta) / Double(totalDelta)
    }

    private func sampleCPUTicks() -> (inUse: UInt64, total: UInt64)? {
        var numCPU: natural_t = 0
        var numCPUInfo: mach_msg_type_number_t = 0
        var cpuInfo: processor_info_array_t? = nil

        let kr = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPU,
            &cpuInfo,
            &numCPUInfo
        )
        guard kr == KERN_SUCCESS, let info = cpuInfo else { return nil }
        defer {
            // 释放 Mach 返回的缓冲区，避免每次采样泄漏
            let size = vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), size)
        }

        var inUse: UInt64 = 0
        var total: UInt64 = 0
        // CPU_STATE_* 常量是 Int32（C 的 int），数组下标要 Int，先统一转换
        let sUser   = Int(CPU_STATE_USER)
        let sSystem = Int(CPU_STATE_SYSTEM)
        let sNice   = Int(CPU_STATE_NICE)
        let sIdle   = Int(CPU_STATE_IDLE)
        let sMax    = Int(CPU_STATE_MAX)
        for core in 0..<Int(numCPU) {
            let base   = core * sMax
            let user   = UInt64(info[base + sUser])
            let system = UInt64(info[base + sSystem])
            let nice   = UInt64(info[base + sNice])
            let idle   = UInt64(info[base + sIdle])
            inUse += user + system + nice
            total += user + system + nice + idle
        }
        return (inUse, total)
    }
}
