import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var stats: SystemStats

    var body: some View {
        let s = stats.now
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                GaugeTile(title: "CPU", symbol: "cpu", value: s.cpu, color: loadColor(s.cpu),
                          detail: "user \(pct(s.cpuUser)) · sys \(pct(s.cpuSystem))") {
                    Sparkline(values: stats.cpuHistory, maxValue: 1, color: loadColor(s.cpu))
                }
                GaugeTile(title: "Memory", symbol: "memorychip", value: s.memory, color: loadColor(s.memory),
                          detail: "\(bytes(s.memoryUsed)) / \(bytes(s.memoryTotal))"
                              + (s.swapUsed > 0 ? "\nswap \(bytes(s.swapUsed))" : "")) {
                    Sparkline(values: stats.memoryHistory, maxValue: 1, color: loadColor(s.memory))
                }
                GaugeTile(title: "GPU", symbol: "square.stack.3d.up.fill", value: s.gpu ?? 0,
                          color: loadColor(s.gpu ?? 0), label: s.gpu == nil ? "n/a" : nil,
                          detail: s.gpuMemory.map { "mem \(bytes($0))" } ?? "") {
                    Sparkline(values: stats.gpuHistory, maxValue: 1, color: loadColor(s.gpu ?? 0))
                }
                NetworkTile(down: s.netDown, up: s.netUp, downHistory: stats.downHistory, upHistory: stats.upHistory)
                GaugeTile(title: "Storage", symbol: "internaldrive.fill", value: s.disk, color: loadColor(s.disk),
                          detail: "\(bytes(s.diskFree)) free\nof \(bytes(s.diskTotal))") {
                    EmptyView()
                }
            }
            footer(s)
        }
        // Values change every second; animating them would keep Core Animation busy the whole time.
        .transaction { $0.animation = nil }
        .onAppear { stats.resume() }
        .onDisappear { stats.pause() }
    }

    private func footer(_ s: SystemStats.Snapshot) -> some View {
        HStack(spacing: 14) {
            Label("up \(uptime(s.uptime))", systemImage: "clock")
            Label(String(format: "load %.2f", s.load), systemImage: "chart.line.uptrend.xyaxis")
            Label(thermal(s.thermal), systemImage: "thermometer.medium")
                .foregroundStyle(s.thermal == .nominal ? Color.gray : s.thermal == .fair ? .yellow : .red)
            if let level = s.battery {
                Label("\(level)%\(s.charging ? " · on power" : "")",
                      systemImage: s.charging ? "battery.100.bolt" : batterySymbol(level))
            }
            Spacer()
        }
        .font(.system(size: 10))
        .foregroundStyle(.gray)
        .labelStyle(CompactLabelStyle())
    }

    private func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    private func thermal(_ t: ProcessInfo.ThermalState) -> String {
        switch t {
        case .nominal: return "cool"
        case .fair: return "warm"
        case .serious: return "hot"
        case .critical: return "critical"
        @unknown default: return "—"
        }
    }

    private func uptime(_ t: TimeInterval) -> String {
        let minutes = Int(t) / 60
        let d = minutes / 1440, h = (minutes % 1440) / 60, m = minutes % 60
        return d > 0 ? "\(d)d \(h)h" : h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

func loadColor(_ v: Double) -> Color {
    v < 0.6 ? .green : v < 0.85 ? .yellow : .red
}

func bytes<T: BinaryInteger>(_ value: T) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
}

func rate(_ bytesPerSecond: Double) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .decimal) + "/s"
}

// MARK: - Pieces

private struct Tile<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.gray)
                .labelStyle(CompactLabelStyle())
            content
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}

private struct GaugeTile<Chart: View>: View {
    let title: String
    let symbol: String
    let value: Double
    let color: Color
    var label: String? = nil
    let detail: String
    @ViewBuilder var chart: Chart

    var body: some View {
        Tile(title: title, symbol: symbol) {
            HStack(spacing: 6) {
                Ring(value: value, color: color, label: label ?? "\(Int((value * 100).rounded()))%")
                    .frame(width: 40, height: 40)
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            chart.frame(minHeight: 18, maxHeight: .infinity)
        }
    }
}

private struct NetworkTile: View {
    let down: Double
    let up: Double
    let downHistory: [Double]
    let upHistory: [Double]

    var body: some View {
        Tile(title: "Network", symbol: "network") {
            VStack(alignment: .leading, spacing: 3) {
                Label(rate(down), systemImage: "arrow.down")
                    .foregroundStyle(.cyan)
                Label(rate(up), systemImage: "arrow.up")
                    .foregroundStyle(.orange)
            }
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .labelStyle(CompactLabelStyle())
            .frame(height: 40, alignment: .leading)
            let peak = max(downHistory.max() ?? 0, upHistory.max() ?? 0, 1024)
            ZStack {
                Sparkline(values: downHistory, maxValue: peak, color: .cyan)
                Sparkline(values: upHistory, maxValue: peak, color: .orange)
            }
            .frame(minHeight: 18, maxHeight: .infinity)
        }
    }
}

private struct Ring: View {
    let value: Double
    let color: Color
    let label: String

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.1), lineWidth: 4.5)
            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label)
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .minimumScaleFactor(0.7)
        }
    }
}

/// Filled line chart of the last minute.
struct Sparkline: View {
    let values: [Double]
    let maxValue: Double
    let color: Color

    var body: some View {
        GeometryReader { g in
            let n = 60
            let step = g.size.width / CGFloat(n - 1)
            let points: [CGPoint] = values.suffix(n).enumerated().map { i, v in
                let x = CGFloat(n - min(values.count, n) + i) * step
                let y = g.size.height * (1 - CGFloat(min(v / max(maxValue, .ulpOfOne), 1)))
                return CGPoint(x: x, y: y)
            }
            if let first = points.first, let last = points.last {
                Path { p in
                    p.move(to: CGPoint(x: first.x, y: g.size.height))
                    points.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: last.x, y: g.size.height))
                    p.closeSubpath()
                }
                .fill(color.opacity(0.22))
                Path { p in
                    p.move(to: first)
                    points.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(color, lineWidth: 1.2)
            }
        }
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}
