import Foundation

/// Structured VM metrics for gauge rendering.
struct VMMetrics: Equatable {
    var isRunning: Bool = false
    var status: String = "unknown"
    var arch: String = ""
    var cpus: String = ""
    var memoryAlloc: String = ""
    var diskAlloc: String = ""
    var runtime: String = ""
    var address: String = ""

    // Live (only when running):
    var cpuUsage: Double? = nil       // 0-100
    var loadAvg1: Double? = nil
    var loadAvg5: Double? = nil
    var loadAvg15: Double? = nil
    var ramUsed: String? = nil
    var ramTotal: String? = nil
    var ramAvail: String? = nil
    var ramUsedPct: Double? = nil     // 0-100
    var rootDiskUsed: String? = nil
    var rootDiskTotal: String? = nil
    var rootDiskPct: Double? = nil
    var dataDiskUsed: String? = nil
    var dataDiskTotal: String? = nil
    var dataDiskPct: Double? = nil
}

/// Separated status collections for sub-tab display.
struct StatusCollection {
    var metrics: VMMetrics = VMMetrics()
    var vmSections: [KubeStatus.Section] = []
    var dockerSections: [KubeStatus.Section] = []
    var kubeSections: [KubeStatus.Section] = []
}

/// Collects status from VM, Docker, K8s, and Disk into unified sections.
struct StatusCollector {

    static func run() -> StatusCollection {
        let metrics = collectVMMetrics()
        var collection = StatusCollection(metrics: metrics)

        // --- VM subsections ---
        // Dashboard card renders live metrics; no redundant text section needed.

        // --- Docker subsections ---
        collection.dockerSections.append(dockerDaemonSection(metrics.isRunning))
        collection.dockerSections.append(dockerStorageSection(metrics.isRunning))

        // --- K8s subsections ---
        if let kubeSections = KubeStatus.run() {
            collection.kubeSections = kubeSections
        }

        return collection
    }

    // MARK: - VM Metrics Collection

    private static func collectVMMetrics() -> VMMetrics {
        var m = VMMetrics()
        let list = ShellCapture.run(AppPaths.colima, args: ["list"], timeout: 15)
        let profile = AppPaths.colimaProfile

        for line in list.stdout.components(separatedBy: "\n").dropFirst() {
            let cols = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).filter { !$0.isEmpty }
            guard cols.first == Substring(profile) else { continue }
            if cols.count >= 2 { m.status = String(cols[1]) }
            if cols.count >= 3 { m.arch = String(cols[2]) }
            if cols.count >= 4 { m.cpus = String(cols[3]) }
            if cols.count >= 5 { m.memoryAlloc = String(cols[4]) }
            if cols.count >= 6 { m.diskAlloc = String(cols[5]) }
            if cols.count >= 7 { m.runtime = String(cols[6]) }
            if cols.count >= 8 { m.address = String(cols[7]) }
            break
        }

        m.isRunning = m.status.lowercased() == "running"
        guard m.isRunning else { return m }

        // Single SSH call: top + free + df for root + docker disk.
        let probe = ClusterOps.colimaSSHPublic(
            "top -bn1 | head -5; echo '___FREE___'; free -h; echo '___DF_ROOT___'; df -hP /; echo '___DF_DOCKER___'; df -hP /var/lib/docker"
        )
        let out = probe.stdout

        // Load average.
        if let loadRange = out.range(of: #"load average:\s*([\d.]+),\s*([\d.]+),\s*([\d.]+)"#, options: .regularExpression) {
            let nums = out[loadRange].components(separatedBy: CharacterSet(charactersIn: ", "))
                .compactMap { Double($0) }
            if nums.count >= 3 {
                m.loadAvg1 = nums[0]
                m.loadAvg5 = nums[1]
                m.loadAvg15 = nums[2]
            }
        }

        // CPU: idle% → used = 100 - idle.
        if let cpuLine = out.components(separatedBy: "\n").first(where: { $0.contains("%Cpu") }),
           let idleMatch = cpuLine.range(of: #"(\d+\.?\d*)\s*id"#, options: .regularExpression) {
            let idleStr = cpuLine[idleMatch].replacingOccurrences(of: " id", with: "")
            if let idle = Double(idleStr) {
                m.cpuUsage = 100.0 - idle
            }
        }

        // RAM from free -h.
        if let freeStart = out.range(of: "___FREE___"),
           let memLine = out[freeStart.upperBound...]
               .components(separatedBy: "\n")
               .first(where: { $0.hasPrefix("Mem:") }) {
            let memCols = memLine.split(whereSeparator: { $0 == " " || $0 == "\t" }).filter { !$0.isEmpty }
            if memCols.count >= 4 {
                m.ramUsed = String(memCols[2])
                m.ramTotal = String(memCols[1])
                if memCols.count >= 7 { m.ramAvail = String(memCols[6]) }
                // Parse percentage: used/(used+buff/cache) approx.
                if let used = parseHumanReadable(String(memCols[2])),
                   let total = parseHumanReadable(String(memCols[1])) {
                    m.ramUsedPct = (used / total) * 100.0
                }
            }
        }

        // Root disk.
        if let dfRootStart = out.range(of: "___DF_ROOT___") {
            parseDisk(out[dfRootStart.upperBound...], into: &m, isDocker: false)
        }

        // Docker disk.
        if let dfDockerStart = out.range(of: "___DF_DOCKER___") {
            parseDisk(out[dfDockerStart.upperBound...], into: &m, isDocker: true)
        }

        return m
    }

    private static func parseDisk(_ text: Substring, into m: inout VMMetrics, isDocker: Bool) {
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.contains("/") else { continue }
            let cols = t.split(whereSeparator: { $0 == " " }).filter { !$0.isEmpty }
            guard cols.count >= 6 else { continue }
            let used = String(cols[2])
            let total = String(cols[1])
            let pctStr = String(cols[4]).replacingOccurrences(of: "%", with: "")
            let pct = Double(pctStr)
            if isDocker {
                m.dataDiskUsed = used
                m.dataDiskTotal = total
                m.dataDiskPct = pct
            } else {
                m.rootDiskUsed = used
                m.rootDiskTotal = total
                m.rootDiskPct = pct
            }
            return
        }
    }

    private static func parseHumanReadable(_ s: String) -> Double? {
        // free -h uses GiB/MiB notation: "7.7Gi", "512Mi", "1024Ki"
        // Strip trailing "i" if present, then parse number + unit.
        var cleaned = s
        if cleaned.hasSuffix("i") { cleaned = String(cleaned.dropLast()) }
        guard let unit = cleaned.last, unit.isLetter else {
            return Double(cleaned)
        }
        let numStr = String(cleaned.dropLast())
        guard let val = Double(numStr) else { return nil }
        switch unit {
        case "G": return val * 1024
        case "M": return val
        case "K": return val / 1024
        case "T": return val * 1024 * 1024
        case "B": return val / (1024 * 1024)
        default: return val
        }
    }

    // MARK: - VM Summary Section (text fallback)

    private static func vmSummarySection(_ m: VMMetrics) -> KubeStatus.Section {
        let indicator = m.isRunning ? "✅" : "⛔"
        var lines: [String] = []
        lines.append("\(indicator) Status:    \(m.status)")
        lines.append("Arch:      \(m.arch)")
        if let cpu = m.cpuUsage {
            lines.append(String(format: "CPU:       %.0f%%  (%@ cores)", cpu, m.cpus))
        } else {
            lines.append("CPU:       \(m.cpus) cores (VM gestoppt)")
        }
        if let used = m.ramUsed, let total = m.ramTotal {
            lines.append("RAM:       \(used) used / \(total) total")
        } else {
            lines.append("Memory:    \(m.memoryAlloc) allocated")
        }
        if let used = m.rootDiskUsed, let total = m.rootDiskTotal, let pct = m.rootDiskPct {
            lines.append(String(format: "Root Disk: %@ / %@ (%.0f%%)", used, total, pct))
        }
        if let used = m.dataDiskUsed, let total = m.dataDiskTotal, let pct = m.dataDiskPct {
            lines.append(String(format: "Data Disk: %@ / %@ (%.0f%%)", used, total, pct))
        }
        lines.append("Runtime:   \(m.runtime)")
        if !m.address.isEmpty { lines.append("Address:   \(m.address)") }

        return KubeStatus.Section(
            title: L10n.tr("status.vm"),
            raw: lines.joined(separator: "\n"),
            collapsedByDefault: false
        )
    }

    // MARK: - Docker

    private static func dockerDaemonSection(_ vmRunning: Bool) -> KubeStatus.Section {
        guard vmRunning else {
            return KubeStatus.Section(
                title: L10n.tr("status.daemon"),
                raw: L10n.tr("status.vm_down"),
                collapsedByDefault: false
            )
        }

        let daemon = ClusterOps.colimaSSHPublic("sudo systemctl is-active docker")
        let isActive = daemon.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "active"

        // Also grab container count.
        let containers = ClusterOps.colimaSSHPublic("docker ps -q | wc -l")
        let runningCount = containers.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        var lines: [String] = []
        lines.append(isActive ? "✅ Daemon: active" : "⛔ Daemon: inactive")
        lines.append("Running containers: \(runningCount)")

        return KubeStatus.Section(
            title: L10n.tr("status.daemon"),
            raw: lines.joined(separator: "\n"),
            collapsedByDefault: false
        )
    }

    private static func dockerStorageSection(_ vmRunning: Bool) -> KubeStatus.Section {
        guard vmRunning else {
            return KubeStatus.Section(
                title: L10n.tr("status.docker_storage"),
                raw: L10n.tr("status.vm_down"),
                collapsedByDefault: true
            )
        }

        let df = ClusterOps.colimaSSHPublic("docker system df")
        let dfTrimmed = df.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        return KubeStatus.Section(
            title: L10n.tr("status.docker_storage"),
            raw: dfTrimmed.isEmpty ? "—" : dfTrimmed,
            collapsedByDefault: false
        )
    }
}
