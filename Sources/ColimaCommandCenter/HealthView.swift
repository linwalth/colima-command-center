import SwiftUI

struct HealthView: View {
    @ObservedObject var viewModel: HealthViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Picker("", selection: $viewModel.subTab) {
                Text(L10n.tr("status.subtab.vm")).tag(0)
                Text(L10n.tr("status.subtab.docker")).tag(1)
                Text(L10n.tr("status.subtab.k8s")).tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.top, 8)

            switch viewModel.subTab {
            case 0:
                VMTab(viewModel: viewModel)
            case 1:
                DockerTab(viewModel: viewModel)
            default:
                K8sTab(viewModel: viewModel)
            }
        }
        .frame(minWidth: 560, idealWidth: 720, minHeight: 360)
    }

    private var header: some View {
        HStack {
            if let date = viewModel.lastUpdated {
                Text(L10n.tr("health.updated", DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .medium)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(L10n.tr("health.refresh")) { viewModel.refresh() }
                .keyboardShortcut("r", modifiers: [.command])
        }
        .padding(10)
    }
}

// MARK: - VM Tab

private struct VMTab: View {
    @ObservedObject var viewModel: HealthViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DashboardCard(metrics: viewModel.vmMetrics, loadHistory1: viewModel.loadHistory1, loadHistory5: viewModel.loadHistory5, loadHistory15: viewModel.loadHistory15)
                SectionListView(sections: viewModel.vmSections, viewModel: viewModel)
            }
            .padding()
        }
    }
}

// MARK: - Docker Tab

private struct DockerTab: View {
    @ObservedObject var viewModel: HealthViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DockerOverviewCard(metrics: viewModel.vmMetrics)

                // Cleanup button
                if viewModel.vmMetrics.isRunning {
                    VStack(alignment: .leading, spacing: 8) {
                        Button(action: { viewModel.cleanDocker() }) {
                            Label(L10n.tr("status.cleanup_docker"), systemImage: "trash")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(viewModel.isCleaningDocker)

                        if viewModel.isCleaningDocker {
                            ProgressView("Bereinige...")
                                .controlSize(.small)
                        }
                        if let result = viewModel.dockerCleanResult {
                            Text(result)
                                .font(.system(.caption, design: .monospaced))
                                .padding(8)
                                .background(Color.secondary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }

                SectionListView(sections: viewModel.dockerSections, viewModel: viewModel)
            }
            .padding()
        }
    }
}

// MARK: - K8s Tab

private struct K8sTab: View {
    @ObservedObject var viewModel: HealthViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button(L10n.tr("health.expand_all")) { viewModel.collapsed.removeAll() }
                    Button(L10n.tr("health.collapse_all")) {
                        viewModel.collapsed = Set(viewModel.kubeSections.map { $0.id })
                    }
                    Spacer()
                    Button(action: { viewModel.cleanK8s() }) {
                        Label(L10n.tr("status.cleanup_k8s"), systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(viewModel.isCleaningK8s)
                }

                if viewModel.isCleaningK8s {
                    ProgressView("Bereinige...")
                        .controlSize(.small)
                }
                if let result = viewModel.k8sCleanResult {
                    Text(result)
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                if viewModel.kubeSections.isEmpty {
                    Text(L10n.tr("health.unavailable_hint"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    SectionListView(sections: viewModel.kubeSections, viewModel: viewModel)
                }
            }
            .padding()
        }
    }
}

// MARK: - Shared Section List

private struct SectionListView: View {
    let sections: [KubeStatus.Section]
    @ObservedObject var viewModel: HealthViewModel

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(sections) { section in
                CollapsibleSection(
                    title: section.title,
                    raw: section.raw,
                    isCollapsed: viewModel.collapsed.contains(section.title),
                    onToggle: { viewModel.toggleCollapsed(section.title) }
                )
            }
        }
    }
}

// MARK: - Dashboard Card (VM)

private struct DashboardCard: View {
    let metrics: VMMetrics
    let loadHistory1: [Double]
    let loadHistory5: [Double]
    let loadHistory15: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(metrics.isRunning ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(metrics.isRunning ? Color.green.opacity(0.3) : Color.red.opacity(0.3), lineWidth: 4)
                            .scaleEffect(metrics.isRunning ? 1.3 : 1.0)
                            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: metrics.isRunning)
                    )
                Text(metrics.isRunning ? "Running" : "Stopped")
                    .font(.title2.bold())
                Spacer()
                if metrics.isRunning {
                    Text("\(metrics.arch) • \(metrics.cpus) CPU • \(metrics.memoryAlloc)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if metrics.isRunning {
                HStack(spacing: 24) {
                    MetricGauge(title: "CPU", value: metrics.cpuUsage,
                                label: metrics.cpuUsage.map { String(format: "%.0f%%", $0) } ?? "—",
                                color: gaugeColor(metrics.cpuUsage))
                    MetricGauge(title: "RAM", value: metrics.ramUsedPct,
                                label: ramLabel, color: gaugeColor(metrics.ramUsedPct))
                    MetricGauge(title: "Data Disk", value: metrics.dataDiskPct,
                                label: diskLabel(metrics.dataDiskUsed, metrics.dataDiskTotal),
                                color: gaugeColor(metrics.dataDiskPct))
                }
                .frame(height: 120)

                VStack(spacing: 8) {
                    if let pct = metrics.dataDiskPct {
                        ProgressBar(label: "Data Disk", value: pct,
                                    detail: "\(metrics.dataDiskUsed ?? "?") / \(metrics.dataDiskTotal ?? "?")")
                    }
                    if let pct = metrics.rootDiskPct {
                        ProgressBar(label: "Root Disk", value: pct,
                                    detail: "\(metrics.rootDiskUsed ?? "?") / \(metrics.rootDiskTotal ?? "?")")
                    }
                }

                // Load average sparkline graph
                if !loadHistory1.isEmpty {
                    LoadSparkline(history1: loadHistory1, history5: loadHistory5, history15: loadHistory15,
                                  load1: metrics.loadAvg1, load5: metrics.loadAvg5, load15: metrics.loadAvg15,
                                  cpuCount: Int(metrics.cpus) ?? 1)
                        .frame(height: 80)
                }

                HStack {
                    Label(metrics.runtime, systemImage: "gearshape.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !metrics.address.isEmpty {
                        Label(metrics.address, systemImage: "network")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("VM gestoppt — Starte die VM für Live-Metriken")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var ramLabel: String {
        guard let used = metrics.ramUsed, let total = metrics.ramTotal else { return "—" }
        return "\(used) / \(total)"
    }

    private var loadLabel: String {
        guard let l1 = metrics.loadAvg1, let l5 = metrics.loadAvg5, let l15 = metrics.loadAvg15 else { return "" }
        return "Load: \(String(format: "%.2f", l1)) / \(String(format: "%.2f", l5)) / \(String(format: "%.2f", l15))"
    }

    private func diskLabel(_ used: String?, _ total: String?) -> String {
        guard let used, let total else { return "—" }
        return "\(used) / \(total)"
    }

    private func gaugeColor(_ value: Double?) -> Color {
        guard let v = value else { return .gray }
        if v < 60 { return .green }
        if v < 80 { return .yellow }
        return .red
    }
}

// MARK: - Load Sparkline Graph

private struct LoadSparkline: View {
    let history1: [Double]
    let history5: [Double]
    let history15: [Double]
    let load1: Double?
    let load5: Double?
    let load15: Double?
    let cpuCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Load Average")
                    .font(.caption.weight(.medium))
                Spacer()
            }

            // Current values with legend colors
            HStack(spacing: 16) {
                LoadLegend(color: .blue, label: "1m", value: load1)
                LoadLegend(color: .purple, label: "5m", value: load5)
                LoadLegend(color: .orange, label: "15m", value: load15)
                Spacer()
                Text("\(cpuCount) cores")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack {
                    // Reference line at load = cpuCount (full utilization)
                    Path { path in
                        let y = geo.size.height * (1 - CGFloat(cpuCount) / CGFloat(maxScale))
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    // 15m line (slowest, thickest)
                    sparklinePath(history15, geo: geo)
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

                    // 5m line
                    sparklinePath(history5, geo: geo)
                        .stroke(Color.purple, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

                    // 1m line (fastest, prominent)
                    sparklinePath(history1, geo: geo)
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
        }
    }

    private func sparklinePath(_ hist: [Double], geo: GeometryProxy) -> Path {
        Path { path in
            guard hist.count > 1 else { return }
            let step = geo.size.width / CGFloat(hist.count - 1)
            for (i, val) in hist.enumerated() {
                let x = CGFloat(i) * step
                let normalized = min(val / maxScale, 1.0)
                let y = geo.size.height * (1 - CGFloat(normalized))
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
        }
    }

    private var maxScale: Double {
        let peak = max(history1.max() ?? 0, history5.max() ?? 0, history15.max() ?? 0)
        return max(Double(cpuCount) * 1.5, peak * 1.2, 1.0)
    }
}

private struct LoadLegend: View {
    let color: Color
    let label: String
    let value: Double?

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value.map { String(format: "%.2f", $0) } ?? "—")
                .font(.caption2.weight(.medium))
                .monospacedDigit()
        }
    }
}

// MARK: - Docker Overview Card

private struct DockerOverviewCard: View {
    let metrics: VMMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: metrics.isRunning ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(metrics.isRunning ? .green : .red)
                    .font(.title2)
                Text("Docker")
                    .font(.title2.bold())
                Spacer()
            }
            if !metrics.isRunning {
                Text("VM gestoppt — Docker nicht verfügbar")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Circular Gauge

private struct MetricGauge: View {
    let title: String
    let value: Double?
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat((value ?? 0) / 100))
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: value)
                VStack {
                    Text(label)
                        .font(.system(.headline, design: .rounded).bold())
                    if let v = value {
                        Text(String(format: "%.0f%%", v))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 80, height: 80)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Linear Progress Bar

private struct ProgressBar: View {
    let label: String
    let value: Double
    let detail: String

    private var color: Color {
        if value < 60 { return .green }
        if value < 80 { return .yellow }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.caption.weight(.medium))
                Spacer()
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.12))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color)
                            .frame(width: geo.size.width * CGFloat(value / 100))
                            .animation(.easeInOut(duration: 0.5), value: value)
                    }
            }
            .frame(height: 10)
        }
    }
}

// MARK: - Collapsible Section

private struct CollapsibleSection: View {
    let title: String
    let raw: String
    let isCollapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    Text(title)
                        .font(.headline)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.bottom, 4)

            if !isCollapsed {
                Text(raw)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
