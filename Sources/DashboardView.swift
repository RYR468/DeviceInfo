import SwiftUI

struct DashboardView: View {
    @State private var monitor = SystemMonitor()

    var body: some View {
        NavigationStack {
            ScrollView {
                if let s = monitor.snapshot {
                    content(s)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                } else {
                    ProgressView("读取中…")
                        .frame(maxWidth: .infinity, minHeight: 240)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("设备信息")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { monitor.start() }
    }

    @ViewBuilder
    private func content(_ s: DeviceSnapshot) -> some View {
        VStack(spacing: 14) {
            CPUCard(usage: s.cpuUsage, measured: s.measured, cores: s.coreCount)
            MemoryCard(used: s.usedRAM, total: s.totalRAM, free: s.freeRAM, appAvail: s.appAvailRAM)
            StorageCard(used: s.totalStorage - s.freeStorage, total: s.totalStorage, free: s.freeStorage)
            DeviceInfoCard(snapshot: s)
        }
    }
}

// MARK: - 卡片

private struct CPUCard: View {
    let usage: Double
    let measured: Bool
    let cores: Int

    var body: some View {
        Card {
            HStack(spacing: 18) {
                Gauge(value: max(0, min(1, usage))) {
                    EmptyView()
                } currentValueLabel: {
                    Text(measured ? Fmt.percent(usage) : "…")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .gaugeStyle(.accessoryCircular)
                .scaleEffect(1.25)
                .frame(width: 90, height: 90)

                VStack(alignment: .leading, spacing: 4) {
                    Text("CPU 占用").font(.headline)
                    Text("\(cores) 个核心 · 系统级总负载")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !measured {
                        Text("首次采样中，约 1 秒后显示")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            }
        }
    }
}

private struct MemoryCard: View {
    let used: UInt64
    let total: UInt64
    let free: UInt64
    let appAvail: UInt64

    private var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("内存").font(.headline)
                    Spacer()
                    Text(Fmt.percent(fraction)).font(.subheadline).foregroundStyle(.secondary)
                }
                ProgressBar(value: fraction)
                HStack {
                    Label("\(Fmt.bytes(used)) 已用", systemImage: "memorychip")
                    Spacer()
                    Text("共 \(Fmt.bytes(total))").foregroundStyle(.secondary)
                }.font(.footnote)
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    Text("空闲 \(Fmt.bytes(free))").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("本 App 可申请 \(Fmt.bytes(appAvail))").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }
}

private struct StorageCard: View {
    let used: Int64
    let total: Int64
    let free: Int64

    private var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("存储").font(.headline)
                    Spacer()
                    Text(Fmt.percent(fraction)).font(.subheadline).foregroundStyle(.secondary)
                }
                ProgressBar(value: fraction)
                HStack {
                    Label("\(Fmt.bytes(used)) 已用", systemImage: "internaldrive")
                    Spacer()
                    Text("可用 \(Fmt.bytes(free))").foregroundStyle(.secondary)
                }.font(.footnote)
            }
        }
    }
}

private struct DeviceInfoCard: View {
    let snapshot: DeviceSnapshot

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Row(label: "机型", value: snapshot.modelName)
                Row(label: "代号", value: snapshot.machineId)
                Row(label: "系统", value: "iOS \(snapshot.osVersion)")
                Row(label: "电池", value: batteryText)
            }
        }
    }

    private var batteryText: String {
        switch snapshot.batteryState {
        case .charging:  return "\(batteryPercent) · 充电中"
        case .full:      return "满电"
        case .unplugged: return "\(batteryPercent) · 未充电"
        case .unknown:   return "未知"
        @unknown default: return "未知"
        }
    }
    private var batteryPercent: String {
        snapshot.batteryLevel >= 0 ? Fmt.percent(Double(snapshot.batteryLevel)) : "—"
    }
}

// MARK: - 通用组件

private struct Card<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ProgressBar: View {
    let value: Double // 0..1
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule().fill(tint)
                    .frame(width: geo.size.width * min(1, max(0, value)))
            }
        }
        .frame(height: 8)
    }
    private var tint: Color {
        switch value {
        case ..<0.7: return .green
        case ..<0.9: return .orange
        default:     return .red
        }
    }
}

private struct Row: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.body).monospacedDigit()
        }
        .font(.subheadline)
    }
}
